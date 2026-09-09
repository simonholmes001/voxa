import Foundation
import Observation

/// Orchestrates the Talk-screen Realtime session lifecycle: microphone
/// permission, requesting a backend session credential, and establishing the
/// media transport. All external dependencies are injected so the flow is
/// testable without hardware or a network.
@MainActor
@Observable
public final class TalkSessionViewModel {
    public private(set) var state: RealtimeConnectionState = .idle
    public private(set) var micPermission: MicrophonePermissionStatus = .undetermined
    public private(set) var pendingIntent: RealtimeTutorIntent = .openPractice
    /// Debrief lifecycle for the session that just ended (or is ending).
    /// Independent of `state` so the view can show a summary card while the
    /// connection is already torn down.
    public private(set) var debriefState: DebriefState = .idle

    private let settingsProvider: @MainActor @Sendable () -> RealtimeCoachingSettings
    private let permission: any MicrophonePermission
    private let service: any RealtimeSessionService
    private let completionService: (any RealtimeSessionCompletionService)?
    private let transport: any RealtimeTransport
    private let debriefService: any DebriefService
    private let accessTokenProvider: @MainActor @Sendable () -> String?
    private let onAuthenticationRequired: @MainActor @Sendable () async -> Void
    private let onSessionCompleted: @MainActor @Sendable () async -> Void
    private let nowProvider: @MainActor @Sendable () -> Date
    private var activeCredential: RealtimeSessionCredential?
    private var connectedAt: Date?

    /// Creates a Talk session model. `settingsProvider` is evaluated at
    /// `start()` time so the session reflects the learner's current
    /// language/level rather than a value fixed at construction.
    public init(
        settingsProvider: @escaping @MainActor @Sendable () -> RealtimeCoachingSettings,
        permission: any MicrophonePermission,
        service: any RealtimeSessionService,
        completionService: (any RealtimeSessionCompletionService)? = nil,
        transport: any RealtimeTransport = UnavailableRealtimeTransport(),
        debriefService: any DebriefService = NotConfiguredDebriefService(),
        accessTokenProvider: @escaping @MainActor @Sendable () -> String? = { nil },
        onAuthenticationRequired: @escaping @MainActor @Sendable () async -> Void = {},
        onSessionCompleted: @escaping @MainActor @Sendable () async -> Void = {},
        nowProvider: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) {
        self.settingsProvider = settingsProvider
        self.permission = permission
        self.service = service
        self.completionService = completionService
        self.transport = transport
        self.debriefService = debriefService
        self.accessTokenProvider = accessTokenProvider
        self.onAuthenticationRequired = onAuthenticationRequired
        self.onSessionCompleted = onSessionCompleted
        self.nowProvider = nowProvider
    }

    /// Convenience for fixed settings (previews/tests).
    public convenience init(
        settings: RealtimeCoachingSettings,
        permission: any MicrophonePermission,
        service: any RealtimeSessionService,
        completionService: (any RealtimeSessionCompletionService)? = nil,
        transport: any RealtimeTransport = UnavailableRealtimeTransport(),
        debriefService: any DebriefService = NotConfiguredDebriefService(),
        accessTokenProvider: @escaping @MainActor @Sendable () -> String? = { nil },
        onAuthenticationRequired: @escaping @MainActor @Sendable () async -> Void = {},
        onSessionCompleted: @escaping @MainActor @Sendable () async -> Void = {},
        nowProvider: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) {
        self.init(
            settingsProvider: { settings },
            permission: permission,
            service: service,
            completionService: completionService,
            transport: transport,
            debriefService: debriefService,
            accessTokenProvider: accessTokenProvider,
            onAuthenticationRequired: onAuthenticationRequired,
            onSessionCompleted: onSessionCompleted,
            nowProvider: nowProvider
        )
    }

    public func prepare(_ intent: RealtimeTutorIntent) {
        pendingIntent = intent
        if state == .ended {
            state = .idle
        }
        // Preparing a new intent implicitly acknowledges any pending debrief
        // from the previous session so the Talk screen doesn't reopen on the
        // stale summary card.
        if case .ready = debriefState { debriefState = .idle }
        if case .failed = debriefState { debriefState = .idle }
    }

