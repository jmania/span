import XCTest
@testable import SummitCore

final class SummitCoreTests: XCTestCase {
    func testParsesAccessibilityLabels() {
        let attendee = Attendee.parse(accessibilityLabel: "Attendee profile image, Maya Chen, Example Corp")
        XCTAssertEqual(attendee?.name, "Maya Chen")
        XCTAssertEqual(attendee?.details, "Example Corp")
        let noImagePrefix = Attendee.parse(accessibilityLabel: "Aabhas Sharma, Product lead, observability at Salesforce")
        XCTAssertEqual(noImagePrefix?.name, "Aabhas Sharma")
        XCTAssertEqual(noImagePrefix?.details, "Product lead, observability at Salesforce")
        let initials = Attendee.parse(accessibilityLabel: "A.J. Angus, Axon")
        XCTAssertEqual(initials?.name, "A.J. Angus")
        let noDetails = Attendee.parse(accessibilityLabel: "Attendee profile image, Abhi Motgi")
        XCTAssertEqual(noDetails?.name, "Abhi Motgi")
        XCTAssertNil(Attendee.parse(accessibilityLabel: "Description"))
        XCTAssertNil(Attendee.parse(accessibilityLabel: "Add connection"))
    }

    func testCSVHandlesQuotedNewlinesAndCommas() {
        let rows = CSV.parse("name,details\r\n\"Chen, Maya\",\"Line one\nLine two\"\r\n")
        XCTAssertEqual(rows, [["name", "details"], ["Chen, Maya", "Line one\nLine two"]])
    }

    func testConnectionsPreambleAndMatching() throws {
        let csv = """
        Notes:
        This export contains a preamble.
        First Name,Last Name,URL,Company,Position
        Maya,Chen,https://example.test/maya,Example Corp,Product
        """.data(using: .utf8)!
        let connections = try ConnectionsCSV.decode(csv)
        let attendee = Attendee(name: "Maya Chen", details: "Example Corp", sourceLabel: "Maya Chen, Example Corp")
        let summary = NetworkMatcher.match(attendees: [attendee], connections: connections)
        XCTAssertEqual(summary.firstDegreeCount, 1)
        XCTAssertEqual(summary.results[0].linkedInURL, "https://example.test/maya")
    }
}
