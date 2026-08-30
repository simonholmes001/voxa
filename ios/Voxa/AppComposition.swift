import Foundation
import SwiftUI
import VoxaAppShell
import VoxaAuth
import VoxaNetworking
import VoxaOnboarding

/// Composition root for the Voxa app target.
///
/// Wires the app-level dependencies (auth service, session store, onboarding)
/// and hands the assembled `RootView` to the `@main` entry point. Keeping this
/// here means the `App` struct stays trivial and the wiring is testable.
enum AppComposition {
    @MainActor
    static func makeRootView() -> RootView {
        RootView(authModel: makeAuthModel(), onboardingModel: makeOnboardingModel())
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

    /// Builds the auth service against the configured backend, or a
    /// clearly-failing fallback when the base URL is missing, so a
    /// misconfigured build fails loudly at sign-in rather than silently.
    static func makeAuthService() -> any AuthenticationService {
        guard let baseURL = backendBaseURL() else {
            return NotConfiguredAuthenticationService()
        }
        return VoxaBackendAuthenticationService(baseURL: baseURL)
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
