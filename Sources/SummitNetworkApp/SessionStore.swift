import Foundation
#if canImport(SummitCore)
import SummitCore
#endif

struct SavedSession: Codable {
    let attendees: [Attendee]
    let results: [NetworkResult]
}

enum SessionStore {
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Summit Network", isDirectory: true)
            .appendingPathComponent("session-v2.json")
    }

    static func load() throws -> SavedSession {
        try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: fileURL))
    }

    static func save(_ session: SavedSession) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: fileURL, options: .atomic)
    }

    static func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
