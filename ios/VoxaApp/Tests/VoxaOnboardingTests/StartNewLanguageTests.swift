import XCTest
@testable import VoxaOnboarding

@MainActor
final class StartNewLanguageTests: XCTestCase {
    func testStartNewLanguageResetsDraftForFreshOnboarding() {
        // A completed profile for one language...
        let store = InMemoryOnboardingDraftStore(
            draft: OnboardingDraft(
                targetLanguage: "fr-FR", nativeLanguage: "en-US",
                goals: ["travel"], minutesPerDay: 15,
                stepIndex: OnboardingStep.summary.rawValue, isCompleted: true
            )
        )
        let model = OnboardingViewModel(store: store)
        XCTAssertTrue(model.isComplete)

        model.startNewLanguageOnboarding()

        // ...becomes a fresh, incomplete onboarding for the next language.
        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.currentStep, .welcome)
        XCTAssertNil(model.draft.targetLanguage)
        XCTAssertTrue(model.draft.goals.isEmpty)
        XCTAssertNil(model.draft.minutesPerDay)
    }
}
