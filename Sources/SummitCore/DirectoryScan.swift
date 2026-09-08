import Foundation

// iOS-on-Mac can advertise page scrolling on individual attendee wrappers as
// well as their enclosing list. The first scrollable element is not necessarily
// the directory. Prefer the most complete viewport, then its narrowest owner.
struct DirectoryContainerCandidate {
    let rowCount: Int
    let subtreeSize: Int
    let canScroll: Bool

    static func bestIndex(in candidates: [Self]) -> Int? {
        let populated = candidates.indices.filter { candidates[$0].rowCount > 0 }
        let scrollable = populated.filter { candidates[$0].canScroll }
        return (scrollable.isEmpty ? populated : scrollable).max { left, right in
            let lhs = candidates[left], rhs = candidates[right]
            if lhs.rowCount != rhs.rowCount { return lhs.rowCount < rhs.rowCount }
            return lhs.subtreeSize > rhs.subtreeSize
        }
    }
}

// The traversal is independent of Accessibility so delayed animations, stale
// views, rejected actions, and false success can be tested deterministically.
enum ScanDirection { case up, down }

struct DirectoryPage {
    let attendees: [Attendee]
    let canScrollUp: Bool?
    let canScrollDown: Bool?
    let expectedCount: Int?

    var signature: [String] { attendees.map(Self.key) }
    static func key(_ attendee: Attendee) -> String {
        [attendee.name, attendee.details].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }.joined(separator: "\u{001F}")
    }
}

protocol DirectoryScanSource: AnyObject {
    func snapshot() throws -> DirectoryPage
    func move(_ direction: ScanDirection) throws
    func waitForAnimation() throws
}

enum DirectoryScanError: LocalizedError {
    case stalledAtStart
    case stalledDuringCollection(Int)
    case incomplete(found: Int, expected: Int)
    case limit

    var errorDescription: String? {
        switch self {
        case .stalledAtStart:
            return "Span couldn’t verify the beginning of the attendee list. Collection was stopped; your saved data has not been replaced."
        case .stalledDuringCollection(let count):
            return "The attendee list stopped moving after \(count) people. Span has not treated this as a complete guest list or replaced your saved data."
        case .incomplete(let found, let expected):
            return "Span read \(found) attendees, but the event app lists \(expected). The scan is incomplete; your saved data has not been replaced."
        case .limit:
            return "The scan reached its safety limit before completion. Your saved data has not been replaced."
        }
    }
}

enum DirectoryScan {
    static func run(
        source: DirectoryScanSource, maximum: Int,
        stage: (String) -> Void,
        progress: ([Attendee]) -> Void
    ) throws -> [Attendee] {
        var page = try source.snapshot()
        var expected = page.expectedCount
        var steps = 0
        stage("Returning to the beginning of the attendee list…")

        // No attendees are published until the top boundary is observed twice.
        while true {
            try Task.checkCancellation()
            if page.canScrollUp == false && page.canScrollDown != nil {
                try source.waitForAnimation()
                let confirmation = try source.snapshot()
                if confirmation.canScrollUp == false && confirmation.signature == page.signature {
                    page = confirmation
                    break
                }
                page = confirmation
                continue
            }
            guard steps < 5_000 else { throw DirectoryScanError.limit }
            do {
                page = try advance(source: source, from: page, direction: .up, count: 0)
            } catch DirectoryScanError.stalledAtStart {
                // The event app keeps Scroll Up at the top for pull-to-refresh.
                // Prove that scrolling still works by moving down and back up.
                // Only an unchanged additional upward attempt is a boundary;
                // a broken scroller cannot pass the round trip.
                guard page.canScrollDown == true else { throw DirectoryScanError.stalledAtStart }
                stage("Checking the beginning of the list…")
                let lower = try advance(source: source, from: page, direction: .down, count: 0)
                let restored = try advance(source: source, from: lower, direction: .up, count: 0)
                guard restored.signature == page.signature else {
                    page = restored
                    continue
                }
                do {
                    page = try advance(source: source, from: restored, direction: .up, count: 0)
                    continue
                } catch DirectoryScanError.stalledAtStart {
                    page = restored
                    break
                }
            }
            steps += 1
            stage("Returning to the beginning… \(steps) pages moved")
        }

        stage("Collecting attendees from the beginning…")
        var collected: [Attendee] = []
        var seen = Set<String>()
        steps = 0
        while true {
            try Task.checkCancellation()
            expected = page.expectedCount ?? expected
            for attendee in page.attendees where seen.insert(DirectoryPage.key(attendee)).inserted {
                collected.append(attendee)
            }
            progress(collected)

            if page.canScrollDown == false && page.canScrollUp != nil {
                try source.waitForAnimation()
                let confirmation = try source.snapshot()
                if confirmation.canScrollDown == false && confirmation.signature == page.signature {
                    // Only a shortfall means rows were missed. Reading more
                    // than the advertised total happens when the event app's
                    // header count is stale or a card's details change
                    // between snapshots; that list is still complete enough
                    // to keep and match against the LinkedIn export.
                    if let expected, collected.count < expected {
                        throw DirectoryScanError.incomplete(found: collected.count, expected: expected)
                    }
                    return collected
                }
                page = confirmation
                continue
            }
            guard collected.count < maximum, steps < 5_000 else { throw DirectoryScanError.limit }
            page = try advance(source: source, from: page, direction: .down, count: collected.count)
            steps += 1
        }
    }

    private static func advance(source: DirectoryScanSource, from old: DirectoryPage,
                                direction: ScanDirection, count: Int) throws -> DirectoryPage {
        // A successful AX return code is only an acknowledgement. Wait for a
        // changed viewport, then a second identical snapshot after animation.
        // Retry once, bounded, including when the action itself is rejected.
        for _ in 0..<2 {
            try Task.checkCancellation()
            do { try source.move(direction) }
            catch is CancellationError { throw CancellationError() }
            catch { /* Re-read the live page and retry after it settles. */ }
            var candidate: DirectoryPage?
            for _ in 0..<8 {
                try source.waitForAnimation()
                let page = try source.snapshot()
                if !page.attendees.isEmpty && page.signature != old.signature {
                    if candidate?.signature == page.signature { return page }
                    candidate = page
                } else {
                    candidate = nil
                }
            }
        }
        if direction == .up { throw DirectoryScanError.stalledAtStart }
        throw DirectoryScanError.stalledDuringCollection(count)
    }
}
