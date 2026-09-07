import Foundation

public struct Connection: Hashable, Sendable {
    public let name: String
    public let company: String
    public let position: String
    public let url: String
    public let email: String

    public init(name: String, company: String, position: String, url: String, email: String) {
        self.name = name
        self.company = company
        self.position = position
        self.url = url
        self.email = email
    }

    var details: String { [company, position].filter { !$0.isEmpty }.joined(separator: " ") }
}

public enum ConnectionDegree: String, Codable, CaseIterable, Sendable {
    case first = "1st"
    case second = "2nd"
    case notConnected = "not_connected"
    case review
    case skip

    public var label: String {
        switch self {
        case .first: return "First degree"
        case .second: return "Second degree"
        case .notConnected: return "Not connected"
        case .review: return "Needs review"
        case .skip: return "Skipped"
        }
    }
}

public struct NetworkResult: Codable, Identifiable, Sendable {
    public let id: UUID
    public let attendee: Attendee
    public var degree: ConnectionDegree
    public let confidence: Double?
    public let linkedInURL: String
    public let matchedConnection: String
    public let matchReason: String
    public var reviewedAt: Date?

    public init(
        id: UUID = UUID(), attendee: Attendee, degree: ConnectionDegree,
        confidence: Double?, linkedInURL: String, matchedConnection: String,
        matchReason: String, reviewedAt: Date? = nil
    ) {
        self.id = id
        self.attendee = attendee
        self.degree = degree
        self.confidence = confidence
        self.linkedInURL = linkedInURL
        self.matchedConnection = matchedConnection
        self.matchReason = matchReason
        self.reviewedAt = reviewedAt
    }
}

public struct MatchSummary: Sendable {
    public let results: [NetworkResult]
    public var firstDegreeCount: Int { results.filter { $0.degree == .first }.count }
    public var reviewCount: Int { results.filter { $0.degree == .review || $0.degree == .skip }.count }
}

