import XCTest
@testable import VoxaOnboarding

final class OnboardingLanguagesTests: XCTestCase {
    func testDisplayNamesAreAlphabetical() {
        XCTAssertEqual(OnboardingLanguages.displayNames, OnboardingLanguages.displayNames.sorted())
    }

    func testDisplayNamesContainSameSetAsSource() {
        XCTAssertEqual(Set(OnboardingLanguages.displayNames), Set(OnboardingLanguages.all))
    }
}

final class GoalSelectionTests: XCTestCase {
    func testDisplayTitleUsesPredefinedTitleOrRawCustom() {
        XCTAssertEqual(GoalSelection.displayTitle(for: "travel"), "Travel")
        XCTAssertEqual(GoalSelection.displayTitle(for: "Cook like a local"), "Cook like a local")
    }

    func testIsCustom() {
        XCTAssertFalse(GoalSelection.isCustom("work"))
        XCTAssertTrue(GoalSelection.isCustom("Order coffee"))
    }

    func testValidatedCustomGoalTrimsAndAccepts() {
        XCTAssertEqual(GoalSelection.validatedCustomGoal("  Order coffee  ", existing: []), .success("Order coffee"))
    }

    func testValidatedCustomGoalRejectsEmpty() {
        XCTAssertEqual(GoalSelection.validatedCustomGoal("   ", existing: []), .failure(.empty))
    }

    func testValidatedCustomGoalRejectsTooLong() {
        let long = String(repeating: "a", count: GoalSelection.maxCustomGoalLength + 1)
        XCTAssertEqual(GoalSelection.validatedCustomGoal(long, existing: []), .failure(.tooLong(max: GoalSelection.maxCustomGoalLength)))
    }

    func testValidatedCustomGoalRejectsDuplicateCaseInsensitive() {
        XCTAssertEqual(GoalSelection.validatedCustomGoal("order coffee", existing: ["Order coffee"]), .failure(.duplicate))
    }

    func testValidatedCustomGoalRejectsOverLimit() {
        let existing = (0..<GoalSelection.maxCustomGoals).map { "custom \($0)" }
        XCTAssertEqual(
            GoalSelection.validatedCustomGoal("one more", existing: existing),
            .failure(.limitReached(max: GoalSelection.maxCustomGoals))
        )
    }
}

@MainActor
final class OnboardingGoalSelectionViewModelTests: XCTestCase {
    func testTogglePredefinedGoalAddsAndRemovesAndPersists() throws {
        let store = InMemoryOnboardingDraftStore()
        let model = OnboardingViewModel(store: store)

        model.togglePredefinedGoal(.travel)
        model.togglePredefinedGoal(.work)
        XCTAssertEqual(model.selectedGoals, ["travel", "work"])
        XCTAssertTrue(model.isGoalSelected("travel"))
        XCTAssertEqual(try store.load()?.goals, ["travel", "work"])

        model.togglePredefinedGoal(.travel)
        XCTAssertEqual(model.selectedGoals, ["work"])
        XCTAssertEqual(try store.load()?.goals, ["work"])
    }

    func testAddCustomGoalPersistsAndValidates() throws {
        let store = InMemoryOnboardingDraftStore()
        let model = OnboardingViewModel(store: store)

        XCTAssertNil(model.addCustomGoal("  Order coffee "))
        XCTAssertEqual(model.selectedGoals, ["Order coffee"])
        XCTAssertEqual(try store.load()?.goals, ["Order coffee"])

        XCTAssertEqual(model.addCustomGoal("order coffee"), .duplicate)
        XCTAssertEqual(model.addCustomGoal(""), .empty)
        XCTAssertEqual(model.selectedGoals, ["Order coffee"])
    }

    func testRemoveGoal() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        model.togglePredefinedGoal(.travel)
        model.addCustomGoal("Order coffee")
        model.removeGoal("travel")
        XCTAssertEqual(model.selectedGoals, ["Order coffee"])
    }

    func testMakeProfileRequiresAtLeastOneGoal() {
        let draft = OnboardingDraft(
            targetLanguage: "French", nativeLanguage: "English",
            goals: [], minutesPerDay: 15, stepIndex: OnboardingStep.summary.rawValue
        )
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore(draft: draft))
        XCTAssertNil(model.makeProfile())
    }

    func testMakeProfileIncludesAllGoals() throws {
        let draft = OnboardingDraft(
            targetLanguage: "French", nativeLanguage: "English",
            goals: ["travel", "Order coffee"], minutesPerDay: 15,
            placementAnswers: [true, true, false, false, false],
            stepIndex: OnboardingStep.summary.rawValue
        )
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore(draft: draft))
        let profile = try XCTUnwrap(model.makeProfile())
        XCTAssertEqual(profile.goals, ["travel", "Order coffee"])
    }
}
