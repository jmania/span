import AppKit
@preconcurrency import ApplicationServices
import Foundation

public enum AXClientError: LocalizedError {
    case notTrusted
    case appNotRunning(String)
    case noWindow
    case attendeeListNotFound
    case cannotScroll

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Allow Small World in System Settings → Privacy & Security → Accessibility, then try again."
        case .appNotRunning:
            return "Open Lenny & Friends and navigate to Attendees → All attendees first."
        case .noWindow:
            return "Lenny & Friends is running, but its window could not be read."
        case .attendeeListNotFound:
            return "The attendee list could not be found. Open All attendees and try again."
        case .cannotScroll:
            return "The attendee list was found, but this version of the app does not expose a usable scroll action."
        }
    }
}

public final class AXClient: @unchecked Sendable {
    private let application: AXUIElement

    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func isAppInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public static func isAppRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    public init(bundleIdentifier: String, promptForPermission: Bool = false) throws {
        guard Self.isAccessibilityTrusted(prompt: promptForPermission) else { throw AXClientError.notTrusted }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            throw AXClientError.appNotRunning(bundleIdentifier)
        }
        application = AXUIElementCreateApplication(running.processIdentifier)
    }

    public func extractAttendees(
        maximum: Int,
        pauseMilliseconds: UInt32,
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> [Attendee] {
        guard let window: AXUIElement = attribute(application, kAXFocusedWindowAttribute) ?? firstWindow() else {
            throw AXClientError.noWindow
        }

        var attendees: [String: Attendee] = [:]
        var orderedKeys: [String] = []
        var stablePasses = 0
        var scrollTarget: AXUIElement?

        while attendees.count < maximum {
            collectAttendees(from: window, into: &attendees, orderedKeys: &orderedKeys)
            progress(attendees.count)
            if attendees.count >= maximum { break }

            let elements = descendants(of: window, maximumDepth: 12)
            if scrollTarget == nil { scrollTarget = findScrollableElement(in: elements) }
            guard let target = scrollTarget else { throw AXClientError.attendeeListNotFound }

            let before = attendees.count
            guard scrollDown(target) else { throw AXClientError.cannotScroll }
            usleep(pauseMilliseconds * 1_000)
            collectAttendees(from: window, into: &attendees, orderedKeys: &orderedKeys)

            stablePasses = attendees.count == before ? stablePasses + 1 : 0
            if stablePasses >= 4 { break }
        }

        return orderedKeys.compactMap { attendees[$0] }
    }

    private func collectAttendees(
        from window: AXUIElement,
        into attendees: inout [String: Attendee],
        orderedKeys: inout [String]
    ) {
        for element in descendants(of: window, maximumDepth: 12) {
            guard let role: String = attribute(element, kAXRoleAttribute), role == kAXButtonRole as String else { continue }
            guard let label = bestLabel(for: element), let attendee = Attendee.parse(accessibilityLabel: label) else { continue }
            let key = normalize(attendee.sourceLabel)
            guard attendees[key] == nil else { continue }
            attendees[key] = attendee
            orderedKeys.append(key)
        }
    }

    private func firstWindow() -> AXUIElement? {
        let windows: [AXUIElement]? = attribute(application, kAXWindowsAttribute)
        return windows?.first
    }

    private func bestLabel(for element: AXUIElement) -> String? {
        let candidates: [String?] = [
            attribute(element, kAXDescriptionAttribute),
            attribute(element, kAXTitleAttribute),
            attribute(element, kAXValueAttribute),
        ]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func descendants(of root: AXUIElement, maximumDepth: Int) -> [AXUIElement] {
        var result: [AXUIElement] = [root]
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count {
            let (element, depth) = queue[index]
            index += 1
            guard depth < maximumDepth else { continue }
            let children: [AXUIElement]? = attribute(element, kAXChildrenAttribute)
            for child in children ?? [] {
                result.append(child)
                queue.append((child, depth + 1))
            }
        }
        return result
    }

    private func findScrollableElement(in elements: [AXUIElement]) -> AXUIElement? {
        for element in elements {
            let actions = actionNames(of: element)
            if actions.contains(where: { isScrollDownAction($0, on: element) }) { return element }
        }
        for element in elements {
            let role: String? = attribute(element, kAXRoleAttribute)
            if role == kAXScrollAreaRole as String { return element }
        }
        return nil
    }

    private func scrollDown(_ element: AXUIElement) -> Bool {
        let actions = actionNames(of: element)
        for action in actions where isScrollDownAction(action, on: element) {
            if AXUIElementPerformAction(element, action as CFString) == .success { return true }
        }

        if let bar: AXUIElement = attribute(element, kAXVerticalScrollBarAttribute),
           let current: Double = numericAttribute(bar, kAXValueAttribute),
           let maximum: Double = numericAttribute(bar, kAXMaxValueAttribute) {
            let next = min(maximum, current + max(maximum * 0.035, 0.01))
            return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, next as CFTypeRef) == .success
        }
        return false
    }

    private func isScrollDownAction(_ action: String, on element: AXUIElement) -> Bool {
        var description: CFString?
        _ = AXUIElementCopyActionDescription(element, action as CFString, &description)
        let searchable = [action, description as String?].compactMap { $0 }.joined(separator: " ")
        let normalized = searchable.lowercased().replacingOccurrences(of: " ", with: "")
        return normalized.contains("scroll") && normalized.contains("down")
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private func numericAttribute(_ element: AXUIElement, _ name: String) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}
