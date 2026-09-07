// Runs without SwiftPM so the native workflow can also be checked with Command Line Tools.
import Foundation

@main
struct AppWorkflowChecks {
    @MainActor
    static func main() async throws {
        try checkDirectoryTraversal()
        try await checkIdentitySuggestions()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("span-workflow-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("Connections.csv")
        try Data("First Name,Last Name,Company,Position,URL\nMaya,Chen,Example,Product,https://example.test/maya\n".utf8).write(to: archive)
        let people = [
            Attendee(name: "Maya Chen", details: "Example", sourceLabel: "Maya Chen, Example"),
            Attendee(name: "Alex Rivera", details: "Example", sourceLabel: "Alex Rivera, Example")
        ]

        let firstURL = directory.appendingPathComponent("archive-first.json")
        let first = AppModel(sessionURL: firstURL)
        await first.importConnections(from: archive)?.value
        precondition(first.connections?.count == 1 && first.attendees.isEmpty && first.results.isEmpty)
        let restored = AppModel(sessionURL: firstURL)
        precondition(restored.connections?.count == 1, "Archive-first import must survive restart")
        try restored.acceptCollectedAttendees(people)
        precondition(restored.firstDegreeCount == 0 && restored.results.count == 2)
        let searchURL = restored.linkedInSearchURL(for: people[1])
        precondition(searchURL?.absoluteString.contains("search/results/people") == true)
        precondition(searchURL?.absoluteString.contains("Alex") == true && searchURL?.absoluteString.contains("Rivera") == true)
        precondition(searchURL?.absoluteString.contains("utm_source=span") == true)

        let second = AppModel(sessionURL: directory.appendingPathComponent("attendees-first.json"))
        try second.acceptCollectedAttendees(people)
        precondition(second.connections == nil && second.results.count == 2)
        await second.importConnections(from: archive)?.value
        precondition(second.firstDegreeCount == 0 && second.results.count == 2)
        let reviewID = second.currentReview?.id
        second.classifyCurrent(as: .second)
        precondition(second.canUndoReview && second.currentReview?.id != reviewID)
        second.undoLastClassification()
        precondition(second.currentReview?.id == reviewID && second.currentReview?.degree == .review)
        second.classifyCurrent(as: .second)
        await second.importConnections(from: archive)?.value
        precondition(second.secondDegreeCount == 1, "Re-import must retain manual review")
        try second.acceptCollectedAttendees(people.map {
            Attendee(name: $0.name, details: $0.details, sourceLabel: $0.sourceLabel)
        })
        precondition(second.connections?.count == 1 && second.secondDegreeCount == 1)
        precondition(second.attendees.allSatisfy { second.result(for: $0) != nil }, "Rescanning must keep directory rows linked to their classifications")
        let reviewPerson = Attendee(name: "Taylor Morgan", details: "Example", sourceLabel: "Taylor Morgan, Example")
        let reviewResult = NetworkResult(attendee: reviewPerson, degree: .review, confidence: nil, linkedInURL: "", matchedConnection: "", matchReason: "test")
        second.results.append(reviewResult)
        second.focusReview(reviewResult.id)
        precondition(second.currentReview?.id == reviewResult.id, "Needs-review list must focus the selected person")

        let before = try Data(contentsOf: firstURL)
        do {
            try restored.acceptCollectedAttendees([])
            preconditionFailure("Empty collection must not succeed")
        } catch AXClientError.noAttendees { }
        precondition(restored.attendees.count == 2 && restored.connections?.count == 1)
        let afterEmptyCollection = try Data(contentsOf: firstURL)
        precondition(afterEmptyCollection == before, "Empty collection must not overwrite saved inputs")

        let bad = directory.appendingPathComponent("Invalid.csv")
        try Data("not,a,connections,archive\n".utf8).write(to: bad)
        await restored.importConnections(from: bad)?.value
        precondition(restored.errorMessage != nil && restored.connections?.count == 1 && !restored.isImporting)
        let empty = directory.appendingPathComponent("Empty.csv")
        try Data("First Name,Last Name\n".utf8).write(to: empty)
        await restored.importConnections(from: empty)?.value
        precondition(restored.connections?.count == 1 && !restored.isImporting)

        let overlap = AppModel(sessionURL: directory.appendingPathComponent("overlap.json"))
        let importTask = overlap.importConnections(from: archive)
        precondition(overlap.importConnections(from: archive) == nil, "Reject duplicate import while busy")
        try overlap.acceptCollectedAttendees(people)
        await importTask?.value
        precondition(overlap.firstDegreeCount == 0 && !overlap.isImporting)

        let legacy = try JSONDecoder().decode(SavedSession.self, from: Data("{\"attendees\":[],\"results\":[]}".utf8))
        precondition(legacy.connections == nil, "Existing sessions must decode without connections")
        print("PASS: archive-first restart, attendees-first, overlap, manual review retention, zero-result preservation, invalid/empty archive, duplicate import guard, legacy session migration")
    }
}
