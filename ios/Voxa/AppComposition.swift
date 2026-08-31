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
        let onboardingModel = makeOnboardingModel(authModel: authModel)
        return RootView(
            authModel: authModel,
            onboardingModel: onboardingModel,
            talkModel: makeTalkModel(authModel: authModel, onboardingModel: onboardingModel)
        )
    }

    @MainActor
    static func makeAuthModel() -> AuthViewModel {
        AuthViewModel(store: KeychainSessionStore(), service: makeAuthService())
    }

    @MainActor
    static func makeOnboardingModel(authModel: AuthViewModel) -> OnboardingViewModel {
        // Start unscoped; RootView loads the user-specific draft after the
        // authenticated tenant/user is known.
        OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(),
            service: makeOnboardingService(authModel: authModel)
        )
    }

    /// Builds the onboarding service against the configured backend, or a
    /// clearly-failing fallback when the base URL is missing, so a
    /// misconfigured build fails loudly at submission rather than silently.
    @MainActor
    static func makeOnboardingService(authModel: AuthViewModel) -> any OnboardingService {
        guard let baseURL = backendBaseURL() else {
            return UnavailableOnboardingService()
        }
        return VoxaBackendOnboardingService(
            baseURL: baseURL,
            accessTokenProvider: { @MainActor in
                authModel.state.session?.accessToken
            }
        )
    }

    /// Builds the Talk-screen session model. Session settings are evaluated at
    /// `start()` time from the learner's onboarding state, so the Realtime
    /// request reflects their chosen language and level. The WebRTC media
    /// transport is a placeholder when the backend is not configured.
    @MainActor
    static func makeTalkModel(
        authModel: AuthViewModel,
        onboardingModel: OnboardingViewModel
    ) -> TalkSessionViewModel {
        TalkSessionViewModel(
            settingsProvider: { [weak onboardingModel] in
                realtimeSettings(from: onboardingModel)
            },
            permission: SystemMicrophonePermission(),
            service: makeRealtimeSessionService(),
            transport: makeRealtimeTransport(),
            accessTokenProvider: { [weak authModel] in authModel?.state.session?.accessToken }
        )
    }

    /// Creates the appropriate Realtime transport based on configuration.
    /// When VOXA_API_BASE_URL is configured, use real WebRTC transport.
    /// Otherwise, use placeholder that fails with clear message.
    static func makeRealtimeTransport() -> any RealtimeTransport {
        if backendBaseURL() == nil {
            return UnavailableRealtimeTransport(reason: "Voice sessions aren't configured for this build yet.")
        } else {
            return WebRTCRealtimeTransport()
        }
    }

    /// Derives Realtime coaching settings from the learner's onboarding state.
    @MainActor
    static func realtimeSettings(from onboardingModel: OnboardingViewModel?) -> RealtimeCoachingSettings {
        RealtimeCoachingSettings(
            proficiencyBand: proficiencyBand(for: onboardingModel?.placementEstimate),
            targetLanguage: languageCode(for: onboardingModel?.draft.targetLanguage)
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

    /// Maps an onboarding language display name to a BCP-47 tag. Defaults to
    /// French until the learner has chosen a language.
    static func languageCode(for displayName: String?) -> String {
        switch displayName {
        case "French": return "fr-FR"
        case "Spanish": return "es-ES"
        case "German": return "de-DE"
        case "Italian": return "it-IT"
        case "Japanese": return "ja-JP"
        case "English": return "en-US"
        case "Mandarin": return "zh-CN"
        case "Portuguese": return "pt-PT"
        default: return "fr-FR"
        }
    }

    /// Maps a CEFR estimate to a coaching proficiency band.
    static func proficiencyBand(for level: CEFRLevel?) -> String {
        switch level {
        case .a1, .a2, .none: return "A1-A2"
        case .b1, .b2: return "B1-B2"
        case .c1, .c2: return "C1-C2"
        }
    }
}
