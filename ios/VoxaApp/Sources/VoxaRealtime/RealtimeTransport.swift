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
