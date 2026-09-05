import XCTest
@testable import Voxa
import VoxaOnboarding

/// Smoke tests for the Voxa app target.
///
/// These run in a unit-test bundle hosted by the Voxa app, so `Bundle.main`
/// resolves to the app bundle under test. They verify that the app target
/// hosts the shell's `RootView` and ships the privacy usage strings the
/// realtime voice tutor will require.
final class AppCompositionTests: XCTestCase {
    @MainActor
    func testCompositionRootBuildsRootView() {
        // The composition root must return the shell's adaptive root view.
        _ = AppComposition.makeRootView()
    }

    func testResolveBaseURLRejectsMissingAndBlankValues() {
        XCTAssertNil(AppComposition.resolveBaseURL(nil))
        XCTAssertNil(AppComposition.resolveBaseURL(""))
        XCTAssertNil(AppComposition.resolveBaseURL("   "))
    }

    func testResolveBaseURLAcceptsValidURL() {
        XCTAssertEqual(
            AppComposition.resolveBaseURL("  https://api.voxa.example  "),
            URL(string: "https://api.voxa.example")
        )
    }

    func testDefaultBuildHasNoBackendBaseURLConfigured() {
        // The default (unconfigured) build must resolve to nil so network calls
        // fail clearly rather than hitting an unintended host.
        XCTAssertNil(AppComposition.backendBaseURL())
    }

    @MainActor
    func testRealtimeSettingsReflectHydratedSelectedLanguageProfile() {
        let onboardingModel = OnboardingViewModel(store: InMemoryOnboardingDraftStore())
        onboardingModel.hydrate(
            from: OnboardingProfile(
                targetLanguage: "es-ES",
                nativeLanguage: "fr-FR",
                goals: ["work"],
                minutesPerDay: 30,
                placementLevel: .c2),
            completed: true)

        let settings = AppComposition.realtimeSettings(from: onboardingModel)

        XCTAssertEqual(settings.targetLanguage, "es-ES")
        XCTAssertEqual(settings.proficiencyBand, "C1-C2")
    }

    func testInfoPlistDeclaresMicrophoneUsage() {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) as? String
        XCTAssertNotNil(value)
        XCTAssertFalse(value?.isEmpty ?? true)
    }

    func testInfoPlistDeclaresSpeechRecognitionUsage() {
        let value = Bundle.main.object(
            forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"
        ) as? String
        XCTAssertNotNil(value)
        XCTAssertFalse(value?.isEmpty ?? true)
    }

    func testSupportsIPhoneAndIPadDeviceFamilies() {
        // UIDeviceFamily 1 == iPhone, 2 == iPad. Xcode injects this from
        // TARGETED_DEVICE_FAMILY at build time.
        let families = Bundle.main.object(
            forInfoDictionaryKey: "UIDeviceFamily"
        ) as? [Int]
        XCTAssertEqual(families, [1, 2])
    }
}
