import XCTest
@testable import VoxaAppShell

final class RoutePlaceholderTests: XCTestCase {
    func testPracticePlaceholderContent() {
        let content = AppRoute.practice.placeholderContent()
        XCTAssertEqual(content.headline, "Practice")
        XCTAssertTrue(content.subheadline.contains("today's recommended session"))
        XCTAssertEqual(content.actionTitle, "Start talking")
    }

    func testReviewPlaceholderContent() {
        let content = AppRoute.review.placeholderContent()
        XCTAssertEqual(content.headline, "Review")
        XCTAssertTrue(content.subheadline.contains("mistakes"))
        XCTAssertEqual(content.actionTitle, "Review with Tutor")
    }

    func testSettingsPlaceholderContentIsMore() {
        let content = AppRoute.settings.placeholderContent()
        XCTAssertEqual(content.headline, "Settings")
        XCTAssertTrue(content.subheadline.contains("language profiles"))
        XCTAssertEqual(content.actionTitle, "Add a Language")
    }
}
