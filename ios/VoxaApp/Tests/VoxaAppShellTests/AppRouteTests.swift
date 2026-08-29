import XCTest
@testable import VoxaAppShell

final class AppRouteTests: XCTestCase {
    func testPrimaryRoutesExistInExpectedOrder() {
        XCTAssertEqual(
            AppRoute.allCases,
            [.home, .talk, .learn, .review, .progress, .settings]
        )
    }

    func testEveryRouteHasNonEmptyTitleAndSymbol() {
        for route in AppRoute.allCases {
            XCTAssertFalse(route.title.isEmpty, "\(route) is missing a title")
            XCTAssertFalse(
                route.systemImageName.isEmpty,
                "\(route) is missing an SF Symbol name"
            )
        }
    }

    func testRouteIdentifierMatchesRawValue() {
        XCTAssertEqual(AppRoute.talk.id, AppRoute.talk.rawValue)
        XCTAssertEqual(AppRoute.progress.id, "progress")
    }
}
