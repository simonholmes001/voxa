import XCTest
@testable import VoxaRealtimeWebRTC

/// Direct coverage of the handshake dispatcher primitive that lets the
/// WebSocketRealtimeTransport start its receive loop before any handshake
/// step — so events emitted between session.created and session.updated are
/// no longer silently dropped by a per-step read.
///
/// A full end-to-end handshake test needs a mock URLSessionWebSocketTask (a
/// follow-up); these tests lock the safety-critical primitive.
final class WebSocketHandshakeContinuationTests: XCTestCase {
    func testSucceedResumesTheAttachedContinuation() async throws {
        let waiter = WebSocketRealtimeTransport.HandshakeContinuation()

        async let result: Void = withCheckedThrowingContinuation { cont in
            waiter.attach(cont)
        }

        // Give the concurrent task a moment to attach before we resume it.
        try await Task.sleep(for: .milliseconds(20))
        waiter.succeed()
        try await result
    }

    func testFailResumesTheAttachedContinuationWithError() async {
        struct SentinelError: Error, Equatable {}
        let waiter = WebSocketRealtimeTransport.HandshakeContinuation()

        async let result: Void = withCheckedThrowingContinuation { cont in
            waiter.attach(cont)
        }

        try? await Task.sleep(for: .milliseconds(20))
        waiter.fail(SentinelError())

        do {
            try await result
            XCTFail("Expected fail() to throw the sentinel error.")
        } catch is SentinelError {
            // Expected.
        } catch {
            XCTFail("Expected SentinelError, got \(error)")
        }
    }

    func testSecondResumeIsANoOpAfterSucceed() async throws {
        // Guard against the double-resume race between the handshake waiter
        // task and the timeout task in waitForHandshakeEvent — Swift traps
        // on double resume, so this must NOT crash.
        struct SentinelError: Error {}
        let waiter = WebSocketRealtimeTransport.HandshakeContinuation()

        async let result: Void = withCheckedThrowingContinuation { cont in
            waiter.attach(cont)
        }

        try await Task.sleep(for: .milliseconds(20))
        waiter.succeed()
        try await result

        // The second call would previously double-resume the continuation
        // (or its already-nilled reference). Both must be safe no-ops.
        waiter.succeed()
        waiter.fail(SentinelError())
    }

    func testSecondResumeIsANoOpAfterFail() async {
        struct FirstError: Error {}
        struct SecondError: Error {}
        let waiter = WebSocketRealtimeTransport.HandshakeContinuation()

        async let result: Void = withCheckedThrowingContinuation { cont in
            waiter.attach(cont)
        }

        try? await Task.sleep(for: .milliseconds(20))
        waiter.fail(FirstError())

        do {
            try await result
            XCTFail("Expected fail() to throw.")
        } catch is FirstError {
            // Expected.
        } catch {
            XCTFail("Expected FirstError, got \(error)")
        }

        // The second call must not trap or double-resume.
        waiter.succeed()
        waiter.fail(SecondError())
    }
}
