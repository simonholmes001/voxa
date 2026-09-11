import XCTest
@testable import VoxaRealtime

@MainActor
final class IdleTimerControlTests: XCTestCase {
    func testRecordingControlStartsWithNoEvents() {
        let control = RecordingIdleTimerControl()
        XCTAssertEqual(control.events, [])
        XCTAssertFalse(control.isCurrentlyKeepingAwake)
    }

    func testKeepAwakeThenAllowSleepBalancesBackToNotKeepingAwake() {
        let control = RecordingIdleTimerControl()
        control.keepScreenAwake()
        XCTAssertTrue(control.isCurrentlyKeepingAwake)
        control.allowScreenSleep()
        XCTAssertFalse(control.isCurrentlyKeepingAwake)
        XCTAssertEqual(control.events, [.keepAwake, .allowSleep])
    }

    func testDoubleAllowSleepIsSafeAndReportsNotKeepingAwake() {
        // The view model may call allowScreenSleep from a teardown path
        // that races with `end()`. The RecordingIdleTimerControl must
        // tolerate an unmatched pair without asserting or crashing.
        let control = RecordingIdleTimerControl()
        control.allowScreenSleep()
        control.allowScreenSleep()
        XCTAssertFalse(control.isCurrentlyKeepingAwake)
    }

    func testSystemIdleTimerControlInitialisesWithoutCrashing() {
        // Smoke test: on macOS the system control is a no-op; on iOS it
        // touches UIApplication. Neither should throw from init on any
        // supported test host.
        _ = SystemIdleTimerControl()
    }
}
