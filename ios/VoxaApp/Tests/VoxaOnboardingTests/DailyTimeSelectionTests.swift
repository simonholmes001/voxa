import XCTest
@testable import VoxaOnboarding

final class DailyTimeSelectionTests: XCTestCase {
    func testValidateAcceptsAndTrims() {
        XCTAssertEqual(DailyTimeSelection.validate("  25 "), .success(25))
        XCTAssertEqual(DailyTimeSelection.validate(String(DailyTimeSelection.minMinutes)), .success(DailyTimeSelection.minMinutes))
        XCTAssertEqual(DailyTimeSelection.validate(String(DailyTimeSelection.maxMinutes)), .success(DailyTimeSelection.maxMinutes))
    }

    func testValidateRejectsEmpty() {
        XCTAssertEqual(DailyTimeSelection.validate("   "), .failure(.empty))
    }

    func testValidateRejectsNonNumber() {
        XCTAssertEqual(DailyTimeSelection.validate("20m"), .failure(.notANumber))
        XCTAssertEqual(DailyTimeSelection.validate("12.5"), .failure(.notANumber))
    }

    func testValidateRejectsOutOfRange() {
        let expected = DailyTimeSelection.DailyTimeError.outOfRange(
            min: DailyTimeSelection.minMinutes, max: DailyTimeSelection.maxMinutes
        )
        XCTAssertEqual(DailyTimeSelection.validate(String(DailyTimeSelection.minMinutes - 1)), .failure(expected))
        XCTAssertEqual(DailyTimeSelection.validate(String(DailyTimeSelection.maxMinutes + 1)), .failure(expected))
    }

    func testIsPreset() {
        XCTAssertTrue(DailyTimeSelection.isPreset(15))
        XCTAssertFalse(DailyTimeSelection.isPreset(42))
        XCTAssertFalse(DailyTimeSelection.isPreset(nil))
    }
}

private final class SubmitCapturingOnboardingService: OnboardingService, @unchecked Sendable {
    private(set) var submitted: [OnboardingProfile] = []
    func submit(_ profile: OnboardingProfile) async throws { submitted.append(profile) }
    func resume() async throws -> OnboardingProfile? { nil }
}

@MainActor
final class OnboardingCustomTimeViewModelTests: XCTestCase {
    // Continue is enabled for the time step iff draft.minutesPerDay != nil
    // (mirrors OnboardingView.canAdvance for .time).
    private func continueEnabled(_ model: OnboardingViewModel) -> Bool {
        model.draft.minutesPerDay != nil
    }

    func testPresetSelectionPersistsAndLeavesCustomMode() throws {
        let store = InMemoryOnboardingDraftStore()
        let model = OnboardingViewModel(store: store)

        model.setMinutesPerDay(15)

        XCTAssertEqual(model.draft.minutesPerDay, 15)
        XCTAssertFalse(model.isCustomTimeMode)
        XCTAssertEqual(try store.load()?.minutesPerDay, 15)
    }

    // 1) preset -> Custom -> no input -> Continue disabled.
    func testPresetThenCustomWithNoInputDisablesContinue() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        model.setMinutesPerDay(15)

        model.enterCustomTimeMode()

        XCTAssertTrue(model.isCustomTimeMode)
        XCTAssertEqual(model.customTimeText, "")
        XCTAssertNil(model.draft.minutesPerDay)
        XCTAssertFalse(continueEnabled(model))
    }

    // 2) preset -> Custom -> invalid input -> Continue disabled.
    func testPresetThenCustomInvalidInputDisablesContinue() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        model.setMinutesPerDay(15)
        model.enterCustomTimeMode()

        model.updateCustomTime("abc")
        XCTAssertNil(model.draft.minutesPerDay)
        XCTAssertEqual(model.customTimeError, .notANumber)
        XCTAssertFalse(continueEnabled(model))

        model.updateCustomTime("500")
        XCTAssertNil(model.draft.minutesPerDay)
        XCTAssertEqual(model.customTimeError, .outOfRange(min: DailyTimeSelection.minMinutes, max: DailyTimeSelection.maxMinutes))
        XCTAssertFalse(continueEnabled(model))
    }

    // 3) preset -> Custom -> valid 42 -> Continue enabled and 42 submitted.
    func testPresetThenCustomValidEnablesContinueAndSubmitsValue() async throws {
        let service = SubmitCapturingOnboardingService()
        let draft = OnboardingDraft(
            targetLanguage: "French",
            nativeLanguage: "English",
            goals: ["travel"],
            minutesPerDay: 15,
            placementAnswers: [true, false, false, false, false],
            stepIndex: OnboardingStep.summary.rawValue
        )
        let store = InMemoryOnboardingDraftStore(draft: draft)
        let model = OnboardingViewModel(store: store, service: service)

        model.enterCustomTimeMode()
        model.updateCustomTime("42")

        XCTAssertEqual(model.draft.minutesPerDay, 42)
        XCTAssertNil(model.customTimeError)
        XCTAssertTrue(continueEnabled(model))
        XCTAssertEqual(try store.load()?.minutesPerDay, 42)

        await model.finish()
        XCTAssertEqual(service.submitted.first?.minutesPerDay, 42)
    }

    // 4) persisted custom 42 -> time step displays 42.
    func testPersistedCustomValuePopulatesField() {
        let store = InMemoryOnboardingDraftStore(
            draft: OnboardingDraft(minutesPerDay: 42, stepIndex: OnboardingStep.time.rawValue)
        )
        let model = OnboardingViewModel(store: store)

        XCTAssertTrue(model.isCustomTimeMode)
        XCTAssertEqual(model.customTimeText, "42")
        XCTAssertTrue(continueEnabled(model))
    }

    func testSelectingPresetAfterCustomResetsMode() {
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        model.enterCustomTimeMode()
        model.updateCustomTime("42")

        model.setMinutesPerDay(10)

        XCTAssertFalse(model.isCustomTimeMode)
        XCTAssertEqual(model.customTimeText, "")
        XCTAssertEqual(model.draft.minutesPerDay, 10)
    }
}
