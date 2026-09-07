import Foundation

// A virtualized directory whose animations take three observations to settle.
// Moving again before it settles discards the previous pending movement, just
// as rapid reset actions can be coalesced by a real UI.
private final class DelayedDirectory: DirectoryScanSource {
    let people = (0..<1352).map { Attendee(name: "Person \($0)", details: "", sourceLabel: "Person \($0)") }
    var offset: Int
    var pending: Int?
    var ticks = 0
    var moves = 0
    var stall = false
    var failFirst = false
    var expected = 1352
    var cancel = false
    var pullToRefresh = false
    init(offset: Int) { self.offset = offset }
    func snapshot() throws -> DirectoryPage {
        DirectoryPage(attendees: Array(people[offset..<min(offset + 6, people.count)]),
                      canScrollUp: offset > 0 || pullToRefresh, canScrollDown: offset < people.count - 6,
                      expectedCount: expected)
    }
    func move(_ direction: ScanDirection) throws {
        moves += 1
        if failFirst { failFirst = false; throw AXClientError.cannotScroll }
        guard !stall else { return } // AX reports success without movement.
        pending = direction == .up ? max(0, offset - 5) : min(people.count - 6, offset + 5)
        ticks = 0
    }
    func waitForAnimation() throws {
        if cancel { throw CancellationError() }
        ticks += 1
        if ticks >= 3, let pending { offset = pending; self.pending = nil }
    }
}

func checkDirectoryTraversal() throws {
    // Reproduces the native failure: a one-person wrapper advertises scrolling
    // before the actual multi-row directory. Ancestors can advertise it too.
    let containers: [DirectoryContainerCandidate] = [
        .init(rowCount: 1, subtreeSize: 4, canScroll: true),
        .init(rowCount: 6, subtreeSize: 80, canScroll: true),
        .init(rowCount: 6, subtreeSize: 30, canScroll: true),
        .init(rowCount: 1, subtreeSize: 2, canScroll: true)
    ]
    precondition(DirectoryContainerCandidate.bestIndex(in: containers) == 2,
                 "Choose all visible attendees, not the first scrollable single-row wrapper")
    precondition(DirectoryContainerCandidate.bestIndex(in: [.init(rowCount: 0, subtreeSize: 1, canScroll: true)]) == nil)
    precondition(DirectoryContainerCandidate.bestIndex(in: [.init(rowCount: 1, subtreeSize: 2, canScroll: false)]) == 0)
    for start in [0, 700, 1346] {
        let source = DelayedDirectory(offset: start)
        var firstPublished: String?
        let result = try DirectoryScan.run(source: source, maximum: 5000, stage: { _ in }) {
            if firstPublished == nil { firstPublished = $0.first?.name }
        }
        precondition(result.count == 1352 && result.first?.name == "Person 0" && result.last?.name == "Person 1351")
        precondition(firstPublished == "Person 0", "Never display names from the starting viewport before reset")
    }
    let stalledReset = DelayedDirectory(offset: 1346)
    stalledReset.stall = true
    var reported = false
    do {
        _ = try DirectoryScan.run(source: stalledReset, maximum: 5000, stage: { _ in }) { _ in reported = true }
        preconditionFailure("False success during reset must not count as reaching the top")
    } catch DirectoryScanError.stalledAtStart { }
    precondition(!reported && stalledReset.moves == 2, "Retries must be bounded")

    let stalledScan = DelayedDirectory(offset: 0)
    stalledScan.stall = true
    do {
        _ = try DirectoryScan.run(source: stalledScan, maximum: 5000, stage: { _ in }, progress: { _ in })
        preconditionFailure("One viewport must not count as a completed directory")
    } catch DirectoryScanError.stalledDuringCollection(let count) { precondition(count == 6) }

    let retry = DelayedDirectory(offset: 0)
    retry.failFirst = true
    let recovered = try DirectoryScan.run(source: retry, maximum: 5000, stage: { _ in }, progress: { _ in })
    precondition(recovered.count == 1352)

    let refresh = DelayedDirectory(offset: 700)
    refresh.pullToRefresh = true
    let afterRefresh = try DirectoryScan.run(source: refresh, maximum: 5000, stage: { _ in }, progress: { _ in })
    precondition(afterRefresh.count == 1352 && afterRefresh.first?.name == "Person 0", "Top with an advertised pull-to-refresh action must pass a bidirectional probe")

    let incomplete = DelayedDirectory(offset: 0)
    incomplete.expected = 1400
    do {
        _ = try DirectoryScan.run(source: incomplete, maximum: 5000, stage: { _ in }, progress: { _ in })
        preconditionFailure("A count mismatch must not be saved as complete")
    } catch DirectoryScanError.incomplete(let found, let expected) { precondition(found == 1352 && expected == 1400) }

    let cancelled = DelayedDirectory(offset: 1346)
    cancelled.cancel = true
    do {
        _ = try DirectoryScan.run(source: cancelled, maximum: 5000, stage: { _ in }, progress: { _ in })
        preconditionFailure("Cancellation must stop reset")
    } catch is CancellationError { }
    print("PASS: 1,352 simulated attendees from top/middle/bottom; delayed animations; false AX success; bounded retries; incomplete-count rejection; cancellation")
}
