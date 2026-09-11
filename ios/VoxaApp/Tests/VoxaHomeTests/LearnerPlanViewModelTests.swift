import XCTest
@testable import VoxaHome
import VoxaRealtime

@MainActor
final class LearnerPlanViewModelTests: XCTestCase {
    func testStartsIdle() {
        let model = LearnerPlanViewModel(
            service: FakeLearnerPlanService(result: .success(sampleAPlan())),
            accessTokenProvider: { "tok" })
        XCTAssertEqual(model.state, .idle)
    }

    func testLoadReachesReadyWithFetchedPlan() async {
        let expected = sampleAPlan()
        let model = LearnerPlanViewModel(
            service: FakeLearnerPlanService(result: .success(expected)),
            accessTokenProvider: { "tok" })

        await model.load()

        XCTAssertEqual(model.state, .ready(expected))
    }

    func testLoadWithoutAccessTokenFailsWithSignInMessage() async {
        let model = LearnerPlanViewModel(
            service: FakeLearnerPlanService(result: .success(sampleAPlan())),
            accessTokenProvider: { nil })

        await model.load()

        if case let .failed(message) = model.state {
            XCTAssertTrue(message.contains("sign in"), "expected sign-in message, got: \(message)")
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    func testTransportFailureSurfacesReadableMessage() async {
        let model = LearnerPlanViewModel(
            service: FakeLearnerPlanService(result: .failure(LearnerPlanServiceError.transport)),
            accessTokenProvider: { "tok" })

        await model.load()

        if case let .failed(message) = model.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    func testNotConfiguredSurfacesTheReason() async {
        let model = LearnerPlanViewModel(
            service: NotConfiguredLearnerPlanService(reason: "no backend for this build"),
            accessTokenProvider: { "tok" })

        await model.load()

        if case let .failed(message) = model.state {
            XCTAssertEqual(message, "no backend for this build")
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    func testResetReturnsStateToIdle() async {
        let model = LearnerPlanViewModel(
            service: FakeLearnerPlanService(result: .success(sampleAPlan())),
            accessTokenProvider: { "tok" })

        await model.load()
        XCTAssertNotEqual(model.state, .idle)
        model.reset()
        XCTAssertEqual(model.state, .idle)
    }

    // MARK: - Helpers

    private func sampleAPlan() -> LearnerPlan {
        LearnerPlan(
            correlationId: "corr-x",
            recommendedSession: RecommendedSession(
                activityIntent: "mistakes_replay",
                focusTitle: "past participles",
                reason: "you missed the past participle in your last session."),
            focusAreas: ["past participle of aller"])
    }
}

private final class FakeLearnerPlanService: LearnerPlanService, @unchecked Sendable {
    let result: Result<LearnerPlan, Error>
    init(result: Result<LearnerPlan, Error>) { self.result = result }

    func fetchTodayPlan(accessToken: String) async throws -> LearnerPlan {
        return try result.get()
    }
}
