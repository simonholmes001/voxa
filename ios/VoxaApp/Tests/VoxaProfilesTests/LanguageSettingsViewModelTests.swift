import XCTest
@testable import VoxaProfiles
import VoxaOnboarding
import VoxaRealtime

private final class FakeLanguageSettingsService: LanguageSettingsService, @unchecked Sendable {
    var result: Result<Int, Error>
    private(set) var calls: [(languageKey: String, profile: OnboardingProfile, expectedVersion: Int)] = []

    init(result: Result<Int, Error> = .success(2)) { self.result = result }

    func update(languageKey: String, profile: OnboardingProfile, expectedVersion: Int) async throws -> Int {
        calls.append((languageKey, profile, expectedVersion))
        return try result.get()
    }
}

private func sampleProfile() -> LanguageProfile {
    LanguageProfile(
        languageKey: "fr-FR", displayName: "French", isComplete: true,
        profile: OnboardingProfile(
            targetLanguage: "fr-FR", nativeLanguage: "en-US", goals: ["travel"],
            minutesPerDay: 15, placementLevel: .a1
        ),
        version: 3
    )
}

@MainActor
final class LanguageSettingsViewModelTests: XCTestCase {
    func testInitPopulatesEditableFields() {
        let store = InMemoryAiTutorPreferencesStore(values: [
            "fr-FR": AiTutorPreferences(voice: .cedar, tone: .calm, speed: 0.9)
        ])
        let model = LanguageSettingsViewModel(
            profile: sampleProfile(),
            service: FakeLanguageSettingsService(),
            aiTutorPreferencesStore: store)
        XCTAssertEqual(model.languageKey, "fr-FR")
        XCTAssertEqual(model.nativeLanguage, "en-US")
        XCTAssertEqual(model.goals, ["travel"])
        XCTAssertEqual(model.minutesPerDay, 15)
        XCTAssertEqual(model.placementLevel, .a1)
        XCTAssertEqual(model.aiTutorPreferences.voice, .cedar)
        XCTAssertEqual(model.aiTutorPreferences.tone, .calm)
        XCTAssertEqual(model.aiTutorPreferences.speed, 0.9)
        XCTAssertEqual(model.currentVersion, 3)
    }

    func testEditsAndSaveSendsUpdatedProfileWithVersion() async {
        let service = FakeLanguageSettingsService(result: .success(4))
        let store = InMemoryAiTutorPreferencesStore()
        let model = LanguageSettingsViewModel(
            profile: sampleProfile(),
            service: service,
            aiTutorPreferencesStore: store)

        model.togglePredefinedGoal(.work)          // -> ["travel","work"]
        XCTAssertNil(model.addCustomGoal("Order coffee"))
        model.setCustomMinutes("42")
        model.setPlacementLevel(.b1)
        model.nativeLanguage = "de-DE"
        model.aiTutorPreferences = AiTutorPreferences(voice: .ash, tone: .energetic, speed: 1.2)

        await model.save()

        XCTAssertEqual(model.state, .saved)
        XCTAssertEqual(model.currentVersion, 4)
        let call = service.calls.first
        XCTAssertEqual(call?.languageKey, "fr-FR")
        XCTAssertEqual(call?.expectedVersion, 3)
        XCTAssertEqual(call?.profile.nativeLanguage, "de-DE")
        XCTAssertEqual(call?.profile.goals, ["travel", "work", "Order coffee"])
        XCTAssertEqual(call?.profile.minutesPerDay, 42)
        XCTAssertEqual(call?.profile.placementLevel, .b1)
        XCTAssertEqual(call?.profile.targetLanguage, "fr-FR") // key unchanged
        XCTAssertEqual(store.preferences(for: "fr-FR").voice, .ash)
        XCTAssertEqual(store.preferences(for: "fr-FR").tone, .energetic)
        XCTAssertEqual(store.preferences(for: "fr-FR").speed, 1.2)
    }

    func testPreviewUsesUnsavedTutorPreferences() async {
        var previewed: RealtimeCoachingSettings?
        let model = LanguageSettingsViewModel(
            profile: sampleProfile(),
            service: FakeLanguageSettingsService(),
            previewer: { settings in previewed = settings })

        model.aiTutorPreferences = AiTutorPreferences(voice: .cedar, tone: .direct, speed: 0.85)

        await model.previewTutor()

        XCTAssertEqual(previewed?.sessionIntent, "voice_preview")
        XCTAssertEqual(previewed?.aiTutorPreferences.voice, .cedar)
        XCTAssertEqual(previewed?.aiTutorPreferences.tone, .direct)
        XCTAssertEqual(previewed?.aiTutorPreferences.speed, 0.85)
        XCTAssertEqual(model.previewState, .played)
    }

    func testVersionConflictSurfaces() async {
        let service = FakeLanguageSettingsService(result: .failure(LanguageProfilesError.versionConflict))
        let model = LanguageSettingsViewModel(profile: sampleProfile(), service: service)

        await model.save()

        XCTAssertEqual(model.state, .versionConflict)
    }

    func testSaveWithNoGoalsFailsWithoutCallingService() async {
        let service = FakeLanguageSettingsService()
        let model = LanguageSettingsViewModel(profile: sampleProfile(), service: service)
        model.removeGoal("travel")

        await model.save()

        guard case .failed = model.state else { return XCTFail("expected failed") }
        XCTAssertTrue(service.calls.isEmpty)
        XCTAssertFalse(model.canSave)
    }

    func testCustomGoalValidationIsEnforced() {
        let model = LanguageSettingsViewModel(profile: sampleProfile(), service: FakeLanguageSettingsService())
        XCTAssertEqual(model.addCustomGoal(""), .empty)
        XCTAssertEqual(model.addCustomGoal("travel"), .duplicate) // predefined already selected
    }
}
