import XCTest
@testable import VoxaDomain

final class VoxaDomainModuleTests: XCTestCase {
    func testModuleBoundaryIsAvailable() {
        XCTAssertEqual(VoxaDomain.moduleName, "VoxaDomain")
    }
}
