import AppKit
import ApplicationServices
import Foundation

enum AXClientError: LocalizedError {
    case notTrusted
    case appNotRunning(String)
    case noWindow
    case attendeeListNotFound
    case cannotScroll

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Accessibility permission is required. Enable your terminal in System Settings → Privacy & Security → Accessibility, then run this command again."
        case .appNotRunning(let bundleID):
            return "No running app has bundle identifier \(bundleID). Open the Summit app and its Attendees screen first."
        case .noWindow:
            return "The Summit app is running, but no accessible window was found."
        case .attendeeListNotFound:
            return "Could not find the attendee list. Open All attendees in the app and try again."
        case .cannotScroll:
            return "The attendee list was found, but macOS did not expose a usable scroll action."
        }
    }
}

final class AXClient {
    private let application: AXUIElement

    init(bundleIdentifier: String, promptForPermission: Bool = true) throws {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptForPermission] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw AXClientError.notTrusted }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            throw AXClientError.appNotRunning(bundleIdentifier)
        }
        application = AXUIElementCreateApplication(running.processIdentifier)
    }

    func extractAttendees(
        maximum: Int,
        pauseMilliseconds: UInt32,
        progress: (Int) -> Void
    ) throws -> [Attendee] {
        guard let window: AXUIElement = attribute(application, kAXFocusedWindowAttribute) ?? firstWindow() else {
            throw AXClientError.noWindow
        }

        var attendees: [String: Attendee] = [:]
        var orderedNames: [String] = []
        var stablePasses = 0
        var scrollTarget: AXUIElement?

        while attendees.count < maximum {
            let elements = descendants(of: window, maximumDepth: 12)
            for element in elements {
                guard let role: String = attribute(element, kAXRoleAttribute), role == kAXButtonRole as String else { continue }
                guard let label = bestLabel(for: element), let attendee = Attendee.parse(accessibilityLabel: label) else { continue }
                let key = normalize(attendee.name)
                guard attendees[key] == nil else { continue }
                attendees[key] = attendee
                orderedNames.append(key)
            }

            progress(attendees.count)
            if attendees.count >= maximum { break }

            if scrollTarget == nil {
                scrollTarget = findScrollableElement(in: elements)
            }
            guard let target = scrollTarget else { throw AXClientError.attendeeListNotFound }

            let before = attendees.count
            guard scrollDown(target) else { throw AXClientError.cannotScroll }
            usleep(pauseMilliseconds * 1_000)

            let refreshed = descendants(of: window, maximumDepth: 12)
            for element in refreshed {
                guard let role: String = attribute(element, kAXRoleAttribute), role == kAXButtonRole as String else { continue }
                guard let label = bestLabel(for: element), let attendee = Attendee.parse(accessibilityLabel: label) else { continue }
                let key = normalize(attendee.name)
                guard attendees[key] == nil else { continue }
                attendees[key] = attendee
                orderedNames.append(key)
            }

            if attendees.count == before {
                stablePasses += 1
            } else {
                stablePasses = 0
            }
            if stablePasses >= 4 { break }
        }

        return orderedNames.compactMap { attendees[$0] }
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
            if actions.contains(where: { isScrollDownAction($0, on: element) }) {
                return element
            }
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
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}
