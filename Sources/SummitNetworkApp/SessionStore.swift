import Foundation
#if canImport(SummitCore)
import SummitCore
#endif

struct SavedSession: Codable {
    let attendees: [Attendee]
    let results: [NetworkResult]
    var connections: [Connection]? = nil
}

enum SessionStore {
    static var diagnosticsURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("scan-diagnostics.txt") }
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Summit Network", isDirectory: true)
            .appendingPathComponent("session-v2.json")
    }

    static func load(from url: URL? = nil) throws -> SavedSession {
        try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: url ?? fileURL))
    }

    static func save(_ session: SavedSession, to url: URL? = nil) throws {
        let destination = url ?? fileURL
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: destination, options: .atomic)
    }

    static func clear(at url: URL? = nil) throws {
        let destination = url ?? fileURL
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }
}
