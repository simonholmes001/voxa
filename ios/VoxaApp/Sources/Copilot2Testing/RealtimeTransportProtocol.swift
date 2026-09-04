import Foundation

/// Lightweight transport state used by ViewModels/tests.
public enum RealtimeTransportState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

/// Minimal transport protocol used to exercise lifecycle/state logic in ViewModels.
public protocol RealtimeTransport {
    var state: RealtimeTransportState { get }

    /// Starts connection process (e.g. SDP exchange + peer connection). Async so tests can await.
    func connect() async

    /// Tears down any active connection synchronously.
    func disconnect()
}
