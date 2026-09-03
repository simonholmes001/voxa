import XCTest
@testable import VoxaAppShell

final class RoutePlaceholderTests: XCTestCase {
    func testLearnPlaceholderContent() {
        let content = AppRoute.learn.placeholderContent()
        XCTAssertEqual(content.headline, "Learn")
        XCTAssertTrue(content.subheadline.contains("lesson"))
        XCTAssertEqual(content.actionTitle, "Start Lesson")
    }

    func testReviewPlaceholderContent() {
        let content = AppRoute.review.placeholderContent()
        XCTAssertEqual(content.headline, "Review")
        XCTAssertTrue(content.subheadline.contains("review sessions"))
        XCTAssertEqual(content.actionTitle, "Start Review")
    }

    func testSettingsPlaceholderContentIsMore() {
        let content = AppRoute.settings.placeholderContent()
        XCTAssertEqual(content.headline, "More")
        XCTAssertTrue(content.subheadline.contains("account"))
        XCTAssertEqual(content.actionTitle, "Open Settings")
    }
}
