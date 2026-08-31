import Foundation
import SwiftUI
import VoxaAppShell
import VoxaAuth
import VoxaNetworking
import VoxaOnboarding
import VoxaRealtime

/// Composition root for the Voxa app target.
///
/// Wires the app-level dependencies (auth service, session store, onboarding,
/// Talk-screen Realtime) and hands the assembled `RootView` to the `@main`
/// entry point. Keeping this here means the `App` struct stays trivial and the
/// wiring is testable.
enum AppComposition {
    @MainActor
    static func makeRootView() -> RootView {
        let authModel = makeAuthModel()
        return RootView(
            authModel: authModel,
            onboardingModel: makeOnboardingModel(),
            talkModel: makeTalkModel(authModel: authModel)
        )
    }

    @MainActor
    static func makeAuthModel() -> AuthViewModel {
        AuthViewModel(store: KeychainSessionStore(), service: makeAuthService())
    }

    @MainActor
    static func makeOnboardingModel() -> OnboardingViewModel {
        // Start unscoped; RootView loads the user-specific draft after the
        // authenticated tenant/user is known.
        OnboardingViewModel(store: InMemoryOnboardingDraftStore())
    }

    /// Builds the Talk-screen session model. The Realtime session credential is
    /// fetched from the backend using the current app-session access token; the
    /// WebRTC media transport is a placeholder until libwebrtc is integrated.
    ///
    /// TODO: Settings are hard-coded until onboarding/profile integration (#59, #20).
    /// When integrated, inject: targetLanguage from profile.targetLanguage,
    /// proficiencyBand from profile.proficiencyLevel (mapped to CEFR bands).
    ///
    /// TODO: Transport is UnavailableRealtimeTransport until WebRTC is integrated.
    /// The UI and backend client-secret call are fully wired, but live audio
    /// will fail with .unavailable until a real transport is injected.
    @MainActor
    static func makeTalkModel(authModel: AuthViewModel) -> TalkSessionViewModel {
        TalkSessionViewModel(
            settings: RealtimeCoachingSettings(
                proficiencyBand: "A1-A2",  // TODO: derive from profile.proficiencyLevel
                targetLanguage: "fr-FR"    // TODO: derive from profile.targetLanguage
            ),
            permission: SystemMicrophonePermission(),
            service: makeRealtimeSessionService(),
            transport: UnavailableRealtimeTransport(
                reason: "WebRTC transport integration pending. See TalkSessionViewModel docs."
            ),
            accessTokenProvider: { [weak authModel] in authModel?.state.session?.accessToken }
        )
    }

    /// Builds the auth service against the configured backend, or a
    /// clearly-failing fallback when the base URL is missing, so a
    /// misconfigured build fails loudly at sign-in rather than silently.
    static func makeAuthService() -> any AuthenticationService {
        guard let baseURL = backendBaseURL() else {
            return NotConfiguredAuthenticationService()
        }
        return VoxaBackendAuthenticationService(baseURL: baseURL)
    }

    /// Builds the Realtime session service, or a clearly-failing fallback when
    /// the base URL is missing.
    static func makeRealtimeSessionService() -> any RealtimeSessionService {
        guard let baseURL = backendBaseURL() else {
            return NotConfiguredRealtimeSessionService()
        }
        return VoxaBackendRealtimeSessionService(baseURL: baseURL)
    }

    /// Resolves the backend base URL from the app's Info.plist
    /// (`VOXA_API_BASE_URL`). Returns `nil` when unset or blank.
    static func backendBaseURL(bundle: Bundle = .main) -> URL? {
        resolveBaseURL(bundle.object(forInfoDictionaryKey: "VOXA_API_BASE_URL") as? String)
    }

    /// Pure helper: trims and validates a base-URL string, returning `nil` for
    /// missing/blank values.
    static func resolveBaseURL(_ raw: String?) -> URL? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return URL(string: trimmed)
    }
}
