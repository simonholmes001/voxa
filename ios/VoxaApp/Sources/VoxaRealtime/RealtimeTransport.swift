/// Abstracts the media transport that establishes the direct WebRTC connection
/// to OpenAI Realtime using the backend-issued ephemeral credential.
///
/// The concrete WebRTC implementation requires a libwebrtc dependency, which is
/// an explicit architecture/dependency decision. Until it is integrated, the
/// app injects `UnavailableRealtimeTransport`, so the Talk flow is fully wired
/// and testable up to (but not including) live audio.
public protocol RealtimeTransport: Sendable {
    /// Establishes the media session for the given credential. Returns once the
    /// peer connection is established, or throws on failure.
    func connect(using credential: RealtimeSessionCredential) async throws
    /// Tears down the media session.
    func disconnect() async
}

public enum RealtimeTransportError: Error, Equatable {
    /// The WebRTC transport has not been integrated yet.
    case unavailable(String)
    /// The peer connection could not be established.
    case connectionFailed(String)
}

/// Placeholder transport until the WebRTC (libwebrtc) integration is approved.
public struct UnavailableRealtimeTransport: RealtimeTransport {
    private let reason: String

    public init(reason: String = "The Realtime WebRTC transport is not yet integrated.") {
        self.reason = reason
    }

    public func connect(using credential: RealtimeSessionCredential) async throws {
        throw RealtimeTransportError.unavailable(reason)
    }

    public func disconnect() async {}
}
