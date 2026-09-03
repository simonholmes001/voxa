import XCTest
@testable import VoxaOnboarding

private final class FakeOnboardingService: OnboardingService, @unchecked Sendable {
    var result: Result<Void, Error>
    var resumeProfile: OnboardingProfile?
    private(set) var submitted: [OnboardingProfile] = []

    init(result: Result<Void, Error> = .success(()), resumeProfile: OnboardingProfile? = nil) {
        self.result = result
        self.resumeProfile = resumeProfile
    }

    func submit(_ profile: OnboardingProfile) async throws {
        submitted.append(profile)
        try result.get()
    }

    func resume() async throws -> OnboardingProfile? {
        return resumeProfile
    }
}

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private func completeDraft() -> OnboardingDraft {
        OnboardingDraft(
            targetLanguage: "French",
            nativeLanguage: "English",
            goals: ["travel"],
            minutesPerDay: 15,
            placementAnswers: [true, true, false, false, false],
            stepIndex: OnboardingStep.summary.rawValue
        )
    }

    func testStartsAtWelcomeStep() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        XCTAssertEqual(model.currentStep, .welcome)
        XCTAssertFalse(model.isComplete)
    }

    func testAdvanceAndBackNavigateStepsAndPersist() throws {
        let store = InMemoryOnboardingDraftStore()
        let model = OnboardingViewModel(store: store)

        model.advance()
        XCTAssertEqual(model.currentStep, .targetLanguage)
        XCTAssertEqual(try store.load()?.stepIndex, OnboardingStep.targetLanguage.rawValue)

        model.goBack()
        XCTAssertEqual(model.currentStep, .welcome)
        XCTAssertEqual(try store.load()?.stepIndex, OnboardingStep.welcome.rawValue)
    }

    func testGoBackDoesNotUnderflow() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        model.goBack()
        XCTAssertEqual(model.currentStep, .welcome)
    }

    func testSettersPersistAnswers() throws {
        let store = InMemoryOnboardingDraftStore()
        let model = OnboardingViewModel(store: store)

        model.setTargetLanguage("Japanese")
        model.setMinutesPerDay(30)

        let saved = try XCTUnwrap(try store.load())
        XCTAssertEqual(saved.targetLanguage, "Japanese")
        XCTAssertEqual(saved.minutesPerDay, 30)
    }

    func testResumeLoadsPersistedDraft() {
        let store = InMemoryOnboardingDraftStore(draft: completeDraft())
        let model = OnboardingViewModel(store: store)
        XCTAssertEqual(model.currentStep, .summary)
        XCTAssertEqual(model.draft.targetLanguage, "French")
    }

    func testAnswerPlacementUpdatesEstimate() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        model.answerPlacement(0, true)
        model.answerPlacement(1, true)
        XCTAssertEqual(model.placementEstimate, .a2)
    }

    func testFinishWithIncompleteProfileFailsWithoutSubmitting() async {
        let service = FakeOnboardingService()
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore(), service: service)

        await model.finish()

        XCTAssertEqual(model.phase, .failed("Please complete every step before continuing."))
        XCTAssertTrue(service.submitted.isEmpty)
        XCTAssertFalse(model.isComplete)
    }

    func testFinishWithCompleteProfileSubmitsAndCompletes() async throws {
        let store = InMemoryOnboardingDraftStore(draft: completeDraft())
        let service = FakeOnboardingService(result: .success(()))
        let model = OnboardingViewModel(store: store, service: service)

        await model.finish()

        XCTAssertEqual(model.phase, .completed)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(service.submitted.count, 1)
        XCTAssertEqual(service.submitted.first?.placementLevel, .a2)
        XCTAssertEqual(try store.load()?.isCompleted, true)
    }

    func testFinishWithServiceFailureSetsFailed() async throws {
        let store = InMemoryOnboardingDraftStore(draft: completeDraft())
        let service = FakeOnboardingService(result: .failure(OnboardingServiceError.unavailable))
        let model = OnboardingViewModel(store: store, service: service)

        await model.finish()

        guard case .failed = model.phase else {
            return XCTFail("expected .failed, got \(model.phase)")
        }
        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(try store.load()?.isCompleted, false)
    }

    func testCompletedDraftResumesAsComplete() {
        var draft = completeDraft()
        draft.isCompleted = true
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore(draft: draft))
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.phase, .completed)
    }

    func testResetForFirstRunReviewClearsCompletedDraft() throws {
        var draft = completeDraft()
        draft.isCompleted = true
        let store = InMemoryOnboardingDraftStore(draft: draft)
        let model = OnboardingViewModel(store: store)

        model.resetForFirstRunReview()

        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.currentStep, .welcome)
        XCTAssertEqual(model.phase, .inProgress)
        XCTAssertNil(try store.load())
    }

    func testChangingAuthenticatedUserLoadsThatUsersOnboardingDraft() throws {
        var completed = completeDraft()
        completed.isCompleted = true
        let userAStore = InMemoryOnboardingDraftStore(draft: completed)
        let userBStore = InMemoryOnboardingDraftStore()
        let model = OnboardingViewModel(
            store: userAStore,
            scopedStoreFactory: { _, userId in
                userId == "user-a" ? userAStore : userBStore
            }
        )

        model.scope(toTenantId: "tenant", userId: "user-a")
        XCTAssertTrue(model.isComplete)

        model.scope(toTenantId: "tenant", userId: "user-b")

        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.currentStep, .welcome)
        XCTAssertNil(try userBStore.load())
    }

    func testBackendResumePersistsPlacementLevelInScopedDraft() async throws {
        let store = InMemoryOnboardingDraftStore()
        let service = FakeOnboardingService(
            resumeProfile: OnboardingProfile(
                targetLanguage: "Spanish",
                nativeLanguage: "English",
                goals: ["work"],
                minutesPerDay: 30,
                placementLevel: .c2
            )
        )
        let model = OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(),
            service: service,
            scopedStoreFactory: { _, _ in store }
        )

        model.scope(toTenantId: "tenant", userId: "user-a")
        for _ in 0..<10 where model.phase != .completed {
            await Task.yield()
        }

        let saved = try XCTUnwrap(try store.load())
        XCTAssertEqual(saved.placementLevel, .c2)
        XCTAssertEqual(model.placementEstimate, .c2)
        XCTAssertEqual(model.phase, .completed)
    }

    func testFinishCompletesLocallyWithDefaultLocalService() async {
        let model = OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(draft: completeDraft()),
            service: LocalOnboardingService()
        )

        await model.finish()

        XCTAssertEqual(model.phase, .completed)
        XCTAssertTrue(model.isComplete)
    }
}
