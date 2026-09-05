import XCTest
@testable import VoxaProfiles
import VoxaOnboarding

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
        let model = LanguageSettingsViewModel(profile: sampleProfile(), service: FakeLanguageSettingsService())
        XCTAssertEqual(model.languageKey, "fr-FR")
        XCTAssertEqual(model.nativeLanguage, "en-US")
        XCTAssertEqual(model.goals, ["travel"])
        XCTAssertEqual(model.minutesPerDay, 15)
        XCTAssertEqual(model.placementLevel, .a1)
        XCTAssertEqual(model.currentVersion, 3)
    }

    func testEditsAndSaveSendsUpdatedProfileWithVersion() async {
        let service = FakeLanguageSettingsService(result: .success(4))
        let model = LanguageSettingsViewModel(profile: sampleProfile(), service: service)

        model.togglePredefinedGoal(.work)          // -> ["travel","work"]
        XCTAssertNil(model.addCustomGoal("Order coffee"))
        model.setCustomMinutes("42")
        model.setPlacementLevel(.b1)
        model.nativeLanguage = "de-DE"

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
