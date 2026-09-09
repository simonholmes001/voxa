import Foundation
import SwiftUI
import VoxaAppShell
import VoxaAuth
import VoxaHome
import VoxaNetworking
import VoxaOnboarding
import VoxaProfiles
import VoxaRealtime
import VoxaRealtimeWebRTC

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
        let onboardingService = makeOnboardingService(authModel: authModel)
        let onboardingModel = makeOnboardingModel(service: onboardingService)
        let languageSettingsService = makeLanguageSettingsService(authModel: authModel)
        let homeModel = makeHomeModel(
            authModel: authModel,
            onboardingService: onboardingService,
            onboardingModel: onboardingModel
        )
        let profileModel = makeProfileModel(authModel: authModel)
        return RootView(
            authModel: authModel,
            onboardingModel: onboardingModel,
            homeModel: homeModel,
            talkModel: makeTalkModel(
                authModel: authModel,
                onboardingModel: onboardingModel,
                onSessionCompleted: {
                    await homeModel.resumeIfAvailable()
                    await profileModel.refresh()
                }
            ),
            profileModel: profileModel,
            makeLanguageSettingsModel: { profile in
                LanguageSettingsViewModel(profile: profile, service: languageSettingsService)
            }
        )
    }

    @MainActor
    static func makeProfileModel(authModel: AuthViewModel) -> ProfileSelectionViewModel {
        ProfileSelectionViewModel(service: makeLanguageProfilesService(authModel: authModel))
    }

    /// The single source of truth for the app-session access token used by every
    /// authenticated backend service. Every service must read its token from the
    /// *same* `AuthViewModel` instance the auth gate signs in; if a service is
    /// wired to a different (or freshly re-created, signed-out) `AuthViewModel`,
    /// its requests silently lose the token and the backend answers 401. Routing
    /// all services through this helper keeps that wiring in one place.
    static func accessTokenProvider(
        for authModel: AuthViewModel
    ) -> @MainActor @Sendable () -> String? {
        { @MainActor in authModel.state.session?.accessToken }
    }

    @MainActor
    static func makeLanguageProfilesService(authModel: AuthViewModel) -> any LanguageProfilesService {
        guard let baseURL = backendBaseURL() else {
            return NotConfiguredLanguageProfilesService()
        }
        return VoxaBackendLanguageProfilesService(
            baseURL: baseURL,
            accessTokenProvider: accessTokenProvider(for: authModel)
        )
    }

    /// Builds the per-language settings service (#84) for the More/Settings
    /// surface to save edits to the active language profile.
    @MainActor
    static func makeLanguageSettingsService(authModel: AuthViewModel) -> any LanguageSettingsService {
        guard let baseURL = backendBaseURL() else {
            return NotConfiguredLanguageSettingsService()
        }
        return VoxaBackendLanguageSettingsService(
            baseURL: baseURL,
            accessTokenProvider: accessTokenProvider(for: authModel)
        )
    }

    @MainActor
    static func makeAuthModel() -> AuthViewModel {
        AuthViewModel(store: KeychainSessionStore(), service: makeAuthService())
    }

    @MainActor
    static func makeOnboardingModel(service: any OnboardingService) -> OnboardingViewModel {
        // Start unscoped; RootView loads the user-specific draft after the
        // authenticated tenant/user is known.
        OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(),
            service: service
        )
    }

    /// Builds the Home/Today model. The learner profile comes from server
    /// learner state (`resume()`), falling back to the locally captured
    /// onboarding profile when the server is unreachable (offline).
    @MainActor
    static func makeHomeModel(
        authModel: AuthViewModel,
        onboardingService: any OnboardingService,
        onboardingModel: OnboardingViewModel
    ) -> HomeViewModel {
        let server = MainActorProfileProvider {
            learnerSummary(from: try await onboardingService.resumeCheckpoint())
        }
        let local = MainActorProfileProvider { [weak onboardingModel] in
            learnerSummary(from: onboardingModel?.makeProfile(), isStale: true)
        }
        let resumer = OnboardingResumerAdapter(service: onboardingService)
        return HomeViewModel(provider: FallbackProfileProvider(
            primary: server,
            fallback: local,
            shouldFallback: { error in isHomeProfileFallbackEligible(error) }
        ), resumer: resumer, messageForError: homeProfileErrorMessage,
        isFallbackEligible: isHomeProfileFallbackEligible,
        isAuthenticationFailure: isHomeProfileAuthenticationFailure,
        onAuthenticationFailure: { [weak authModel] in
            await authModel?.signOut()
        })
    }

    /// Maps an onboarding profile into the display-ready Home summary.
    static func learnerSummary(
        from profile: OnboardingProfile?,
        isStale: Bool = false,
        activePlanTitle: String? = nil,
        currentLessonTitle: String? = nil,
        currentLessonStepIndex: Int? = nil,
        dueReviewCount: Int = 0,
        recentSessionCount: Int = 0,
        minutesPracticedToday: Int = 0
    ) -> LearnerProfileSummary? {
        guard let profile else { return nil }
        return LearnerProfileSummary(
            languageName: OnboardingLanguages.displayName(forKey: profile.targetLanguage),
            levelName: profile.placementLevel.displayName,
            goalName: profile.goals.map(GoalSelection.displayTitle).joined(separator: ", "),
            dailyMinutes: profile.minutesPerDay,
            isStale: isStale,
            activePlanTitle: activePlanTitle,
            currentLessonTitle: currentLessonTitle,
            currentLessonStepIndex: currentLessonStepIndex,
            dueReviewCount: dueReviewCount,
            recentSessionCount: recentSessionCount,
            minutesPracticedToday: minutesPracticedToday
        )
    }

    /// Adapter that exposes OnboardingService.resume() as a LearnerProfileResuming
    /// implementation for composition. Keeping this here avoids adding another
    /// small source file in the worktree and keeps the adapter implementation
    /// local to composition.
    private struct OnboardingResumerAdapter: LearnerProfileResuming {
        let service: any OnboardingService

        func resumeSession() async throws -> LearnerProfileSummary? {
            let checkpoint = try await service.resumeCheckpoint()
            return AppComposition.learnerSummary(from: checkpoint)
        }
    }

    /// Maps a resume checkpoint into the display-ready Home summary, preserving
    /// current plan/review context when the backend supplies it.
    static func learnerSummary(
        from checkpoint: OnboardingResumeCheckpoint?,
        isStale: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LearnerProfileSummary? {
        guard let checkpoint else { return nil }
        return learnerSummary(
            from: checkpoint.profile,
            isStale: isStale,
            activePlanTitle: checkpoint.activePlan?.title,
            currentLessonTitle: displayTitle(forKnowledgeUnitId: checkpoint.currentLesson?.knowledgeUnitId),
            currentLessonStepIndex: checkpoint.currentLesson?.stepIndex,
            dueReviewCount: checkpoint.reviewQueue.filter { $0.dueAt <= now }.count,
            recentSessionCount: checkpoint.recentSessions.count,
            minutesPracticedToday: minutesPracticedToday(
                from: checkpoint.recentSessions,
                now: now,
                calendar: calendar
            )
        )
    }

    static func minutesPracticedToday(
        from sessions: [SessionSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let seconds = sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .reduce(0) { total, session in total + max(0, session.durationSeconds) }
        return seconds / 60
    }

    static func displayTitle(forKnowledgeUnitId knowledgeUnitId: String?) -> String? {
        guard let knowledgeUnitId else { return nil }
        let words = knowledgeUnitId
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
        guard !words.isEmpty else { return nil }
        return words.map { word in
            let first = word.prefix(1).uppercased()
            let remainder = String(word.dropFirst())
            return first + remainder
        }.joined(separator: " ")
    }

    static func isHomeProfileFallbackEligible(_ error: Error) -> Bool {
        guard let onboardingError = error as? OnboardingServiceError else {
            return false
        }
        return onboardingError == .transportUnavailable || onboardingError == .serverUnavailable
    }

    static func homeProfileErrorMessage(_ error: Error) -> String {
        if let onboardingError = error as? OnboardingServiceError,
           onboardingError == .authenticationRequired {
            return "Please sign in again to load your learning home."
        }
        return "We couldn't load your learning home. Check your connection and try again."
    }

    static func isHomeProfileAuthenticationFailure(_ error: Error) -> Bool {
        guard let onboardingError = error as? OnboardingServiceError else {
            return false
        }
        return onboardingError == .authenticationRequired
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
        onboardingModel: OnboardingViewModel,
        onSessionCompleted: @escaping @MainActor @Sendable () async -> Void = {}
    ) -> TalkSessionViewModel {
        TalkSessionViewModel(
            settingsProvider: { [weak onboardingModel] in
                realtimeSettings(from: onboardingModel)
            },
            permission: SystemMicrophonePermission(),
            service: makeRealtimeSessionService(),
            completionService: makeRealtimeSessionCompletionService(),
            transport: makeRealtimeTransport(),
            accessTokenProvider: { [weak authModel] in authModel?.state.session?.accessToken },
            onAuthenticationRequired: { [weak authModel] in
                await authModel?.signOut()
            },
            onSessionCompleted: onSessionCompleted
        )
    }

    /// Creates the appropriate Realtime transport based on configuration.
    /// The WebSocket path owns native audio playback so received tutor audio
    /// can be amplified and limited deterministically.
    /// Otherwise, use placeholder that fails with clear message.
    static func makeRealtimeTransport() -> any RealtimeTransport {
        if backendBaseURL() == nil {
            return UnavailableRealtimeTransport(reason: "Voice sessions aren't configured for this build yet.")
        } else {
            return WebSocketRealtimeTransport()
        }
    }

    /// Derives Realtime coaching settings from the learner's onboarding state.
    @MainActor
    static func realtimeSettings(from onboardingModel: OnboardingViewModel?) -> RealtimeCoachingSettings {
        RealtimeCoachingSettings(
            proficiencyBand: proficiencyBand(for: onboardingModel?.placementEstimate),
            targetLanguage: canonicalLanguageKey(for: onboardingModel?.draft.targetLanguage)
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

    static func makeRealtimeSessionCompletionService() -> (any RealtimeSessionCompletionService)? {
        guard let baseURL = backendBaseURL() else {
            return nil
        }
        return VoxaBackendRealtimeSessionService(baseURL: baseURL)
    }

    static func makeDeveloperResetService() -> any DeveloperResetService {
        guard let baseURL = backendBaseURL() else {
            return UnavailableDeveloperResetService()
        }
        return VoxaBackendDeveloperResetService(baseURL: baseURL)
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

    /// Resolves a canonical BCP-47 language key from either a stored key or a
    /// legacy display name, defaulting to French when unset. Idempotent for keys.
    static func canonicalLanguageKey(for value: String?) -> String {
        guard let value, !value.isEmpty else { return "fr-FR" }
        if let key = OnboardingLanguages.key(forDisplayName: value) { return key }
        return value
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
