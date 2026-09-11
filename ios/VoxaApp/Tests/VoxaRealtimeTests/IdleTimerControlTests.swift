import XCTest
@testable import VoxaRealtime

@MainActor
final class IdleTimerControlTests: XCTestCase {

    // MARK: - RecordingIdleTimerControl (per-instance semantics)

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

    func testDoubleKeepAwakeOnSameInstanceIsANoOpAfterFirstClaim() {
        // Per-instance semantics: a second keep call while already
        // holding a claim doesn't re-emit or re-retain. Matches the
        // view model's start-once / end-once state transitions.
        let control = RecordingIdleTimerControl()
        control.keepScreenAwake()
        control.keepScreenAwake()
        XCTAssertEqual(control.events, [.keepAwake])
        XCTAssertTrue(control.isCurrentlyKeepingAwake)
    }

    func testUnmatchedAllowSleepIsANoOp() {
        // Reviewer scenario: end() from idle must not force auto-lock
        // if we never claimed. Silent no-op is the correct behaviour.
        let control = RecordingIdleTimerControl()
        control.allowScreenSleep()
        control.allowScreenSleep()
        XCTAssertEqual(control.events, [])
        XCTAssertFalse(control.isCurrentlyKeepingAwake)
    }

    // MARK: - IdleTimerCoordinator (process-shared refcount)

    func testCoordinatorRetainReleaseRoundTripFromZero() {
        let coordinator = IdleTimerCoordinator()
        XCTAssertEqual(coordinator.currentClaimCount, 0)
        coordinator.retain()
        XCTAssertEqual(coordinator.currentClaimCount, 1)
        coordinator.release()
        XCTAssertEqual(coordinator.currentClaimCount, 0)
    }

    func testCoordinatorReleaseAtZeroIsANoOp() {
        // Guard against underflow. An unmatched release must not tip
        // the counter negative and it must not force the flag off.
        let coordinator = IdleTimerCoordinator()
        coordinator.release()
        coordinator.release()
        XCTAssertEqual(coordinator.currentClaimCount, 0)
    }

    func testCoordinatorMultipleClaimsMustBeReleasedIndividually() {
        // Two overlapping components each need to release their own
        // claim before auto-lock resumes.
        let coordinator = IdleTimerCoordinator()
        coordinator.retain()
        coordinator.retain()
        XCTAssertEqual(coordinator.currentClaimCount, 2)
        coordinator.release()
        XCTAssertEqual(coordinator.currentClaimCount, 1)
        coordinator.release()
        XCTAssertEqual(coordinator.currentClaimCount, 0)
    }

    // MARK: - SystemIdleTimerControl (production impl, shared coordinator)

    func testSystemControlInitDoesNotClaim() {
        let coordinator = IdleTimerCoordinator()
        _ = SystemIdleTimerControl()
        XCTAssertEqual(coordinator.currentClaimCount, 0)
    }

    func testSystemControlClaimAndReleaseRouteThroughSharedCoordinator() {
        // Reset the shared instance so we can assert against it
        // without leakage from any prior test in this run.
        IdleTimerCoordinator.shared.resetForTesting()

        let control = SystemIdleTimerControl()
        control.keepScreenAwake()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 1)
        control.allowScreenSleep()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 0)
    }

    func testTwoOverlappingSystemControlsBothHoldTheirOwnClaimsIndependently() {
        // The reviewer's headline scenario. Two view models start
        // sessions overlappingly. Ending one MUST NOT release the
        // other's claim on the process-shared flag.
        IdleTimerCoordinator.shared.resetForTesting()

        let sessionA = SystemIdleTimerControl()
        let sessionB = SystemIdleTimerControl()

        sessionA.keepScreenAwake()
        sessionB.keepScreenAwake()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 2)

        sessionA.allowScreenSleep()
        // sessionB is still live — the flag stays disabled.
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 1)

        sessionB.allowScreenSleep()
        // Now both released, back to auto-lock.
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 0)
    }

    func testSystemControlDoubleClaimIsIdempotentAgainstSharedCoordinator() {
        // A view model that (hypothetically) called keepScreenAwake
        // twice for the same session must not double-retain against
        // the shared coordinator — otherwise its single release would
        // leave the coordinator's count at 1 and starve auto-lock.
        IdleTimerCoordinator.shared.resetForTesting()

        let control = SystemIdleTimerControl()
        control.keepScreenAwake()
        control.keepScreenAwake()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 1)
        control.allowScreenSleep()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 0)
    }

    func testSystemControlUnmatchedReleaseDoesNotStarveOverlappingClaimant() {
        // The reviewer's specific worry: unconditional release from
        // one view model's teardown path shouldn't drop the count
        // below where another live session's claim keeps it.
        IdleTimerCoordinator.shared.resetForTesting()

        let liveSession = SystemIdleTimerControl()
        let strangerTearingDown = SystemIdleTimerControl()

        liveSession.keepScreenAwake()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 1)

        // Stranger never claimed. Its unmatched release must be a no-op.
        strangerTearingDown.allowScreenSleep()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 1)

        liveSession.allowScreenSleep()
        XCTAssertEqual(IdleTimerCoordinator.shared.currentClaimCount, 0)
    }
}
