import XCTest
@testable import Voxa
import VoxaAuth
import VoxaOnboarding

private final class StubAuthenticationService: AuthenticationService, @unchecked Sendable {
    let session: AuthSession
    init(session: AuthSession) { self.session = session }
    func exchange(_ proof: AppleIdentityProof) async throws -> AuthSession { session }
    func refresh(_ session: AuthSession) async throws -> AuthSession { session }
    func invalidate(_ session: AuthSession) async throws {}
}

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

    /// Regression guard for the post-sign-in "no access token" device bug.
    ///
    /// Every authenticated backend service must read its token from the live,
    /// shared `AuthViewModel` behind the auth gate. Before sign-in the provider
    /// yields `nil`; after the same model signs in, it must yield that session's
    /// access token. If a service is ever wired to a different `AuthViewModel`
    /// (as happened when `makeRootView()` was re-invoked per SwiftUI render and
    /// rewired `RootView`'s non-`@State` child models to a fresh signed-out
    /// model), this invariant breaks and every request loses its token.
    @MainActor
    func testAccessTokenProviderReflectsSharedAuthModelSignIn() async {
        let session = AuthSession(
            accessToken: "access-123",
            refreshToken: "refresh-123",
            expiresAt: Date().addingTimeInterval(3600),
            refreshTokenExpiresAt: Date().addingTimeInterval(7200),
            userId: "user-1",
            tenantId: "tenant-1")
        let authModel = AuthViewModel(
            store: EphemeralSessionStore(),
            service: StubAuthenticationService(session: session))
        let provider = AppComposition.accessTokenProvider(for: authModel)

        let tokenBeforeSignIn = await provider()
        XCTAssertNil(tokenBeforeSignIn, "Signed-out model must not expose a token")

        await authModel.signIn(with: AppleIdentityProof(
            identityToken: Data("id".utf8),
            authorizationCode: Data("code".utf8),
            nonce: "nonce",
            userID: "user-1"))

        let tokenAfterSignIn = await provider()
        XCTAssertEqual(
            tokenAfterSignIn,
            "access-123",
            "Provider must read the token from the same model the auth gate signed in")
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
