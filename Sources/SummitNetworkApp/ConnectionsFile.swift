import Foundation

enum ConnectionsFileError: LocalizedError {
    case unsupportedFile
    case archiveFailed
    case connectionsNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "Choose LinkedIn's ZIP archive or Connections.csv."
        case .archiveFailed: return "The LinkedIn archive could not be opened."
        case .connectionsNotFound: return "Connections.csv was not found in that archive."
        }
    }
}

enum ConnectionsFile {
    static func read(from url: URL) throws -> Data {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        switch url.pathExtension.lowercased() {
        case "csv":
            return try Data(contentsOf: url)
        case "zip":
            return try readArchive(url)
        default:
            throw ConnectionsFileError.unsupportedFile
        }
    }

    private static func readArchive(_ url: URL) throws -> Data {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummitNetwork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ConnectionsFileError.archiveFailed }

        guard let enumerator = FileManager.default.enumerator(
            at: destination,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw ConnectionsFileError.connectionsNotFound }
        for case let candidate as URL in enumerator {
            if candidate.lastPathComponent.caseInsensitiveCompare("Connections.csv") == .orderedSame {
                return try Data(contentsOf: candidate)
            }
        }
        throw ConnectionsFileError.connectionsNotFound
    }
}
