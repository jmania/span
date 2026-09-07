import Foundation

/// A snapshot of list membership, deliberately independent of review decisions.
/// Build again only when inputs change or the list is reopened. Search filters
/// this snapshot, so confirming/dismissing a pairing never moves an attendee.
public struct SummitListPresentation {
    public let suggested: [Attendee]
    public let others: [Attendee]
    public let summary: String
    public let hasArchive: Bool

    public init(attendees: [Attendee], results: [NetworkResult], connectionCount: Int?) {
        let lookup = Dictionary(results.map { ($0.attendee.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = attendees.sorted {
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if $0.details != $1.details { return $0.details < $1.details }
            return $0.id.uuidString < $1.id.uuidString
        }
        // Retain original evidence, including dismissed/confirmed suggestions.
        // A dismissed suggestion is not evidence that someone isn't connected.
        func hasEvidence(_ attendee: Attendee) -> Bool {
            guard let result = lookup[attendee.id] else { return false }
            return !(result.candidates ?? []).isEmpty || result.isConfirmed
        }
        suggested = sorted.filter(hasEvidence)
        others = sorted.filter { !hasEvidence($0) }
        hasArchive = connectionCount != nil
        let count = attendees.filter { !(lookup[$0.id]?.candidates ?? []).isEmpty }.count
        if let connectionCount {
            summary = "We compared \(attendees.count.formatted()) Summit attendees with \(connectionCount.formatted()) connections in your LinkedIn export and found \(count.formatted()) attendee\(count == 1 ? "" : "s") with possible matches."
        } else {
            summary = "\(attendees.count.formatted()) Summit attendees, ready to explore. Add your LinkedIn export to find people you may know."
        }
    }

    public func filtered(_ attendees: [Attendee], query: String) -> [Attendee] {
        let query = normalizedName(query)
        return attendees.filter { query.isEmpty || normalizedName($0.name + " " + $0.details).contains(query) }
    }
}