    /// Starts a session: ensures mic permission, requests a credential, and
    /// connects the transport. Safe to call repeatedly; it no-ops while busy.
    public func start() async {
        guard !state.isBusy else { return }

        micPermission = permission.currentStatus()
        if micPermission == .undetermined {
            micPermission = await permission.request()
        }
        guard micPermission == .granted else {
            state = .failed("Microphone access is required to talk with your tutor.")
            return
        }

        guard let token = accessTokenProvider(), !token.isEmpty else {
            state = .failed("Please sign in again to start a session.")
            return
        }

        let settings = settingsProvider().applying(pendingIntent)
        state = .requestingSession
        let credential: RealtimeSessionCredential
        do {
            credential = try await service.createSession(settings, accessToken: token)
        } catch {
            state = .failed(Self.message(for: error))
            if case RealtimeSessionError.appSessionRequired = error {
                await onAuthenticationRequired()
            }
            return
        }

        state = .connecting
        do {
            try await transport.connect(using: credential)
        } catch {
            state = .failed(Self.message(for: error))
            return
        }

        state = .connected
        activeCredential = credential
        connectedAt = nowProvider()
    }

    /// Interrupts the tutor mid-sentence. Safe to call any time — a no-op
    /// when the tutor isn't currently speaking. Used by the Talk UI to give
    /// the learner a tap-to-interrupt affordance.
    public func interrupt() async {
        guard case .connected = state else { return }
        await transport.interrupt()
    }

    /// Ends the current session and tears down the transport.
    /// After teardown, kicks off the post-session debrief in the background if
    /// the transcript captured at least one turn. The view observes
    /// `debriefState` to render the summary card / spinner / error.
    public func end() async {
        let settings = activeCredential?.settings
        await transport.disconnect()
        await recordCompletionIfPossible()
        let transcript = transport.capturedTranscript()
        activeCredential = nil
        connectedAt = nil
        state = .ended
        if !transcript.isEmpty, let settings {
            await runDebrief(settings: settings, transcript: transcript)
        } else {
            debriefState = .idle
        }
    }

    /// Clears any stale debrief when the learner navigates back to Talk to
    /// start a new session (called from the debrief view's "start next drill"
    /// action, or from a plain dismissal).
    public func acknowledgeDebrief() {
        debriefState = .idle
    }

    private func runDebrief(
        settings: RealtimeCoachingSettings,
        transcript: [TranscriptTurn]
    ) async {
        guard let token = accessTokenProvider(), !token.isEmpty else {
            debriefState = .failed("Please sign in again to see your session summary.")
            return
        }
        debriefState = .loading
        do {
            let debrief = try await debriefService.generateDebrief(
                settings: settings,
                transcript: transcript,
                accessToken: token)
            debriefState = .ready(debrief)
        } catch {
            debriefState = .failed(Self.debriefMessage(for: error))
        }
    }

    private static func debriefMessage(for error: Error) -> String {
        switch error {
        case DebriefServiceError.authenticationRequired:
            return "Please sign in again to see your session summary."
        case let DebriefServiceError.notConfigured(reason):
            return reason
        case DebriefServiceError.transport:
            return "We couldn't reach Voxa to generate your session summary. Try again later."
        case let DebriefServiceError.server(code, _):
            return "Session summary service returned an error (\(code)). Try again later."
        default:
            return "We couldn't generate a session summary this time."
        }
    }

    private func recordCompletionIfPossible() async {
        guard let completionService, let credential = activeCredential else { return }
        guard let token = accessTokenProvider(), !token.isEmpty else { return }

        let startedAt = connectedAt ?? nowProvider()
        let durationSeconds = Int(nowProvider().timeIntervalSince(startedAt))
        do {
            try await completionService.completeSession(
                RealtimeSessionCompletion(
                    sessionId: credential.correlationId,
                    durationSeconds: durationSeconds,
                    sessionIntent: credential.settings.sessionIntent
                ),
                accessToken: token)
            await onSessionCompleted()
        } catch {
            return
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RealtimeSessionError.appSessionRequired:
            return "Your session expired. Please sign in again."
        case let RealtimeSessionError.notConfigured(reason):
            return reason
        case RealtimeSessionError.transport:
            return "We couldn't reach Voxa. Check your connection and try again."
        case let RealtimeSessionError.validation(message):
            return message
        case let RealtimeSessionError.server(code, message):
            return "Server error (\(code)): \(message)"
        case let RealtimeTransportError.unavailable(reason):
            return reason
        case let RealtimeTransportError.connectionFailed(reason):
            return "We couldn't connect to your tutor: \(reason)"
        default:
            // Fall back to error's description when available for easier diagnostics.
            return (error as NSError).localizedDescription
        }
    }
}
