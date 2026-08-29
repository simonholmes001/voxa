import XCTest
@testable import VoxaAppShell

final class AppNavigationModelTests: XCTestCase {
    func testDefaultsToHomeRoute() {
        let model = AppNavigationModel()
        XCTAssertEqual(model.selectedRoute, .home)
    }

    func testInitialRouteCanBeOverridden() {
        let model = AppNavigationModel(selectedRoute: .learn)
        XCTAssertEqual(model.selectedRoute, .learn)
    }

    func testSelectUpdatesSelectedRoute() {
        let model = AppNavigationModel()
        model.select(.progress)
        XCTAssertEqual(model.selectedRoute, .progress)
    }
}
