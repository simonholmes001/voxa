import XCTest
import WebRTC
import VoxaRealtime
@testable import VoxaRealtimeWebRTC

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

    func testCallsExchangerPostsDocumentedMultipartRequestAndAcceptsCreatedAnswer() async throws {
        let session = URLSession(configuration: Self.urlSessionConfiguration())
        let exchanger = OpenAIRealtimeCallsExchanger(
            session: session,
            endpoint: URL(string: "https://api.openai.test/v1/realtime/calls")!,
            boundaryProvider: { "test-boundary" }
        )
        StubURLProtocol.handler = { request, body in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.test/v1/realtime/calls")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ephemeral-client-secret")

            let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
            XCTAssertEqual(contentType, "multipart/form-data; boundary=test-boundary")

            let text = try XCTUnwrap(String(data: body, encoding: .utf8))
            XCTAssertEqual(Self.multipartPart(named: "sdp", in: text), "v=0\r\no=- test-offer")

            let sessionJSON = try XCTUnwrap(Self.multipartPart(named: "session", in: text))
            let sessionObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(sessionJSON.utf8)) as? [String: Any]
            )
            XCTAssertEqual(sessionObject["type"] as? String, "realtime")
            XCTAssertEqual(sessionObject["model"] as? String, "gpt-realtime-2.1")

            let reasoning = try XCTUnwrap(sessionObject["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "low")

            let metadata = try XCTUnwrap(sessionObject["metadata"] as? [String: Any])
            XCTAssertEqual(metadata["coaching_mode"] as? String, "tutor")
            XCTAssertEqual(metadata["proficiency_band"] as? String, "B1-B2")
            XCTAssertEqual(metadata["target_language"] as? String, "fr-FR")

            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("v=0\r\no=- test-answer".utf8))
        }

        let answer = try await exchanger.createCall(
            offerSDP: "v=0\r\no=- test-offer",
            credential: RealtimeSessionCredential(
                clientSecret: "ephemeral-client-secret",
                model: "gpt-realtime-2.1",
                reasoningEffort: "low",
                expiresAt: Date(timeIntervalSinceNow: 60),
                settings: validSettings
            )
        )

        XCTAssertEqual(answer, "v=0\r\no=- test-answer")
    }

    func testCallsExchangerRejectsOpenAIErrorStatus() async {
        let session = URLSession(configuration: Self.urlSessionConfiguration())
        let exchanger = OpenAIRealtimeCallsExchanger(
            session: session,
            endpoint: URL(string: "https://api.openai.test/v1/realtime/calls")!
        )
        StubURLProtocol.handler = { request, _ in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await exchanger.createCall(offerSDP: "v=0", credential: validCredential())
            XCTFail("expected status failure")
        } catch RealtimeTransportError.connectionFailed(let message) {
            XCTAssertTrue(message.contains("401"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testReadinessWaitsForConnectedSignal() async throws {
        let readiness = WebRTCPeerConnectionReadiness()
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            readiness.markConnected()
        }

        try await readiness.wait(timeoutNanoseconds: 1_000_000_000)
    }

    func testReadinessFailsWhenPeerConnectionFails() async {
        let readiness = WebRTCPeerConnectionReadiness()
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            readiness.markFailed("ICE failed")
        }

        do {
            try await readiness.wait(timeoutNanoseconds: 1_000_000_000)
            XCTFail("expected readiness failure")
        } catch RealtimeTransportError.connectionFailed(let message) {
            XCTAssertEqual(message, "ICE failed")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testReadinessTimesOutWithoutConnectedSignal() async {
        let readiness = WebRTCPeerConnectionReadiness()

        do {
            try await readiness.wait(timeoutNanoseconds: 1)
            XCTFail("expected timeout")
        } catch RealtimeTransportError.connectionFailed(let message) {
            XCTAssertTrue(message.contains("timed out"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLifecycleRetainsAndEnablesRemoteAudioTrack() {
        let lifecycle = WebRTCTransportLifecycle()
        let audioSource = RTCPeerConnectionFactory.sharedInstance().audioSource(
            with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        )
        let audioTrack = RTCPeerConnectionFactory.sharedInstance().audioTrack(
            with: audioSource,
            trackId: "remote-audio"
        )
        audioTrack.isEnabled = false

        lifecycle.retainRemoteAudioTracks([audioTrack])

        let state = lifecycle.clear()
        XCTAssertEqual(state.remoteAudioTracks.count, 1)
        XCTAssertTrue(state.remoteAudioTracks[0].isEnabled)
    }

    func testLifecycleClearDropsStaleReadiness() throws {
        let lifecycle = WebRTCTransportLifecycle()
        let readiness = WebRTCPeerConnectionReadiness()
        _ = lifecycle.start(peerConnection: try Self.makePeerConnection(), readiness: readiness)

        _ = lifecycle.clear()

        XCTAssertNil(lifecycle.currentReadiness())
    }

    func testStaleConnectionCleanupDoesNotClearNewerActiveConnection() throws {
        let lifecycle = WebRTCTransportLifecycle()
        let firstReadiness = WebRTCPeerConnectionReadiness()
        let firstID = lifecycle.start(peerConnection: try Self.makePeerConnection(), readiness: firstReadiness)

        let secondReadiness = WebRTCPeerConnectionReadiness()
        _ = lifecycle.start(peerConnection: try Self.makePeerConnection(), readiness: secondReadiness)

        let staleState = lifecycle.clearIfActive(firstID)

        XCTAssertNil(staleState.peerConnection)
        XCTAssertTrue(lifecycle.currentReadiness() === secondReadiness)
    }

    private static func urlSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    private static func multipartPart(named name: String, in body: String) -> String? {
        let marker = "Content-Disposition: form-data; name=\"\(name)\""
        guard let markerRange = body.range(of: marker),
              let headerEnd = body[markerRange.upperBound...].range(of: "\r\n\r\n") else {
            return nil
        }

        let valueStart = headerEnd.upperBound
        guard let valueEnd = body[valueStart...].range(of: "\r\n--") else {
            return nil
        }

        return String(body[valueStart..<valueEnd.lowerBound])
    }

    private static func makePeerConnection() throws -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return try XCTUnwrap(RTCPeerConnectionFactory.sharedInstance().peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: nil
        ))
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest, Data) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
            let (response, data) = try handler(request, body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
