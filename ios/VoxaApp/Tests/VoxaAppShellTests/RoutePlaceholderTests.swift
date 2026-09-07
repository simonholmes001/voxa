import XCTest
@testable import VoxaAppShell

final class RoutePlaceholderTests: XCTestCase {
    func testLearnPlaceholderContent() {
        let content = AppRoute.learn.placeholderContent()
        XCTAssertEqual(content.headline, "Learn")
        XCTAssertTrue(content.subheadline.contains("tutor-led lesson"))
        XCTAssertEqual(content.actionTitle, "Continue Learning")
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
