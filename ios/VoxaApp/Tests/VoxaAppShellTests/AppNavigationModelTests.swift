import XCTest
@testable import VoxaAppShell

final class AppNavigationModelTests: XCTestCase {
    func testDefaultsToHomeRoute() {
        let model = AppNavigationModel()
        XCTAssertEqual(model.selectedRoute, .home)
    }

    func testInitialRouteCanBeOverridden() {
        let model = AppNavigationModel(selectedRoute: .practice)
        XCTAssertEqual(model.selectedRoute, .practice)
    }

    func testSelectUpdatesSelectedRoute() {
        let model = AppNavigationModel()
        model.select(.progress)
        XCTAssertEqual(model.selectedRoute, .progress)
    }
}
