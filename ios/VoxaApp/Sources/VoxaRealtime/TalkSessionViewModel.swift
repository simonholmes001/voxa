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

    private let settingsProvider: @MainActor () -> RealtimeCoachingSettings
    private let permission: any MicrophonePermission
    private let service: any RealtimeSessionService
    private let transport: any RealtimeTransport
    private let accessTokenProvider: @MainActor () -> String?

    /// Creates a Talk session model. `settingsProvider` is evaluated at
    /// `start()` time so the session reflects the learner's current
    /// language/level rather than a value fixed at construction.
    public init(
        settingsProvider: @escaping @MainActor () -> RealtimeCoachingSettings,
        permission: any MicrophonePermission,
        service: any RealtimeSessionService,
        transport: any RealtimeTransport = UnavailableRealtimeTransport(),
        accessTokenProvider: @escaping @MainActor () -> String? = { nil }
    ) {
        self.settingsProvider = settingsProvider
        self.permission = permission
        self.service = service
        self.transport = transport
        self.accessTokenProvider = accessTokenProvider
    }

    /// Convenience for fixed settings (previews/tests).
    public convenience init(
        settings: RealtimeCoachingSettings,
        permission: any MicrophonePermission,
        service: any RealtimeSessionService,
        transport: any RealtimeTransport = UnavailableRealtimeTransport(),
        accessTokenProvider: @escaping @MainActor () -> String? = { nil }
    ) {
        self.init(
            settingsProvider: { settings },
            permission: permission,
            service: service,
            transport: transport,
            accessTokenProvider: accessTokenProvider
        )
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

        let settings = settingsProvider()
        state = .requestingSession
        let credential: RealtimeSessionCredential
        do {
            credential = try await service.createSession(settings, accessToken: token)
        } catch {
            state = .failed(Self.message(for: error))
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
    }

    /// Ends the current session and tears down the transport.
    public func end() async {
        await transport.disconnect()
        state = .ended
    }

    private static func message(for error: Error) -> String {
        switch error {
        case RealtimeSessionError.appSessionRequired:
            return "Your session expired. Please sign in again."
        case RealtimeSessionError.notConfigured:
            return "Voice sessions aren't configured for this build yet."
        case RealtimeSessionError.transport:
            return "We couldn't reach Voxa. Check your connection and try again."
        case let RealtimeTransportError.unavailable(reason):
            return reason
        case RealtimeTransportError.connectionFailed:
            return "We couldn't connect to your tutor. Please try again."
        default:
            return "We couldn't start the session. Please try again."
        }
    }
}
