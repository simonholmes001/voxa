import XCTest
@testable import VoxaRealtime

/// Tests for WebRTCRealtimeTransport lifecycle and basic contract validation.
/// The actual WebRTC SDP exchange and peer connection logic cannot be unit-tested
/// without running against a real OpenAI endpoint or a complex WebRTC mock.
/// These tests verify the transport's public contract and credential validation.
@MainActor
final class WebRTCRealtimeTransportTests: XCTestCase {
    private let validSettings = RealtimeCoachingSettings(
        proficiencyBand: "B1-B2",
        targetLanguage: "fr-FR"
    )

    private func validCredential(expiresIn seconds: TimeInterval = 60) -> RealtimeSessionCredential {
        RealtimeSessionCredential(
            clientSecret: "secret-test-token",
            model: "gpt-realtime",
            reasoningEffort: "low",
            expiresAt: Date(timeIntervalSinceNow: seconds),
            settings: validSettings
        )
    }

    func testInitializes() {
        let transport = WebRTCRealtimeTransport()
        XCTAssertNotNil(transport)
    }

    func testRejectsExpiredCredential() async {
        let transport = WebRTCRealtimeTransport()
        let expired = validCredential(expiresIn: -10)

        do {
            try await transport.connect(using: expired)
            XCTFail("Expected connectionFailed for expired credential")
        } catch RealtimeTransportError.connectionFailed(let message) {
            XCTAssertTrue(message.contains("expired"), "Message should mention expiration")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDisconnectCanBeCalledWithoutConnect() async {
        let transport = WebRTCRealtimeTransport()
        // Should not crash or throw
        await transport.disconnect()
    }

    func testDisconnectCanBeCalledMultipleTimes() async {
        let transport = WebRTCRealtimeTransport()
        await transport.disconnect()
        await transport.disconnect()
    }

    // NOTE: We cannot test actual connect() without a real OpenAI endpoint or
    // heavy WebRTC mocking. Integration/device tests must verify:
    // - SDP offer/answer exchange with valid clientSecret
    // - Audio session configuration on iOS
    // - Peer connection state transitions
    // - Data channel setup for events
    // - Proper cleanup on disconnect
}
