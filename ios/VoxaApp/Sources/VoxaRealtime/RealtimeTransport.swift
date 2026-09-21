/// Abstracts the media transport that establishes the direct WebRTC connection
/// to OpenAI Realtime using the backend-issued ephemeral credential.
///
/// Production builds inject the concrete WebRTC implementation when the app has
/// a backend base URL. Previews, tests, and deliberately unconfigured builds can
/// inject `UnavailableRealtimeTransport` to fail clearly before live audio.
public protocol RealtimeTransport: Sendable {
    /// Establishes the media session for the given credential. Returns once the
    /// peer connection is established, or throws on failure.
    func connect(using credential: RealtimeSessionCredential) async throws
    /// Tears down the media session.
    func disconnect() async
    /// Cancels the tutor's current response mid-flight: stops local playback,
    /// releases the mic gate, and asks the server to stop generating so the
    /// learner can take the floor. No-op when no response is in progress.
    func interrupt() async
    /// Plays a single assistant response using the credential's voice settings
    /// without opening a full learner conversation.
    func playPreview(
        using credential: RealtimeSessionCredential,
        text: String
    ) async throws
    /// The transcript accumulated during the session, in turn order. Returned
    /// after `disconnect()` so the post-session debrief can be generated from
    /// what was actually said. Empty for transports that don't capture
    /// transcripts (WebRTC today) or sessions that produced none.
    func capturedTranscript() -> [TranscriptTurn]

    /// Registers a callback for the tutor's explicit session-completion
    /// marker. The callback is invoked after any queued tutor audio has
    /// finished playing. Transports that cannot observe tutor transcripts may
    /// leave this as a no-op.
    func setSessionCompletionHandler(_ handler: (@Sendable () -> Void)?)
}

public extension RealtimeTransport {
    func setSessionCompletionHandler(_ handler: (@Sendable () -> Void)?) {}

    // Default no-op keeps existing transports (WebRTC, Unavailable, fakes)
    // source-compatible. Only WebSocketRealtimeTransport actually implements
    // barge-in and transcript capture today.
    func interrupt() async {}
    func playPreview(
        using credential: RealtimeSessionCredential,
        text: String
    ) async throws {
        throw RealtimeTransportError.unavailable("Voice preview isn't configured for this build yet.")
    }
    func capturedTranscript() -> [TranscriptTurn] { [] }
}

public enum RealtimeTransportError: Error, Equatable {
    /// The WebRTC transport has not been integrated yet.
    case unavailable(String)
    /// The peer connection could not be established.
    case connectionFailed(String)
}

/// Placeholder transport for previews, tests, and builds without Realtime
/// configuration.
public struct UnavailableRealtimeTransport: RealtimeTransport {
    private let reason: String

    public init(reason: String = "The Realtime WebRTC transport is not configured.") {
        self.reason = reason
    }

    public func connect(using credential: RealtimeSessionCredential) async throws {
        throw RealtimeTransportError.unavailable(reason)
    }

    public func disconnect() async {}
}
