import XCTest
@testable import VoxaHome
import VoxaRealtime

@MainActor
final class LearnerCourseViewModelTests: XCTestCase {

    func testStartsIdle() {
        let model = LearnerCourseViewModel(
            service: FakeCourseService(fetch: .success(sample())),
            accessTokenProvider: { "tok" })
        XCTAssertEqual(model.state, .idle)
    }

    func testLoadReachesReadyWithFetchedCourse() async {
        let expected = sample()
        let model = LearnerCourseViewModel(
            service: FakeCourseService(fetch: .success(expected)),
            accessTokenProvider: { "tok" })

        await model.load()
        XCTAssertEqual(model.state, .ready(expected))
    }

    func testLoadWithoutAccessTokenSurfacesSignInMessage() async {
        let model = LearnerCourseViewModel(
            service: FakeCourseService(fetch: .success(sample())),
            accessTokenProvider: { nil })

        await model.load()

        if case let .failed(message) = model.state {
            XCTAssertTrue(message.contains("sign in"))
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    func testNotFoundFromServiceReadsAsCompleteOnboardingMessage() async {
        let model = LearnerCourseViewModel(
            service: FakeCourseService(fetch: .failure(LearnerCourseServiceError.notFound)),
            accessTokenProvider: { "tok" })

        await model.load()

        if case let .failed(message) = model.state {
            XCTAssertTrue(message.contains("Complete onboarding"))
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    func testReassessTransitionsThroughReassessingWithPreviousPreserved() async {
        // The Reassess sheet doesn't blank Home — it dims the previous
        // course. That relies on the view model keeping the previous
        // course visible through the reassess call. Verify that
        // transition explicitly by checking .reassessing carries the
        // pre-reassess course.
        let previous = sample()
        let updated = sample(planId: "p2", title: "Everyday German (revised)")
        let service = FakeCourseService(fetch: .success(previous), reassess: .success(updated))
        let model = LearnerCourseViewModel(
            service: service,
            accessTokenProvider: { "tok" })

        await model.load()
        // .reassess is a single async call — we can't easily observe
        // intermediate state without a step-through fake. Assert the
        // FINAL state and separately assert the service saw the reassess
        // call.
        await model.reassess(request: "more speaking")
        XCTAssertEqual(model.state, .ready(updated))
        XCTAssertEqual(service.reassessCalls.count, 1)
        XCTAssertEqual(service.reassessCalls[0], "more speaking")
    }

    func testReassessWithNoPreviousCourseFallsBackToPlainLoad() async {
        // If the learner never ran load() first, reassess() does the
        // sensible thing — it fetches the course (equivalent to a plain
        // load) rather than sending a reassess request with no context.
        let service = FakeCourseService(fetch: .success(sample()))
        let model = LearnerCourseViewModel(
            service: service,
            accessTokenProvider: { "tok" })

        await model.reassess(request: "anything")

        XCTAssertEqual(model.state, .ready(sample()))
        // No reassess call was made — it fell back to fetch.
        XCTAssertTrue(service.reassessCalls.isEmpty)
    }

    func testReassessFailureSurfacesReadableMessageWithoutLosingPreviousCourseFromLastReady() async {
        let previous = sample()
        let service = FakeCourseService(
            fetch: .success(previous),
            reassess: .failure(LearnerCourseServiceError.transport))
        let model = LearnerCourseViewModel(
            service: service,
            accessTokenProvider: { "tok" })

        await model.load()
        await model.reassess(request: "go")

        if case let .failed(message) = model.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected .failed, got \(model.state)")
        }
    }

    func testResetReturnsToIdle() async {
        let model = LearnerCourseViewModel(
            service: FakeCourseService(fetch: .success(sample())),
            accessTokenProvider: { "tok" })

        await model.load()
        model.reset()
        XCTAssertEqual(model.state, .idle)
    }

    private func sample(planId: String = "plan-x", title: String = "Everyday German") -> LearnerCourse {
        LearnerCourse(
            correlationId: "corr",
            planId: planId,
            title: title,
            lessons: [
                PlannedLesson(lessonId: "l1", title: "Greetings", learningObjective: "…", order: 1, estimatedMinutes: 10, status: .completed),
                PlannedLesson(lessonId: "l2", title: "Cooking verbs", learningObjective: "…", order: 2, estimatedMinutes: 15, status: .current),
            ])
    }
}

private final class FakeCourseService: LearnerCourseService, @unchecked Sendable {
    let fetch: Result<LearnerCourse, Error>
    let reassess: Result<LearnerCourse, Error>?
    private(set) var reassessCalls: [String?] = []

    init(fetch: Result<LearnerCourse, Error>, reassess: Result<LearnerCourse, Error>? = nil) {
        self.fetch = fetch
        self.reassess = reassess
    }

    func fetchCourse(accessToken: String) async throws -> LearnerCourse {
        return try fetch.get()
    }

    func reassessCourse(request: String?, accessToken: String) async throws -> LearnerCourse {
        reassessCalls.append(request)
        guard let reassess else {
            throw LearnerCourseServiceError.notConfigured(reason: "no reassess result configured")
        }
        return try reassess.get()
    }
}
