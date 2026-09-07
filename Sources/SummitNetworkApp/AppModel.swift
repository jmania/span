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
    @Published var isExtracting = false
    @Published var isImporting = false
    @Published var extractionCount = 0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var isDemo = false

    init() {
        if let saved = try? SessionStore.load() {
            attendees = saved.attendees
            results = saved.results
        }
        refreshPrerequisites()
    }

    var firstDegreeCount: Int { results.filter { $0.degree == .first }.count }
    var secondDegreeCount: Int { results.filter { $0.degree == .second }.count }
    var notConnectedCount: Int { results.filter { $0.degree == .notConnected }.count }
    var reviewCount: Int { results.filter { $0.degree == .review || $0.degree == .skip }.count }
    var currentReview: NetworkResult? {
        results.first { $0.degree == .review } ?? results.first { $0.degree == .skip }
    }

    func refreshPrerequisites() {
        appInstalled = AXClient.isAppInstalled(bundleIdentifier: Self.bundleIdentifier)
        appRunning = AXClient.isAppRunning(bundleIdentifier: Self.bundleIdentifier)
        accessibilityTrusted = AXClient.isAccessibilityTrusted()
    }

    func requestAccessibility() {
        _ = AXClient.isAccessibilityTrusted(prompt: true)
        refreshPrerequisites()
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
        statusMessage = "Reading the attendee directory…"
        let model = self
        Task {
            do {
                let extracted = try await Task.detached(priority: .userInitiated) {
                    let client = try AXClient(bundleIdentifier: Self.bundleIdentifier)
                    return try client.extractAttendees(maximum: 5_000, pauseMilliseconds: 450) { count in
                        Task { @MainActor in model.extractionCount = count }
                    }
                }.value
                attendees = extracted
                results = []
                isExtracting = false
                statusMessage = "Collected \(extracted.count) attendees."
                try saveSession()
            } catch {
                isExtracting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func importConnections(from url: URL) {
        guard !attendees.isEmpty else { return }
        isImporting = true
        statusMessage = "Reading your LinkedIn archive…"
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ConnectionsFile.read(from: url)
                }.value
                let connections = try ConnectionsCSV.decode(data)
                let summary = NetworkMatcher.match(attendees: attendees, connections: connections)
                results = summary.results
                isImporting = false
                statusMessage = "Found \(summary.firstDegreeCount) first-degree connections."
                try saveSession()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func classifyCurrent(as degree: ConnectionDegree) {
        guard let current = currentReview,
              let index = results.firstIndex(where: { $0.id == current.id }) else { return }
        results[index].degree = degree
        results[index].reviewedAt = Date()
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
        attendees = []
        results = []
        extractionCount = 0
        statusMessage = ""
        if isDemo {
            isDemo = false
            return
        }
        try? SessionStore.clear()
    }

    func loadDemo() {
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
        statusMessage = "Showing sample data."
    }

    private func saveSession() throws {
        guard !isDemo else { return }
        try SessionStore.save(SavedSession(attendees: attendees, results: results))
    }
}
