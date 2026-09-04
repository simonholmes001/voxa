import Foundation

public final class FakeRealtimeTransport: RealtimeTransport {
    public private(set) var state: RealtimeTransportState = .idle
    public var connectDelayNanoseconds: UInt64 = 150_000_000
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
