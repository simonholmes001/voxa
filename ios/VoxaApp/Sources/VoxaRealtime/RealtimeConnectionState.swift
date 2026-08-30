/// The lifecycle of a Talk-screen Realtime session.
public enum RealtimeConnectionState: Sendable, Equatable {
    case idle
    case requestingSession
    case connecting
    case connected
    case failed(String)
    case ended

    /// Whether a session is in progress (so `start` is a no-op).
    public var isBusy: Bool {
        switch self {
        case .requestingSession, .connecting, .connected: return true
        case .idle, .failed, .ended: return false
        }
    }
}
