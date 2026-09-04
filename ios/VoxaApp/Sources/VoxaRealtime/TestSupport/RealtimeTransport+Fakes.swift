import Foundation

public enum RealtimeTransportState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

public protocol RealtimeTransport {
    var state: RealtimeTransportState { get }
    func connect() async
    func disconnect()
}

public final class FakeRealtimeTransport: RealtimeTransport {
    public private(set) var state: RealtimeTransportState = .idle
    public var connectDelayNanoseconds: UInt64 = 120_000_000
    public var shouldFail: Bool = false
    public var failureMessage: String = "simulated failure"

    public init() {}

    public func connect() async {
        state = .connecting
        if connectDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: connectDelayNanoseconds)
        }
        if shouldFail {
            state = .failed(failureMessage)
        } else {
            state = .connected
        }
    }

    public func disconnect() {
        state = .idle
    }
}