public enum ConnectionsCSV {
    public static func decode(_ data: Data) throws -> [Connection] {
        let rows = try CSV.decode(data)
        guard let headerIndex = rows.firstIndex(where: isConnectionsHeader) else {
            throw CSVError.missingConnectionsHeader
        }
        let header = rows[headerIndex]
        var columns: [String: Int] = [:]
        for (index, value) in header.enumerated() {
            columns[value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = index
        }

        func index(_ names: [String]) -> Int? {
            names.compactMap { columns[$0.lowercased()] }.first
        }
        let full = index(["name", "full name", "full_name"])
        let first = index(["first name", "first_name", "first"])
        let last = index(["last name", "last_name", "last"])
        let company = index(["company", "organization"])
        let position = index(["position", "title", "job title"])
        let url = index(["url", "linkedin url", "profile url"])
        let email = index(["email address", "email"])

        func value(_ row: [String], at index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return rows.dropFirst(headerIndex + 1).compactMap { row in
            let name = full.map { value(row, at: $0) } ??
                [value(row, at: first), value(row, at: last)].filter { !$0.isEmpty }.joined(separator: " ")
            guard !normalizedName(name).isEmpty else { return nil }
            return Connection(
                name: name,
                company: value(row, at: company),
                position: value(row, at: position),
                url: value(row, at: url),
                email: value(row, at: email)
            )
        }
    }

    private static func isConnectionsHeader(_ row: [String]) -> Bool {
        let values = Set(row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return values.contains("name") || (values.contains("first name") && values.contains("last name"))
    }
}

public enum NetworkMatcher {
    public static func match(attendees: [Attendee], connections: [Connection]) -> MatchSummary {
        MatchSummary(results: attendees.map { attendee in
            let outcome = bestMatch(name: attendee.name, details: attendee.details, connections: connections)
            guard let connection = outcome.connection else {
                return NetworkResult(
                    attendee: attendee, degree: .review,
                    confidence: outcome.confidence > 0 ? outcome.confidence : nil,
                    linkedInURL: "", matchedConnection: "", matchReason: outcome.reason
                )
            }
            return NetworkResult(
                attendee: attendee, degree: .first, confidence: outcome.confidence,
                linkedInURL: connection.url, matchedConnection: connection.name,
                matchReason: outcome.reason
            )
        })
    }

    private struct Outcome {
        let connection: Connection?
        let confidence: Double
        let reason: String
    }

    private static func bestMatch(name: String, details: String, connections: [Connection]) -> Outcome {
        let wanted = normalizedName(name)
        let exact = connections.filter { normalizedName($0.name) == wanted }
        if exact.count == 1 {
            let overlap = detailOverlap(details, exact[0].details)
            return Outcome(connection: exact[0], confidence: overlap > 0 ? 1.0 : 0.97, reason: "exact name")
        }
        if exact.count > 1 {
            let ranked = exact.sorted { detailOverlap(details, $0.details) > detailOverlap(details, $1.details) }
            let overlap = detailOverlap(details, ranked[0].details)
            if overlap >= 0.25 {
                return Outcome(connection: ranked[0], confidence: min(1.0, 0.96 + overlap * 0.04), reason: "exact name; details disambiguated")
            }
            return Outcome(connection: nil, confidence: 0, reason: "multiple connections have this name")
        }

        let ranked = connections.compactMap { connection -> (Double, Double, Connection)? in
            let similarity = nameSimilarity(wanted, normalizedName(connection.name))
            guard similarity >= 0.88 else { return nil }
            return (similarity, detailOverlap(details, connection.details), connection)
        }.sorted { lhs, rhs in lhs.0 == rhs.0 ? lhs.1 > rhs.1 : lhs.0 > rhs.0 }

        guard let best = ranked.first else { return Outcome(connection: nil, confidence: 0, reason: "no first-degree name match") }
        let runnerUp = ranked.count > 1 ? ranked[1].0 : 0
        if best.0 >= 0.97, best.0 - runnerUp >= 0.03 {
            return Outcome(connection: best.2, confidence: best.0 * 0.96 + best.1 * 0.04, reason: "high-confidence fuzzy name")
        }
        if best.0 >= 0.92, best.1 >= 0.34, best.0 - runnerUp >= 0.02 {
            return Outcome(connection: best.2, confidence: best.0 * 0.8 + best.1 * 0.2, reason: "fuzzy name plus matching details")
        }
        return Outcome(connection: nil, confidence: best.0, reason: "possible match: \(best.2.name)")
    }
}

public enum ResultsCSV {
    public static func encode(_ results: [NetworkResult]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = [[
            "name", "details", "degree", "confidence", "linkedin_url",
            "matched_connection", "match_reason", "reviewed_at"
        ]] + results.map { result in
            [
                result.attendee.name,
                result.attendee.details,
                result.degree.rawValue,
                result.confidence.map { String(format: "%.3f", $0) } ?? "",
                result.linkedInURL,
                result.matchedConnection,
                result.matchReason,
                result.reviewedAt.map(formatter.string) ?? "",
            ]
        }
        return CSV.encode(rows: rows)
    }
}

public func normalizedName(_ value: String) -> String {
    let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    var words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "phd", "mba", "md", "esq"]
    while let last = words.last, suffixes.contains(last.lowercased()) { words.removeLast() }
    return words.map { $0.lowercased() }.joined(separator: " ")
}

private func detailOverlap(_ left: String, _ right: String) -> Double {
    let a = Set(normalizedName(left).split(separator: " ").filter { $0.count > 1 })
    let b = Set(normalizedName(right).split(separator: " ").filter { $0.count > 1 })
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    return Double(a.intersection(b).count) / Double(min(a.count, b.count))
}

private func nameSimilarity(_ left: String, _ right: String) -> Double {
    if left == right { return 1 }
    let a = Array(left), b = Array(right)
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    var previous = Array(0...b.count)
    for (i, leftCharacter) in a.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: b.count)
        for (j, rightCharacter) in b.enumerated() {
            current[j + 1] = [
                current[j] + 1,
                previous[j + 1] + 1,
                previous[j] + (leftCharacter == rightCharacter ? 0 : 1)
            ].min()!
        }
        previous = current
    }
    return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
}
