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
            goals: ["travel"],
            minutesPerDay: 15,
            placementLevel: .b1
        )

        let summary = AppComposition.learnerSummary(from: profile)

        XCTAssertEqual(summary, LearnerProfileSummary(
            languageName: "French",
            levelName: "B1",
            goalName: "Travel",
            dailyMinutes: 15,
            isStale: false
        ))
    }

    func testMapsLocalFallbackProfileToStaleSummary() {
        let profile = OnboardingProfile(
            targetLanguage: "French",
            nativeLanguage: "English",
            goals: ["travel"],
            minutesPerDay: 15,
            placementLevel: .b1
        )

        let summary = AppComposition.learnerSummary(from: profile, isStale: true)

        XCTAssertEqual(summary?.isStale, true)
    }

    func testNilProfileMapsToNil() {
        XCTAssertNil(AppComposition.learnerSummary(from: nil))
    }

    func testHomeProfileFallbackAllowsTemporaryBackendFailures() {
        XCTAssertTrue(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.transportUnavailable))
        XCTAssertTrue(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.serverUnavailable))
        XCTAssertFalse(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.authenticationRequired))
        XCTAssertFalse(AppComposition.isHomeProfileFallbackEligible(OnboardingServiceError.invalidResponse))
    }

    func testHomeProfileAuthenticationFailureOnlyAllowsAuthRequired() {
        XCTAssertTrue(AppComposition.isHomeProfileAuthenticationFailure(OnboardingServiceError.authenticationRequired))
        XCTAssertFalse(AppComposition.isHomeProfileAuthenticationFailure(OnboardingServiceError.transportUnavailable))
        XCTAssertFalse(AppComposition.isHomeProfileAuthenticationFailure(OnboardingServiceError.serverUnavailable))
        XCTAssertFalse(AppComposition.isHomeProfileAuthenticationFailure(OnboardingServiceError.invalidResponse))
    }
}
