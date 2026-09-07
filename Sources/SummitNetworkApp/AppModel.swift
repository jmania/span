import AppKit
import Foundation
#if canImport(SummitCore)
import SummitCore
#endif

@MainActor
final class AppModel: ObservableObject {
    nonisolated static let bundleIdentifier = "com.zuddl.lennyfriendssummit"

    @Published var appInstalled = false
    @Published var appRunning = false
    @Published var accessibilityTrusted = false
    @Published var attendees: [Attendee] = []
    @Published var results: [NetworkResult] = []
    @Published var connections: [Connection]?
    @Published var isExtracting = false
    @Published var isImporting = false
    @Published var extractionCount = 0
    @Published var extractionStage = "Returning to the beginning of the attendee list…"
    private var extractionTask: Task<[Attendee], Error>?
    @Published var recentCollectedAttendees: [Attendee] = []
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var lastClassificationMessage: String?
    @Published var isDemo = false
    private let sessionURL: URL?
    private struct ReviewUndo {
        let id: UUID
        let degree: ConnectionDegree
        let reviewedAt: Date?
    }
    private var reviewUndoStack: [ReviewUndo] = []
    @Published private(set) var focusedReviewID: UUID?

    init(sessionURL: URL? = nil) {
        self.sessionURL = sessionURL
        if let saved = try? SessionStore.load(from: sessionURL) {
            attendees = saved.attendees
            results = saved.results
            connections = saved.connections
        }
        refreshPrerequisites()
    }

    var guestListReady: Bool { appInstalled && appRunning && accessibilityTrusted }
    var hasInputs: Bool { !attendees.isEmpty || connections != nil }

    var firstDegreeCount: Int { results.filter { $0.degree == .first }.count }
    var secondDegreeCount: Int { results.filter { $0.degree == .second }.count }
    var notConnectedCount: Int { results.filter { $0.degree == .notConnected }.count }
    var reviewCount: Int { results.filter { $0.degree == .review || $0.degree == .skip }.count }
    var firstDegreeResults: [NetworkResult] { results.filter { $0.degree == .first } }
    func results(for category: ConnectionDegree) -> [NetworkResult] {
        switch category {
        case .review: return results.filter { $0.degree == .review || $0.degree == .skip }
        default: return results.filter { $0.degree == category }
        }
    }

    func result(for attendee: Attendee) -> NetworkResult? {
        results.first { $0.attendee.id == attendee.id }
    }

