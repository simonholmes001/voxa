import XCTest
@testable import Voxa
import VoxaHome
import VoxaOnboarding

/// Verifies the onboarding-profile -> Home summary mapping used by the Home
/// surface, so the post-onboarding screen reflects the learner's choices.
final class HomeProfileMappingTests: XCTestCase {
    func testMapsOnboardingProfileToSummary() {
        let profile = OnboardingProfile(
            targetLanguage: "French",
            nativeLanguage: "English",
            goal: .travel,
            minutesPerDay: 15,
            placementLevel: .b1
        )

        let summary = AppComposition.learnerSummary(from: profile)

        XCTAssertEqual(summary, LearnerProfileSummary(
            languageName: "French",
            levelName: "B1",
            goalName: "Travel",
            dailyMinutes: 15
        ))
    }

    func testNilProfileMapsToNil() {
        XCTAssertNil(AppComposition.learnerSummary(from: nil))
    }

    func testHomeProfileFallbackOnlyAllowsTransportUnavailable() {
        XCTAssertTrue(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.transportUnavailable))
        XCTAssertFalse(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.authenticationRequired))
        XCTAssertFalse(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.invalidResponse))
        XCTAssertFalse(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.serverUnavailable))
    }
}
