import Foundation

public struct Attendee: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let details: String
    public let sourceLabel: String

    public init(id: UUID = UUID(), name: String, details: String, sourceLabel: String) {
        self.id = id
        self.name = name
        self.details = details
        self.sourceLabel = sourceLabel
    }

    public static func parse(accessibilityLabel rawLabel: String) -> Attendee? {
        var label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Attendee profile image,"
        if label.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil {
            label = String(label.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let ignored = [
            "Add connection", "Search", "All attendees", "Your connections",
            "Message", "back", "scan_network"
        ]
        guard !ignored.contains(where: { label.caseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }

        let parts = label.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let first = parts.first, parts.count >= 2, looksLikeName(first) else {
            return nil
        }

        return Attendee(
            name: first,
            details: parts.dropFirst().joined(separator: ", "),
            sourceLabel: rawLabel
        )
    }

    private static func looksLikeName(_ value: String) -> Bool {
        guard value.count >= 2, value.count <= 100 else { return false }
        guard value.rangeOfCharacter(from: .letters) != nil else { return false }
        let forbidden = ["attendees", "information added", "social profiles", "interests", "about"]
        return !forbidden.contains { value.localizedCaseInsensitiveContains($0) }
    }
}

public func csvField(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}