    func classify(attendee: Attendee, as degree: ConnectionDegree) {
        if let index = results.firstIndex(where: { $0.attendee.id == attendee.id }) {
            reviewUndoStack.append(ReviewUndo(id: results[index].id, degree: results[index].degree, reviewedAt: results[index].reviewedAt))
            results[index].degree = degree
            results[index].reviewedAt = Date()
        } else {
            results.append(NetworkResult(attendee: attendee, degree: degree, confidence: nil, linkedInURL: "", matchedConnection: "", matchReason: "manually classified", reviewedAt: Date()))
        }
        let message = "Marked \(attendee.name) as \(degree.label)."
        lastClassificationMessage = message
        try? saveSession()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.lastClassificationMessage == message { self.lastClassificationMessage = nil }
        }
    }
    var currentReview: NetworkResult? {
        if let focusedReviewID,
           let focused = results.first(where: { $0.id == focusedReviewID }),
           focused.degree == .review || focused.degree == .skip {
            return focused
        }
        return results.first { $0.degree == .review } ?? results.first { $0.degree == .skip }
    }

    func refreshPrerequisites() {
        appInstalled = AXClient.isAppInstalled(bundleIdentifier: Self.bundleIdentifier)
        appRunning = AXClient.isAppRunning(bundleIdentifier: Self.bundleIdentifier)
        accessibilityTrusted = AXClient.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        _ = AXClient.isAccessibilityTrusted(prompt: true)
        refreshPrerequisites()
        if !accessibilityTrusted { openAccessibilitySettings() }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealCurrentApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openEventApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            errorMessage = "Lenny & Friends is not installed on this Mac."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            Task { @MainActor in
                if let error { self.errorMessage = error.localizedDescription }
                self.refreshPrerequisites()
            }
        }
    }

    func extractAttendees() {
        guard !isExtracting && !isImporting else { return }
        refreshPrerequisites()
        guard accessibilityTrusted else {
            errorMessage = "Allow Accessibility access first, then click Check again."
            return
        }
        guard appRunning else {
            errorMessage = "Open Lenny & Friends and navigate to Attendees → All attendees first."
            return
        }

        isExtracting = true
        extractionCount = 0
        recentCollectedAttendees = []
        extractionStage = "Returning to the beginning of the attendee list…"
        statusMessage = "Reading the attendee directory…"
        let model = self
        Task {
            do {
                let task = Task.detached(priority: .userInitiated) {
                    let client = try AXClient(bundleIdentifier: Self.bundleIdentifier)
                    return try client.extractAttendees(maximum: 5_000, pauseMilliseconds: 450, recentAttendees: { attendees in
                        Task { @MainActor in
                            guard model.isExtracting else { return }
                            model.recentCollectedAttendees = attendees
                        }
                    }, stage: { stage in
                        Task { @MainActor in
                            guard model.isExtracting else { return }
                            model.extractionStage = stage
                        }
                    }, diagnosticsURL: SessionStore.diagnosticsURL) { count in
                        Task { @MainActor in
                            guard model.isExtracting else { return }
                            model.extractionCount = count
                        }
                    }
                }
                extractionTask = task
                let extracted = try await task.value
                extractionTask = nil
                try acceptCollectedAttendees(extracted)
                isExtracting = false
            } catch is CancellationError {
                extractionTask = nil
                isExtracting = false
                statusMessage = "Collection stopped. Your saved inputs are unchanged."
            } catch {
                extractionTask = nil
                isExtracting = false
                statusMessage = "Collection needs attention."
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancelExtraction() {
        extractionTask?.cancel()
    }

    @discardableResult
    func importConnections(from url: URL) -> Task<Void, Never>? {
        guard !isImporting else { return nil }
        isImporting = true
        statusMessage = "Reading your LinkedIn archive…"
        return Task {
            defer { isImporting = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ConnectionsFile.read(from: url)
                }.value
                let imported = try ConnectionsCSV.decode(data)
                guard !imported.isEmpty else { throw ConnectionsFileError.emptyConnections }
                connections = imported
                matchIfReady()
                statusMessage = attendees.isEmpty
                    ? "\(imported.count) LinkedIn connections ready. Collect attendees next."
                    : "Found \(firstDegreeCount) first-degree connections."
                try saveSession()
            } catch {
                statusMessage = "Archive needs attention."
                errorMessage = error.localizedDescription
            }
        }
    }

    func acceptCollectedAttendees(_ collected: [Attendee]) throws {
        guard !collected.isEmpty else { throw AXClientError.noAttendees }
        attendees = collected.map { attendee in
            if let saved = attendees.first(where: { $0.sourceLabel == attendee.sourceLabel }) {
                return Attendee(id: saved.id, name: attendee.name, details: attendee.details, sourceLabel: attendee.sourceLabel)
            }
            return attendee
        }
        matchIfReady()
        statusMessage = connections == nil
            ? "Collected \(collected.count) attendees. Add your LinkedIn archive when ready."
            : "Collected \(collected.count) attendees; \(firstDegreeCount) first-degree connections."
        try saveSession()
    }

    private func matchIfReady() {
        guard !attendees.isEmpty, let connections else { return }
        let previous = results
        results = NetworkMatcher.match(attendees: attendees, connections: connections).results.map { match in
            // Re-importing an archive must not discard the user's manual review work.
            previous.first { $0.attendee.sourceLabel == match.attendee.sourceLabel && $0.reviewedAt != nil } ?? match
        }
    }

    func classifyCurrent(as degree: ConnectionDegree) {
        guard let current = currentReview,
              let index = results.firstIndex(where: { $0.id == current.id }) else { return }
        reviewUndoStack.append(ReviewUndo(id: current.id, degree: results[index].degree, reviewedAt: results[index].reviewedAt))
        results[index].degree = degree
        results[index].reviewedAt = Date()
        let message = "Marked \(current.attendee.name) as \(degree.label)."
        lastClassificationMessage = message
        try? saveSession()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.lastClassificationMessage == message { self.lastClassificationMessage = nil }
        }
    }

    func focusReview(_ id: UUID) {
        guard let result = results.first(where: { $0.id == id }), result.degree == .review || result.degree == .skip else { return }
        focusedReviewID = id
    }

    var canUndoReview: Bool { !reviewUndoStack.isEmpty }

    func undoLastClassification() {
        guard let undo = reviewUndoStack.popLast(),
              let index = results.firstIndex(where: { $0.id == undo.id }) else { return }
        results[index].degree = undo.degree
        results[index].reviewedAt = undo.reviewedAt
        focusedReviewID = undo.id
        lastClassificationMessage = "Back to \(results[index].attendee.name)."
        try? saveSession()
    }

    func copyCurrentSearch() {
        guard let current = currentReview else { return }
        let query = [current.attendee.name, current.attendee.details].filter { !$0.isEmpty }.joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(query, forType: .string)
        statusMessage = "Search text copied."
    }

    func openLinkedIn() {
        if let url = URL(string: "https://www.linkedin.com/") { NSWorkspace.shared.open(url) }
    }

    func linkedInSearchURL(for attendee: Attendee) -> URL? {
        var components = URLComponents(string: "https://www.linkedin.com/search/results/people/")
        let query = [attendee.name, attendee.details].filter { !$0.isEmpty }.joined(separator: " ")
        components?.queryItems = [
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "utm_source", value: "span")
        ]
        return components?.url
    }

    func openLinkedInSearch(for attendee: Attendee) {
        guard let url = linkedInSearchURL(for: attendee) else { return }
        let escapedURL = url.absoluteString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let browserURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        let browserID = browserURL.flatMap { Bundle(url: $0)?.bundleIdentifier }

        if browserID == "com.apple.Safari" {
            let source = """
            tell application "Safari"
                if (count of windows) = 0 then make new document
                set targetWindow to front window
                set targetTab to missing value
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t contains "utm_source=span") then
                            set targetWindow to w
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is not missing value then exit repeat
                end repeat
                if targetTab is missing value then set targetTab to make new tab at end of tabs of targetWindow
                set index of targetWindow to 1
                set current tab of targetWindow to targetTab
                set URL of targetTab to "\(escapedURL)"
                activate
            end tell
            """
            if runBrowserScript(source) { return }
        } else if browserID == "com.google.Chrome" {
            let source = """
            tell application "Google Chrome"
                if (count of windows) = 0 then make new window
                set targetWindow to front window
                set targetTab to missing value
                repeat with w in windows
                    repeat with t in tabs of w
                        if (URL of t contains "utm_source=span") then
                            set targetWindow to w
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is not missing value then exit repeat
                end repeat
                if targetTab is missing value then set targetTab to make new tab at end of tabs of targetWindow
                set index of targetWindow to 1
                set active tab index of targetWindow to (index of targetTab)
                set URL of targetTab to "\(escapedURL)"
                activate
            end tell
            """
            if runBrowserScript(source) { return }
        }

        // Other browsers, or browsers without Automation permission, use the
        // system's normal URL-opening behavior as a safe fallback.
        NSWorkspace.shared.open(url)
    }

    private func runBrowserScript(_ source: String) -> Bool {
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    func exportResults() {
        guard !results.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export network results"
        panel.nameFieldStringValue = "summit-network-results.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ResultsCSV.encode(results).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Results exported to \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startOver() {
        guard !isExtracting && !isImporting else { return }
        attendees = []
        results = []
        connections = nil
        reviewUndoStack = []
        focusedReviewID = nil
        lastClassificationMessage = nil
        extractionCount = 0
        recentCollectedAttendees = []
        statusMessage = ""
        if isDemo {
            isDemo = false
            return
        }
        try? SessionStore.clear(at: sessionURL)
    }

    func loadDemo() {
        guard !isExtracting && !isImporting else { return }
        isDemo = true
        let people = [
            Attendee(name: "Maya Chen", details: "Product lead at Example Corp", sourceLabel: "Maya Chen, Product lead at Example Corp"),
            Attendee(name: "Jordan Patel", details: "Founder at Northstar", sourceLabel: "Jordan Patel, Founder at Northstar"),
            Attendee(name: "Alex Rivera", details: "Design director", sourceLabel: "Alex Rivera, Design director"),
            Attendee(name: "Sam Williams", details: "Acme Labs", sourceLabel: "Sam Williams, Acme Labs"),
        ]
        attendees = people
        results = [
            NetworkResult(attendee: people[0], degree: .first, confidence: 1, linkedInURL: "", matchedConnection: people[0].name, matchReason: "exact name"),
            NetworkResult(attendee: people[1], degree: .second, confidence: nil, linkedInURL: "", matchedConnection: "", matchReason: "manually reviewed", reviewedAt: Date()),
            NetworkResult(attendee: people[2], degree: .review, confidence: nil, linkedInURL: "", matchedConnection: "", matchReason: "no first-degree name match"),
            NetworkResult(attendee: people[3], degree: .notConnected, confidence: nil, linkedInURL: "", matchedConnection: "", matchReason: "manually reviewed", reviewedAt: Date()),
        ]
        reviewUndoStack = []
        focusedReviewID = nil
        lastClassificationMessage = nil
        statusMessage = "Showing sample data."
    }

    private func saveSession() throws {
        guard !isDemo else { return }
        try SessionStore.save(SavedSession(attendees: attendees, results: results, connections: connections), to: sessionURL)
    }
}
