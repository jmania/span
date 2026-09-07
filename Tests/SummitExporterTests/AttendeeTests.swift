import XCTest
@testable import SummitExporter

final class AttendeeTests: XCTestCase {
    func testParsesImageLabel() {
        let attendee = Attendee.parse(accessibilityLabel: "Attendee profile image, Maya Chen, Example Corp")
        XCTAssertEqual(attendee?.name, "Maya Chen")
        XCTAssertEqual(attendee?.details, "Example Corp")
    }

    func testKeepsCommasInDetails() {
        let attendee = Attendee.parse(accessibilityLabel: "Jordan Patel, Product lead, observability at Example Corp")
        XCTAssertEqual(attendee?.name, "Jordan Patel")
        XCTAssertEqual(attendee?.details, "Product lead, observability at Example Corp")
    }

    func testIgnoresControls() {
        XCTAssertNil(Attendee.parse(accessibilityLabel: "Add connection"))
        XCTAssertNil(Attendee.parse(accessibilityLabel: "1352 attendees"))
    }
}
