import XCTest
@testable import VoxaRealtimeWebRTC

/// The transport instance is owned for the lifetime of a `TalkSessionViewModel`,
/// so a normal end-and-restart flow calls `connect() → disconnect() → connect()`
/// on the same object. Every `connect()` runs the AVAudioEngine setup that
/// attaches the player node to the mixer; attaching an already-attached node
/// raises an ObjC `NSInternalInconsistencyException` that Swift can't catch,
/// which would crash the app on the second Talk start.
///
/// These tests exercise the reconnect safety directly on a real
/// `AVAudioEngine`, so they would crash against the pre-fix code.
final class WebSocketReconnectSafetyTests: XCTestCase {
    func testConfigureAudioPipelineIsIdempotentAcrossManyCalls() {
        let transport = WebSocketRealtimeTransport()
        XCTAssertFalse(transport.audioPipelineConfigured)

        transport.configureAudioPipelineIfNeeded()
        XCTAssertTrue(transport.audioPipelineConfigured)

        // Without the idempotency guard, engine.attach(player) fires an
        // NSInternalInconsistencyException here. If we reach the next line
        // the guard is doing its job.
        transport.configureAudioPipelineIfNeeded()
        transport.configureAudioPipelineIfNeeded()
        transport.configureAudioPipelineIfNeeded()
        XCTAssertTrue(transport.audioPipelineConfigured)
    }

    func testDisconnectPreservesAudioPipelineConfiguredForReconnectSafety() async {
        let transport = WebSocketRealtimeTransport()
        transport.configureAudioPipelineIfNeeded()
        XCTAssertTrue(transport.audioPipelineConfigured)

        await transport.disconnect()

        // The whole point of the flag is that disconnect() does NOT reset it.
        // If disconnect() cleared it, the next connect() would call
        // engine.attach(player) on an already-attached node → crash.
        XCTAssertTrue(transport.audioPipelineConfigured)

        // Simulating a reconnect: this must be a safe no-op, not a crash.
        transport.configureAudioPipelineIfNeeded()
        XCTAssertTrue(transport.audioPipelineConfigured)
    }
}
