import XCTest
@testable import Voxa
import VoxaOnboarding
import VoxaRealtime

/// Verifies the onboarding-state -> Realtime settings mapping used to build the
/// Talk session request, so device testing reflects the learner's choices.
final class RealtimeSettingsMappingTests: XCTestCase {
    func testCanonicalLanguageKeyMapping() {
        XCTAssertEqual(AppComposition.canonicalLanguageKey(for: "Japanese"), "ja-JP")
        XCTAssertEqual(AppComposition.canonicalLanguageKey(for: "Spanish"), "es-ES")
        XCTAssertEqual(AppComposition.canonicalLanguageKey(for: "es-ES"), "es-ES") // passthrough for keys
        XCTAssertEqual(AppComposition.canonicalLanguageKey(for: nil), "fr-FR")
    }

    func testProficiencyBandMapping() {
        XCTAssertEqual(AppComposition.proficiencyBand(for: .a1), "A1-A2")
        XCTAssertEqual(AppComposition.proficiencyBand(for: .b2), "B1-B2")
        XCTAssertEqual(AppComposition.proficiencyBand(for: .c1), "C1-C2")
        XCTAssertEqual(AppComposition.proficiencyBand(for: nil), "A1-A2")
    }

    @MainActor
    func testSettingsReflectOnboardingDraft() {
        let draft = OnboardingDraft(
            targetLanguage: "Spanish",
            placementAnswers: [true, true, true, false, false] // ladder -> B1
        )
        let model = OnboardingViewModel(store: InMemoryOnboardingDraftStore(draft: draft))

        let settings = AppComposition.realtimeSettings(from: model)

        XCTAssertEqual(settings.targetLanguage, "es-ES")
        XCTAssertEqual(settings.proficiencyBand, "B1-B2")
    }
}
