import Foundation

@MainActor
func checkIdentitySuggestions() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("span-identity-tests-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let people = [
        Attendee(name: "Kyle Miller", details: "Example Labs", sourceLabel: "Kyle Miller, Example Labs"),
        Attendee(name: "Kyle Miller", details: "Unrelated Org", sourceLabel: "Kyle Miller, Unrelated Org"),
        Attendee(name: "Maya Chen", details: "New Employer", sourceLabel: "Maya Chen, New Employer"),
        Attendee(name: "Alex Rivera", details: "Design", sourceLabel: "Alex Rivera, Design")
    ]
    let contacts = [
        Connection(name: "Kyle Miller", company: "Example Labs", position: "Product manager", url: "https://www.linkedin.com/in/example-kyle", email: ""),
        Connection(name: "Kyle Miller", company: "Other Co", position: "Designer", url: "https://www.linkedin.com/in/other-kyle", email: ""),
        Connection(name: "Maya Chen", company: "Old Employer", position: "Product", url: "https://www.linkedin.com/in/example-maya", email: "")
    ]
    let url = folder.appendingPathComponent("session.json")
    let model = AppModel(sessionURL: url)
    model.connections = contacts
    try model.acceptCollectedAttendees(people)
    precondition(model.firstDegreeCount == 0 && model.possibleCount == 3)
    let kyle = model.results[0]
    precondition(kyle.candidates?.count == 2)
    precondition(kyle.candidates?.first?.connection.company == "Example Labs")
    precondition(kyle.candidates?.first?.otherAttendeeCount == 1)
    precondition(kyle.linkedInURL.isEmpty && kyle.confidence == nil)
    let candidate = kyle.candidates![0]
    let list = SummitListPresentation(attendees: people, results: model.results, connectionCount: contacts.count)
    precondition(list.suggested.count == 3 && list.others.map(\.name) == ["Alex Rivera"])
    precondition(list.summary.contains("4 Summit attendees with 3 connections"))
    precondition(list.summary.contains("3 attendees with possible matches"))
    precondition(list.filtered(list.suggested, query: "  MAYA  ").map(\.name) == ["Maya Chen"])
    precondition(list.filtered(list.others, query: "Design").count == 1)
    precondition(list.filtered(list.suggested, query: "no such attendee").isEmpty)
    let noArchive = SummitListPresentation(attendees: people, results: [], connectionCount: nil)
    precondition(noArchive.suggested.isEmpty && noArchive.others.count == 4 && !noArchive.hasArchive)
    precondition(!noArchive.summary.contains("compared"))
    let zeroMatches = SummitListPresentation(attendees: people, results: [], connectionCount: 0)
    precondition(zeroMatches.hasArchive && zeroMatches.summary.contains("0 attendees with possible matches"))
    model.decide(attendee: people[0], candidate: candidate, samePerson: false)
    precondition(model.canUndoReview(for: people[0]) && !model.canUndoReview(for: people[1]))
    let afterDismissal = SummitListPresentation(attendees: people, results: model.results, connectionCount: contacts.count)
    precondition(afterDismissal.suggested.map(\.id) == list.suggested.map(\.id))
    precondition(afterDismissal.summary == list.summary, "Review decisions must not shift the comparison summary")
    precondition(model.results[0].activeCandidates.count == 1 && model.results[0].degree == .review)
    precondition(model.attendees.count == 4)
    model.undoLastClassification()
    precondition(model.results[0].activeCandidates.count == 2)
    model.decide(attendee: people[0], candidate: candidate, samePerson: false)
    let other = model.results[0].activeCandidates[0]
    model.decide(attendee: people[0], candidate: other, samePerson: true)
    precondition(model.firstDegreeCount == 1 && model.results[0].linkedInURL.contains("other-kyle"))
    let afterConfirmation = SummitListPresentation(attendees: people, results: model.results, connectionCount: contacts.count)
    precondition(afterConfirmation.suggested.map(\.id) == list.suggested.map(\.id))
    model.undoLastClassification()
    precondition(model.firstDegreeCount == 0 && model.results[0].linkedInURL.isEmpty)
    model.decide(attendee: people[0], candidate: other, samePerson: true)
    let reimport = folder.appendingPathComponent("Connections.csv")
    let csvRows = [["Name", "Company", "Position", "URL"]] + contacts.map { [$0.name, $0.company, $0.position, $0.url] }
    try Data(CSV.encode(rows: csvRows).utf8).write(to: reimport)
    await model.importConnections(from: reimport)?.value
    precondition(model.results[0].isConfirmed && model.results[0].rejectedCandidateIDs == [candidate.id])
    try model.acceptCollectedAttendees(people.map { Attendee(name: $0.name, details: $0.details, sourceLabel: $0.sourceLabel) })
    precondition(model.results[0].isConfirmed && model.results[0].rejectedCandidateIDs == [candidate.id])
    let restarted = AppModel(sessionURL: url)
    precondition(restarted.results[0].isConfirmed && restarted.results[0].rejectedCandidateIDs == [candidate.id])
    restarted.restoreSuggestions(for: restarted.attendees[0])
    precondition(restarted.results[0].rejectedCandidateIDs?.isEmpty == true)
    restarted.undoLastClassification()
    precondition(restarted.results[0].rejectedCandidateIDs == [candidate.id])
    precondition(linkedInProfileURL("https://www.linkedin.com/in/example/?trk=x")?.absoluteString == "https://www.linkedin.com/in/example")
    precondition(linkedInProfileURL("https://linkedin.com.evil.test/in/example") == nil)
    precondition(linkedInProfileURL("javascript:alert(1)") == nil)
    let legacyURL = folder.appendingPathComponent("legacy.json")
    let oldResults = people.enumerated().map { index, person in
        NetworkResult(attendee: person, degree: .first, confidence: 0.97,
                      linkedInURL: "https://www.linkedin.com/in/old-guessed-profile", matchedConnection: person.name,
                      matchReason: "exact name", reviewedAt: index == 1 ? Date() : nil)
    }
    try SessionStore.save(SavedSession(attendees: people, results: oldResults), to: legacyURL)
    let migrated = AppModel(sessionURL: legacyURL)
    precondition(FileManager.default.fileExists(atPath: legacyURL.appendingPathExtension("pre-list-first-backup").path))
    precondition(migrated.firstDegreeCount == 1 && migrated.results[1].isConfirmed)
    precondition(migrated.results.allSatisfy { $0.linkedInURL.isEmpty })
    let encoded = ResultsCSV.encode(restarted.results)
    precondition(encoded.contains("possible_profile_urls") && !encoded.contains("confidence"))
    let changedJob = Connection(name: candidate.connection.name, company: "New Job", position: "New Title", url: candidate.connection.url + "/?trk=changed", email: "")
    precondition(changedJob.identityKey == candidate.id)
    let duplicate = NetworkMatcher.match(attendees: [people[0]], connections: [candidate.connection, candidate.connection])
    precondition(duplicate.results[0].candidates?.count == 1)
    let generic = Connection(name: "Kyle Miller", company: "Product Manager", position: "Founder", url: "", email: "")
    precondition(NetworkMatcher.match(attendees: [people[0]], connections: [generic]).results[0].candidates?.first?.rank == 1)
    let fuzzy = Attendee(name: "Kylie Miller", details: "", sourceLabel: "Kylie Miller")
    precondition(NetworkMatcher.match(attendees: [fuzzy], connections: contacts).firstDegreeCount == 0)
    let variants = ["Alexandria Montgomery", "Alexandra Montgomery", "Alexandria Montgomeri", "Alexander Montgomery", "Alexandria Montgomer", "Alxandria Montgomri", "Kyle Miller", "Kylie Miller", "José García", "Jose Garcia", "Jo Smith", "Jon Smith"]
    func reference(_ left: String, _ right: String) -> Double {
        let a = Array(normalizedName(left)), b = Array(normalizedName(right))
        var previous = Array(0...b.count)
        for (i, letter) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, other) in b.enumerated() {
                row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (letter == other ? 0 : 1))
            }
            previous = row
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
    for left in variants {
        for right in variants {
            let person = Attendee(name: left, details: "", sourceLabel: left)
            let contact = Connection(name: right, company: "", position: "", url: "", email: "")
            let suggested = NetworkMatcher.match(attendees: [person], connections: [contact]).results[0].hasSuggestion
            precondition(suggested == (reference(left, right) >= 0.88), "Bounded matcher must agree with full edit distance")
        }
    }
    print("PASS: identity ambiguity, pair decisions, row-scoped undo, stable list sections, search, archive-free/zero-match states, migration, persistence, URL safety, ranking, and honest exports")
}
