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
        let result: NetworkResult
    }
    private var reviewUndoStack: [ReviewUndo] = []
    @Published private(set) var inputRevision = 0
    @Published private(set) var focusedReviewID: UUID?

    init(sessionURL: URL? = nil) {
        self.sessionURL = sessionURL
        if let saved = try? SessionStore.load(from: sessionURL) {
            if saved.results.contains(where: { $0.candidates == nil }) {
                do { try SessionStore.backupBeforeListMigration(at: sessionURL) }
                catch { errorMessage = "Could not back up your previous session: \(error.localizedDescription)" }
            }
            attendees = saved.attendees
            results = saved.results
            connections = saved.connections
        }
        // Recompute legacy automatic matches; preserve deliberate human decisions.
        if !attendees.isEmpty {
            matchIfReady()
            if errorMessage == nil { try? saveSession() }
        }
        refreshPrerequisites()
    }

    var guestListReady: Bool { appInstalled && appRunning && accessibilityTrusted }
    var hasInputs: Bool { !attendees.isEmpty || connections != nil }

    var firstDegreeCount: Int { results.filter { $0.isConfirmed }.count }
    var possibleCount: Int { results.filter { $0.hasSuggestion }.count }
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
        guard let index = results.firstIndex(where: { $0.attendee.id == attendee.id }) else { return }
        reviewUndoStack.append(ReviewUndo(result: results[index]))
        results[index].degree = degree
        results[index].reviewedAt = Date()
        // A manual status without a chosen candidate must not inherit a guessed URL.
        results[index].linkedInURL = ""
        results[index].matchedConnection = ""
        results[index].confirmedCandidateID = nil
        finishDecision("Updated \(attendee.name).")
    }

    func decide(attendee: Attendee, candidate: MatchCandidate, samePerson: Bool) {
        guard let index = results.firstIndex(where: { $0.attendee.id == attendee.id }) else { return }
        reviewUndoStack.append(ReviewUndo(result: results[index]))
        if samePerson {
            results[index].degree = .first
            results[index].reviewedAt = Date()
            results[index].confirmedCandidateID = candidate.id
            results[index].linkedInURL = linkedInProfileURL(candidate.connection.url)?.absoluteString ?? ""
            results[index].matchedConnection = candidate.connection.name
            results[index].rejectedCandidateIDs?.removeAll { $0 == candidate.id }
        } else {
            var rejected = Set(results[index].rejectedCandidateIDs ?? [])
            rejected.insert(candidate.id)
            results[index].rejectedCandidateIDs = rejected.sorted()
            if results[index].confirmedCandidateID == candidate.id {
                results[index].degree = .review
                results[index].reviewedAt = nil
                results[index].confirmedCandidateID = nil
                results[index].linkedInURL = ""
                results[index].matchedConnection = ""
            }
        }
        finishDecision(samePerson ? "Confirmed \(attendee.name)." : "Different person. Attendee kept in your list.")
    }

    func restoreSuggestions(for attendee: Attendee) {
        guard let index = results.firstIndex(where: { $0.attendee.id == attendee.id }) else { return }
        reviewUndoStack.append(ReviewUndo(result: results[index]))
        results[index].rejectedCandidateIDs = []
        finishDecision("Suggestions restored.")
    }

    private func finishDecision(_ message: String) {
        lastClassificationMessage = message
        do { try saveSession() } catch { errorMessage = "Could not save this decision: \(error.localizedDescription)" }
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
                    : "\(possibleCount) attendees have possible LinkedIn connections. Confirm identities in your list."
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
                var retained = Attendee(id: saved.id, name: attendee.name, details: attendee.details, sourceLabel: attendee.sourceLabel)
                retained.profileEvidence = attendee.profileEvidence ?? saved.profileEvidence
                return retained
            }
            return attendee
        }
        matchIfReady()
        statusMessage = connections == nil
            ? "Collected \(collected.count) attendees. Add your LinkedIn archive when ready."
            : "Collected \(collected.count) attendees; \(possibleCount) have possible connections."
        try saveSession()
    }

    private func matchIfReady() {
        guard !attendees.isEmpty else { return }
        let previous = results
        results = NetworkMatcher.match(attendees: attendees, connections: connections ?? []).results.map { match in
            guard let saved = previous.first(where: { $0.attendee.sourceLabel == match.attendee.sourceLabel }) else { return match }
            var merged = NetworkResult(id: saved.id, attendee: match.attendee,
                degree: saved.reviewedAt != nil ? saved.degree : .review, confidence: nil,
                linkedInURL: saved.isConfirmed && saved.confirmedCandidateID != nil ? saved.linkedInURL : "",
                matchedConnection: saved.isConfirmed ? saved.matchedConnection : "",
                matchReason: match.matchReason, reviewedAt: saved.reviewedAt)
            merged.candidates = match.candidates
            merged.rejectedCandidateIDs = saved.rejectedCandidateIDs
            merged.confirmedCandidateID = saved.confirmedCandidateID
            return merged
        }
        reviewUndoStack = []
        inputRevision += 1
    }

    func classifyCurrent(as degree: ConnectionDegree) {
        guard let current = currentReview else { return }
        classify(attendee: current.attendee, as: degree)
    }

    func focusReview(_ id: UUID) {
        guard let result = results.first(where: { $0.id == id }), result.degree == .review || result.degree == .skip else { return }
        focusedReviewID = id
    }

    var canUndoReview: Bool { !reviewUndoStack.isEmpty }

    func canUndoReview(for attendee: Attendee) -> Bool {
        reviewUndoStack.last?.result.attendee.id == attendee.id
    }

    func undoLastClassification() {
        guard let undo = reviewUndoStack.popLast(),
              let index = results.firstIndex(where: { $0.id == undo.result.id }) else { return }
        results[index] = undo.result
        focusedReviewID = undo.result.id
        finishDecision("Undid the last change.")
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
        panel.title = "Export attendee list"
        panel.nameFieldStringValue = "span-attendee-list.csv"
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
        connections = [
            Connection(name: "Maya Chen", company: "Example Corp", position: "Product lead", url: "https://www.linkedin.com/in/span-fictional-maya", email: ""),
            Connection(name: "Jordan Patel", company: "Other Example", position: "Founder", url: "", email: "")
        ]
        results = NetworkMatcher.match(attendees: people, connections: connections ?? []).results
        inputRevision += 1
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
