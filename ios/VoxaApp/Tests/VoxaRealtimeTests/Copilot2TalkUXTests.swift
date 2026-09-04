import XCTest
@testable import VoxaRealtime

final class Copilot2TalkUXTests: XCTestCase {
    func test_connect_updates_state_sequence() async throws {
        let transport = FakeRealtimeTransport()
        XCTAssertEqual(transport.state, .idle)

        let task = Task {
            await transport.connect()
        }

        // allow connect() to begin
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(transport.state, .connecting)

        // wait for completion
        try await task.value
        XCTAssertEqual(transport.state, .connected)
    }

    func test_connect_failure_sets_error_and_allows_retry() async throws {
        let transport = FakeRealtimeTransport()
        transport.shouldFail = true

        await transport.connect()
        if case .failed(let msg) = transport.state {
            XCTAssertEqual(msg, "simulated failure")
        } else {
            XCTFail("Expected failed state")
        }

        // prepare for retry
        transport.shouldFail = false
        await transport.connect()
        XCTAssertEqual(transport.state, .connected)
    }

    func test_disconnect_resets_state() async throws {
        let transport = FakeRealtimeTransport()
        await transport.connect()
        XCTAssertEqual(transport.state, .connected)
        transport.disconnect()
        XCTAssertEqual(transport.state, .idle)
    }

    func test_permission_denied_blocks_connect() async throws {
        // Simulate permission gate: when permissionDenied is true, do not call connect
        struct PermissionGate {
            var denied: Bool
            func attemptConnect(transport: FakeRealtimeTransport) async {
                if denied { return }
                await transport.connect()
            }
        }

        let transport = FakeRealtimeTransport()
        let gate = PermissionGate(denied: true)
        await gate.attemptConnect(transport: transport)
        XCTAssertEqual(transport.state, .idle)

        let gate2 = PermissionGate(denied: false)
        await gate2.attemptConnect(transport: transport)
        XCTAssertEqual(transport.state, .connected)
    }
}
