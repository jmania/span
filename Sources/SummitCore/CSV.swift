import Foundation

public enum CSVError: LocalizedError {
    case unreadableText
    case missingConnectionsHeader
    case missingAttendeeHeader

    public var errorDescription: String? {
        switch self {
        case .unreadableText: return "The file is not a readable CSV."
        case .missingConnectionsHeader: return "No LinkedIn connections header was found in this file."
        case .missingAttendeeHeader: return "The attendee CSV must contain name and details columns."
        }
    }
}

public enum CSV {
    public static func decode(_ data: Data) throws -> [[String]] {
        let text: String
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            text = latin1
        } else {
            throw CSVError.unreadableText
        }
        return parse(text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text)
    }

    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        func finishField() {
            row.append(field)
            field = ""
        }
        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    quoted = true
                case ",":
                    finishField()
                case "\n":
                    finishRow()
                case "\r":
                    finishRow()
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }

    public static func encode(rows: [[String]]) -> String {
        rows.map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }
}

public enum AttendeeCSV {
    public static func encode(_ attendees: [Attendee]) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let rows = [["name", "details", "source_label", "extracted_at"]] + attendees.map {
            [$0.name, $0.details, $0.sourceLabel, timestamp]
        }
        return CSV.encode(rows: rows)
    }

    public static func decode(_ data: Data) throws -> [Attendee] {
        let rows = try CSV.decode(data)
        guard let headerIndex = rows.firstIndex(where: { row in
            Set(row.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }).contains("name")
        }) else { throw CSVError.missingAttendeeHeader }
        let headers = rows[headerIndex].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let nameIndex = headers.firstIndex(of: "name") else { throw CSVError.missingAttendeeHeader }
        let detailsIndex = headers.firstIndex(of: "details")
        let sourceIndex = headers.firstIndex(of: "source_label")
        return rows.dropFirst(headerIndex + 1).compactMap { row in
            guard nameIndex < row.count else { return nil }
            let name = row[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let details = detailsIndex.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let source = sourceIndex.flatMap { $0 < row.count ? row[$0] : nil } ?? "\(name), \(details)"
            return Attendee(name: name, details: details, sourceLabel: source)
        }
    }
}
