import Foundation
#if canImport(SummitCore)
import SummitCore
#endif

struct Options {
    var bundleIdentifier = "com.zuddl.lennyfriendssummit"
    var output = "attendees.csv"
    var maximum = 5_000
    var pauseMilliseconds: UInt32 = 450
}

func parseOptions() throws -> Options {
    var options = Options()
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--bundle-id":
            guard let value = iterator.next() else { throw CLIError.usage("--bundle-id needs a value") }
            options.bundleIdentifier = value
        case "--output", "-o":
            guard let value = iterator.next() else { throw CLIError.usage("--output needs a value") }
            options.output = value
        case "--max":
            guard let value = iterator.next(), let parsed = Int(value), parsed > 0 else { throw CLIError.usage("--max needs a positive number") }
            options.maximum = parsed
        case "--pause-ms":
            guard let value = iterator.next(), let parsed = UInt32(value), parsed >= 100 else { throw CLIError.usage("--pause-ms needs a number of at least 100") }
            options.pauseMilliseconds = parsed
        case "--help", "-h":
            print(usageText)
            exit(0)
        default:
            throw CLIError.usage("Unknown option: \(argument)")
        }
    }
    return options
}

enum CLIError: LocalizedError {
    case usage(String)
    var errorDescription: String? {
        switch self {
        case .usage(let message): return "\(message)\n\n\(usageText)"
        }
    }
}

let usageText = """
Usage: summit-export [options]

Before running, open Lenny & Friends → Attendees → All attendees.

Options:
  -o, --output PATH      CSV destination (default: attendees.csv)
      --bundle-id ID     App bundle identifier
      --max NUMBER       Safety limit (default: 5000)
      --pause-ms NUMBER  Pause after each scroll (default: 450)
  -h, --help             Show this help
"""

func reportProgress(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

do {
    let options = try parseOptions()
    let client = try AXClient(bundleIdentifier: options.bundleIdentifier)
    reportProgress("Reading attendees… keep the attendee window open.\n")
    let attendees = try client.extractAttendees(
        maximum: options.maximum,
        pauseMilliseconds: options.pauseMilliseconds
    ) { count in
        reportProgress("\rFound \(count) unique attendees")
    }
    reportProgress("\n")

    let timestamp = ISO8601DateFormatter().string(from: Date())
    var csv = "name,details,source_label,extracted_at\n"
    for attendee in attendees {
        csv += [attendee.name, attendee.details, attendee.sourceLabel, timestamp]
            .map(csvField).joined(separator: ",") + "\n"
    }
    try csv.write(toFile: options.output, atomically: true, encoding: .utf8)
    print("Wrote \(attendees.count) attendees to \(options.output)")
} catch {
    reportProgress("Error: \(error.localizedDescription)\n")
    exit(1)
}
