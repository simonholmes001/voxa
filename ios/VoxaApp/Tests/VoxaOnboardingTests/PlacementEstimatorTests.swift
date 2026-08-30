import XCTest
@testable import VoxaOnboarding

final class PlacementEstimatorTests: XCTestCase {
    func testNoAffirmationsEstimatesA1() {
        XCTAssertEqual(PlacementEstimator.estimate(from: [false, false, false, false, false]), .a1)
    }

    func testEmptyAnswersEstimatesA1() {
        XCTAssertEqual(PlacementEstimator.estimate(from: []), .a1)
    }

    func testFirstTwoAffirmedEstimatesA2() {
        XCTAssertEqual(PlacementEstimator.estimate(from: [true, true, false, false, false]), .a2)
    }

    func testAllAffirmedEstimatesTopRung() {
        XCTAssertEqual(PlacementEstimator.estimate(from: [true, true, true, true, true]), .c1)
    }

    func testGapStopsTheLadder() {
        // A1 affirmed, A2 not — later affirmations are ignored.
        XCTAssertEqual(PlacementEstimator.estimate(from: [true, false, true, true, true]), .a1)
    }
}
