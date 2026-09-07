import AppKit
@preconcurrency import ApplicationServices
import Foundation

public enum AXClientError: LocalizedError {
    case notTrusted
    case appNotRunning(String)
    case noWindow
    case attendeeListNotFound
    case cannotScroll
    case noAttendees

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Allow Span in System Settings → Privacy & Security → Accessibility, then try again."
        case .appNotRunning:
            return "Open Lenny & Friends and navigate to Attendees → All attendees first."
        case .noWindow:
            return "Lenny & Friends is running, but its window could not be read."
        case .attendeeListNotFound:
            return "The attendee list could not be found. Open All attendees and try again."
        case .cannotScroll:
            return "The attendee list was found, but this version of the app does not expose a usable scroll action."
        case .noAttendees:
            return "No attendee profiles were found. In Lenny & Friends, open Attendees → All attendees, clear any search or filter, and wait for the names to appear. Then return to Span and try Collect attendees again. Your existing data has not been changed."
        }
    }
}

public final class AXClient: @unchecked Sendable {
    private let application: AXUIElement
    private var trace: [String] = []

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
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .sorted {
                // Some Catalyst/iOS installs briefly expose more than one
                // process with the same bundle identifier. Prefer the regular,
                // fully launched UI process so we do not read an extension or
                // a stale helper with an empty accessibility tree.
                if $0.activationPolicy != $1.activationPolicy {
                    return $0.activationPolicy == .regular
                }
                if $0.isFinishedLaunching != $1.isFinishedLaunching {
                    return $0.isFinishedLaunching
                }
                return $0.processIdentifier > $1.processIdentifier
            }
        guard let running = candidates.first else {
            throw AXClientError.appNotRunning(bundleIdentifier)
        }
        application = AXUIElementCreateApplication(running.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 3)
    }

    public func extractAttendees(
        maximum: Int,
        pauseMilliseconds: UInt32,
        recentAttendees: @escaping @Sendable ([Attendee]) -> Void = { _ in },
        stage: @escaping @Sendable (String) -> Void = { _ in },
        diagnosticsURL: URL? = nil,
        progress: @escaping @Sendable (Int) -> Void
    ) throws -> [Attendee] {
        trace = ["Span collection diagnostics — no attendee names or contact data"]
        defer {
            if let diagnosticsURL {
                try? FileManager.default.createDirectory(at: diagnosticsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? trace.joined(separator: "\n").write(to: diagnosticsURL, atomically: true, encoding: .utf8)
            }
        }
        let source = LiveDirectorySource(client: self, pauseMilliseconds: max(250, pauseMilliseconds))
        do {
            let result = try DirectoryScan.run(source: source, maximum: maximum, stage: stage) { attendees in
                recentAttendees(Array(attendees.suffix(3)))
                progress(attendees.count)
            }
            record("Completed: \(result.count)")
            return result
        } catch {
            record("Stopped: \(error.localizedDescription)")
            throw error
        }
    }

    private func record(_ message: String) {
        if trace.count < 10_000 { trace.append("\(Date().timeIntervalSince1970): \(message)") }
    }

    private func rows(in container: AXUIElement) -> [Attendee] {
        rows(in: descendants(of: container, maximumDepth: 16))
    }

    private func rows(in elements: [AXUIElement]) -> [Attendee] {
        var seen = Set<String>()
        return elements.compactMap { child in
            let role: String? = attribute(child, kAXRoleAttribute)
            guard role == kAXButtonRole as String,
                  let label = bestLabel(for: child),
                  let attendee = Attendee.parse(accessibilityLabel: label),
                  seen.insert(DirectoryPage.key(attendee)).inserted else { return nil }
            return attendee
        }
    }

    private func liveContainer() throws -> (AXUIElement, [AXUIElement]) {
        guard let window = attendeeWindow() else { throw AXClientError.noWindow }
        let elements = descendants(of: window, maximumDepth: 16)
        guard let target = findScrollableElement(in: elements), !rows(in: target).isEmpty else {
            throw AXClientError.attendeeListNotFound
        }
        return (target, elements)
    }

    private func page() throws -> DirectoryPage {
        let (target, elements) = try liveContainer()
        let actions = actionNames(of: target)
        let up = actions.contains { isScrollUpAction($0, on: target) }
        let down = actions.contains { isScrollDownAction($0, on: target) }
        let hasDirectionalActions = up || down
        let attendees = rows(in: target)
        let total = elements.compactMap { bestLabel(for: $0) }.compactMap { label -> Int? in
            guard label.range(of: #"^\s*[0-9][0-9,]*\s+attendees\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
            return Int(label.filter { $0.isNumber })
        }.first
        record("Snapshot rows=\(attendees.count) total=\(total ?? -1) up=\(up) down=\(down) actions=\(actions)")
        let wholeListVisible = total == attendees.count
        return DirectoryPage(attendees: attendees,
                             canScrollUp: hasDirectionalActions || wholeListVisible ? up : nil,
                             canScrollDown: hasDirectionalActions || wholeListVisible ? down : nil,
                             expectedCount: total)
    }

    private func move(_ direction: ScanDirection) throws {
        let (target, _) = try liveContainer()
        // Use the action actually advertised on the row container. Arbitrary
        // scrollbar fractions can skip dozens of virtualized rows.
        let action = actionNames(of: target).first {
            direction == .up ? isScrollUpAction($0, on: target) : isScrollDownAction($0, on: target)
        }
        guard let action else { throw AXClientError.cannotScroll }
        let result = AXUIElementPerformAction(target, action as CFString)
        record("Move \(direction): action=\(action) result=\(result.rawValue)")
        guard result == .success else { throw AXClientError.cannotScroll }
    }

    private final class LiveDirectorySource: DirectoryScanSource {
        let client: AXClient
        let pauseMilliseconds: UInt32
        init(client: AXClient, pauseMilliseconds: UInt32) {
            self.client = client
            self.pauseMilliseconds = pauseMilliseconds
        }
        func snapshot() throws -> DirectoryPage {
            for _ in 0..<8 {
                do { return try client.page() }
                catch { try waitForAnimation() }
            }
            return try client.page()
        }
        func move(_ direction: ScanDirection) throws { try client.move(direction) }
        func waitForAnimation() throws {
            try Task.checkCancellation()
            usleep(pauseMilliseconds * 1_000)
            try Task.checkCancellation()
        }
    }

    private func firstWindow() -> AXUIElement? {
        let windows: [AXUIElement]? = attribute(application, kAXWindowsAttribute)
        return windows?.first
    }

    private func attendeeWindow() -> AXUIElement? {
        let focused: AXUIElement? = attribute(application, kAXFocusedWindowAttribute)
        let windows: [AXUIElement] = attribute(application, kAXWindowsAttribute) ?? []
        var candidates: [AXUIElement] = []
        if let focused { candidates.append(focused) }
        candidates.append(contentsOf: windows)

        // Catalyst/iOS apps can report a stale focused window while another
        // scene contains the visible directory. Prefer the scene that actually
        // exposes an attendee row, then fall back to the focused/first window.
        if let matching = candidates.first(where: { window in
            descendants(of: window, maximumDepth: 12).contains { element in
                guard let role: String = attribute(element, kAXRoleAttribute),
                      role.caseInsensitiveCompare(kAXButtonRole as String) == .orderedSame,
                      let label = bestLabel(for: element) else { return false }
                return Attendee.parse(accessibilityLabel: label) != nil
            }
        }) {
            return matching
        }
        return candidates.first ?? firstWindow()
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
        let candidates = elements.map { element in
            let subtree = descendants(of: element, maximumDepth: 16)
            let canScroll = actionNames(of: element).contains {
                isScrollUpAction($0, on: element) || isScrollDownAction($0, on: element)
            }
            return DirectoryContainerCandidate(rowCount: rows(in: subtree).count,
                                               subtreeSize: subtree.count, canScroll: canScroll)
        }
        guard let index = DirectoryContainerCandidate.bestIndex(in: candidates) else { return nil }
        let chosen = candidates[index]
        record("Container rows=\(chosen.rowCount) subtree=\(chosen.subtreeSize) scrollable=\(chosen.canScroll) maxVisible=\(candidates.map(\.rowCount).max() ?? 0)")
        return elements[index]
    }

    private func isScrollDownAction(_ action: String, on element: AXUIElement) -> Bool {
        var description: CFString?
        _ = AXUIElementCopyActionDescription(element, action as CFString, &description)
        let searchable = [action, description as String?].compactMap { $0 }.joined(separator: " ")
        let normalized = searchable.lowercased().replacingOccurrences(of: " ", with: "")
        return normalized.contains("scroll") && normalized.contains("down")
    }

    private func isScrollUpAction(_ action: String, on element: AXUIElement) -> Bool {
        var description: CFString?
        _ = AXUIElementCopyActionDescription(element, action as CFString, &description)
        let searchable = [action, description as String?].compactMap { $0 }.joined(separator: " ")
        let normalized = searchable.lowercased().replacingOccurrences(of: " ", with: "")
        return normalized.contains("scroll") && normalized.contains("up")
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
