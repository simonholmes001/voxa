import XCTest
@testable import VoxaAppShell

final class AdaptiveLayoutResolverTests: XCTestCase {
    func testCompactHorizontalSizeClassUsesTabBar() {
        XCTAssertEqual(AdaptiveLayoutResolver.layout(for: .compact), .tabBar)
    }

    func testRegularHorizontalSizeClassUsesSplitView() {
        XCTAssertEqual(AdaptiveLayoutResolver.layout(for: .regular), .splitView)
    }

    func testUnknownHorizontalSizeClassDefaultsToTabBar() {
        XCTAssertEqual(AdaptiveLayoutResolver.layout(for: nil), .tabBar)
    }
}
