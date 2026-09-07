import Foundation

public struct Connection: Hashable, Codable, Sendable {
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

    public var details: String { [company, position].filter { !$0.isEmpty }.joined(separator: " ") }
}


public struct MatchCandidate: Codable, Identifiable, Sendable {
    public let connection: Connection
    public let reason: String
    /// Ordering evidence, not a calibrated probability.
    public let rank: Double
    public var otherAttendeeCount: Int = 0
    public var id: String { connection.identityKey }
}

public extension Connection {
    var identityKey: String {
        if let url = linkedInProfileURL(url) { return url.absoluteString.lowercased() }
        return [normalizedName(name), normalizedName(company), normalizedName(position)].joined(separator: "|")
    }
}

public func linkedInProfileURL(_ value: String) -> URL? {
    guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let host = parts.host?.lowercased(),
          host == "linkedin.com" || host.hasSuffix(".linkedin.com"),
          parts.scheme == "https" || parts.scheme == "http",
          parts.user == nil, parts.password == nil else { return nil }
    let path = parts.path.split(separator: "/")
    guard path.count == 2, path[0] == "in", !path[1].isEmpty else { return nil }
    parts.scheme = "https"
    parts.host = "www.linkedin.com"
    parts.port = nil
    parts.path = "/in/\(path[1])"
    parts.query = nil
    parts.fragment = nil
    return parts.url
}

public enum ConnectionDegree: String, Codable, CaseIterable, Sendable {
    case first = "1st"
    case second = "2nd"
    case notConnected = "not_connected"
    case review
    case skip

    public var label: String {
        switch self {
        case .first: return "Confirmed by you"
        case .second: return "Second degree"
        case .notConnected: return "Not connected"
        case .review: return "Not confirmed"
        case .skip: return "Undecided"
        }
    }
}

public struct NetworkResult: Codable, Identifiable, Sendable {
    public let id: UUID
    public let attendee: Attendee
    public var degree: ConnectionDegree
    public let confidence: Double?
    public var linkedInURL: String
    public var matchedConnection: String
    public let matchReason: String
    public var reviewedAt: Date?
    public var candidates: [MatchCandidate]? = nil
    public var rejectedCandidateIDs: [String]? = nil
    public var confirmedCandidateID: String? = nil

    public var isConfirmed: Bool { degree == .first && reviewedAt != nil }
    public var activeCandidates: [MatchCandidate] {
        (candidates ?? []).filter { !(rejectedCandidateIDs ?? []).contains($0.id) }
    }
    public var hasSuggestion: Bool { !isConfirmed && !activeCandidates.isEmpty }


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
        var seen = Set<String>()
        let unique = connections.filter { seen.insert($0.identityKey).inserted }
        let prepared = unique.map { ($0, normalizedName($0.name), meaningfulWords($0.company)) }
        var results = attendees.map { attendee -> NetworkResult in
            let wanted = normalizedName(attendee.name)
            let eventWords = meaningfulWords(attendee.details)
            let candidates = prepared.compactMap { item -> MatchCandidate? in
                let (connection, name, companyWords) = item
                let similarity = nameSimilarity(wanted, name)
                guard !wanted.isEmpty, similarity >= 0.88 else { return nil }
                let companyMatches = !companyWords.isEmpty && companyWords.isSubset(of: eventWords)
                let reason = similarity == 1
                    ? (companyMatches ? "Same name and company words. Please confirm the identity." : "Same name only. This may be a different person.")
                    : (companyMatches ? "Similar name and company words. Please confirm the identity." : "Similar name only. This may be a different person.")
                return MatchCandidate(connection: connection, reason: reason,
                                      rank: similarity + (companyMatches ? 0.15 : 0))
            }.sorted {
                if $0.rank != $1.rank { return $0.rank > $1.rank }
                return $0.id < $1.id
            }
            var result = NetworkResult(attendee: attendee, degree: .review, confidence: nil,
                                       linkedInURL: "", matchedConnection: "",
                                       matchReason: candidates.isEmpty ? "No suggestion from this export; connection status unknown." : "Possible identity matches; not confirmed.")
            result.candidates = candidates
            return result
        }
        var uses: [String: Int] = [:]
        for result in results {
            for candidate in result.candidates ?? [] { uses[candidate.id, default: 0] += 1 }
        }
        for i in results.indices {
            results[i].candidates = results[i].candidates?.map { candidate in
                var item = candidate
                item.otherAttendeeCount = max(0, (uses[item.id] ?? 1) - 1)
                return item
            }
        }
        return MatchSummary(results: results)
    }
}

private func meaningfulWords(_ value: String) -> Set<String> {
    let generic: Set<String> = ["inc", "llc", "ltd", "corp", "company", "the", "and", "at",
        "product", "manager", "director", "lead", "founder", "consultant", "independent", "self", "employed"]
    return Set(normalizedName(value).split(separator: " ").map(String.init)
        .filter { $0.count > 1 && !generic.contains($0) })
}

public enum ResultsCSV {
    public static func encode(_ results: [NetworkResult]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = [["name", "event_details", "status", "confirmed_profile_url",
                     "possible_connection_names", "possible_connection_details", "possible_profile_urls",
                     "rejected_candidate_ids", "reviewed_at", "event_profile_url", "event_profile_source"]]
        for result in results {
            let candidates = result.isConfirmed ? [] : result.activeCandidates
            let status = result.isConfirmed ? "confirmed_by_you"
                : (result.hasSuggestion ? "possible_connection" : "unconfirmed")
            rows.append([
                result.attendee.name, result.attendee.details, status,
                result.isConfirmed ? result.linkedInURL : "",
                candidates.map { $0.connection.name }.joined(separator: " | "),
                candidates.map { $0.connection.details }.joined(separator: " | "),
                candidates.map { linkedInProfileURL($0.connection.url)?.absoluteString ?? "" }.joined(separator: " | "),
                (result.rejectedCandidateIDs ?? []).joined(separator: " | "),
                result.reviewedAt.map(formatter.string) ?? "",
                result.attendee.profileEvidence?.linkedInURL ?? "",
                result.attendee.profileEvidence?.source ?? ""
            ])
        }
        return CSV.encode(rows: rows.map { $0.map { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["=", "+", "-", "@"].contains(where: { trimmed.hasPrefix($0) }) ? "'" + value : value
        } })
    }
}

public func normalizedName(_ value: String) -> String {
    let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    var words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "phd", "mba", "md", "esq"]
    while let last = words.last, suffixes.contains(last.lowercased()) { words.removeLast() }
    return words.map { $0.lowercased() }.joined(separator: " ")
}

private func nameSimilarity(_ left: String, _ right: String) -> Double {
    if left == right { return 1 }
    let a = Array(left), b = Array(right)
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    guard Double(abs(a.count - b.count)) / Double(max(a.count, b.count)) <= 0.12 else { return 0 }
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
