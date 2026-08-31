import AVFoundation
import VoxaRealtime
import WebRTC

#if canImport(UIKit)
import UIKit
#endif

/// Real WebRTC transport for OpenAI Realtime API. Establishes a peer connection
/// using the backend-issued ephemeral credential (clientSecret) to authenticate
/// the SDP exchange with OpenAI.
public final class WebRTCRealtimeTransport: NSObject, RealtimeTransport, @unchecked Sendable {
    #if os(iOS)
    private let audioSession: AVAudioSession
    #endif
    private let callsExchanger: any RealtimeCallsExchanging
    private let connectionTimeoutNanoseconds: UInt64
    private let lifecycle = WebRTCTransportLifecycle()

    #if os(iOS)
    public init(
        audioSession: AVAudioSession = .sharedInstance(),
        callsExchanger: any RealtimeCallsExchanging = OpenAIRealtimeCallsExchanger(),
        connectionTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        self.audioSession = audioSession
        self.callsExchanger = callsExchanger
        self.connectionTimeoutNanoseconds = connectionTimeoutNanoseconds
        super.init()
    }
    #else
    public init(
        callsExchanger: any RealtimeCallsExchanging = OpenAIRealtimeCallsExchanger(),
        connectionTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        self.callsExchanger = callsExchanger
        self.connectionTimeoutNanoseconds = connectionTimeoutNanoseconds
        super.init()
    }
    #endif

    public func connect(using credential: RealtimeSessionCredential) async throws {
        guard !credential.isExpired() else {
            throw RealtimeTransportError.connectionFailed("Session credential has expired")
        }

        var connectionID: UUID?
        do {
            // Configure audio session for voice chat
            try configureAudioSession()

            // Create peer connection with STUN servers
            let configuration = RTCConfiguration()
            configuration.sdpSemantics = .unifiedPlan
            configuration.continualGatheringPolicy = .gatherContinually
            configuration.iceServers = [
                RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
            ]

            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )

            let readiness = WebRTCPeerConnectionReadiness()

            guard let pc = RTCPeerConnectionFactory.sharedInstance().peerConnection(
                with: configuration,
                constraints: constraints,
                delegate: self
            ) else {
                throw RealtimeTransportError.connectionFailed("Failed to create peer connection")
            }
            connectionID = lifecycle.start(peerConnection: pc, readiness: readiness)

            try addLocalAudioTrack(to: pc)
            try createDataChannel(on: pc)

            let offer = try await createOffer(on: pc)
            try await setLocalDescription(offer, on: pc)

            let answer = try await callsExchanger.createCall(
                offerSDP: offer.sdp,
                credential: credential
            )

            let remoteDescription = RTCSessionDescription(type: .answer, sdp: answer)
            try await setRemoteDescription(remoteDescription, on: pc)
            try await readiness.wait(timeoutNanoseconds: connectionTimeoutNanoseconds)
        } catch {
            if let connectionID {
                let state = lifecycle.clearIfActive(connectionID)
                state.dataChannel?.close()
                state.peerConnection?.close()
            }
            deactivateAudioSession()
            throw error
        }
    }

    public func disconnect() async {
        let state = lifecycle.clear()
        state.dataChannel?.close()
        state.peerConnection?.close()

        deactivateAudioSession()
    }

    // MARK: - Private helpers

    private func configureAudioSession() throws {
        #if os(iOS)
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func addLocalAudioTrack(to pc: RTCPeerConnection) throws {
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = RTCPeerConnectionFactory.sharedInstance().audioSource(with: audioConstraints)
        let audioTrack = RTCPeerConnectionFactory.sharedInstance().audioTrack(with: audioSource, trackId: "audio0")

        pc.add(audioTrack, streamIds: ["stream0"])
        lifecycle.setLocalAudioTrack(audioTrack)
    }

    private func createDataChannel(on pc: RTCPeerConnection) throws {
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        guard let dc = pc.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig) else {
            throw RealtimeTransportError.connectionFailed("Failed to create data channel")
        }
        lifecycle.setDataChannel(dc)
    }

    private func createOffer(on pc: RTCPeerConnection) async throws -> RTCSessionDescription {
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true"
            ],
            optionalConstraints: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            pc.offer(for: offerConstraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: RealtimeTransportError.connectionFailed("No SDP offer generated"))
                }
            }
        }
    }

    private func setLocalDescription(_ description: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(description) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(description) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

extension WebRTCRealtimeTransport: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        lifecycle.retainRemoteAudioTracks(stream.audioTracks)
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            lifecycle.currentReadiness()?.markConnected()
        case .failed, .disconnected, .closed:
            lifecycle.currentReadiness()?.markFailed("WebRTC connection failed.")
        default:
            break
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        if let audioTrack = rtpReceiver.track as? RTCAudioTrack {
            lifecycle.retainRemoteAudioTracks([audioTrack])
        }
    }
}

public protocol RealtimeCallsExchanging: Sendable {
    func createCall(offerSDP: String, credential: RealtimeSessionCredential) async throws -> String
}

public struct OpenAIRealtimeCallsExchanger: RealtimeCallsExchanging {
    private let session: URLSession
    private let endpoint: URL
    private let boundaryProvider: @Sendable () -> String

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.openai.com/v1/realtime/calls")!,
        boundaryProvider: @escaping @Sendable () -> String = { "voxa-\(UUID().uuidString)" }
    ) {
        self.session = session
        self.endpoint = endpoint
        self.boundaryProvider = boundaryProvider
    }

    public func createCall(offerSDP: String, credential: RealtimeSessionCredential) async throws -> String {
        let boundary = boundaryProvider()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.multipartBody(
            boundary: boundary,
            offerSDP: offerSDP,
            credential: credential
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RealtimeTransportError.connectionFailed("OpenAI Realtime call request failed.")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RealtimeTransportError.connectionFailed("Invalid response from OpenAI.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RealtimeTransportError.connectionFailed("OpenAI returned status \(httpResponse.statusCode).")
        }

        guard let answerSDP = String(data: data, encoding: .utf8), !answerSDP.isEmpty else {
            throw RealtimeTransportError.connectionFailed("Invalid SDP answer from OpenAI.")
        }

        return answerSDP
    }

    private static func multipartBody(
        boundary: String,
        offerSDP: String,
        credential: RealtimeSessionCredential
    ) throws -> Data {
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"sdp\"\r\n")
        body.appendString("Content-Type: application/sdp\r\n\r\n")
        body.appendString(offerSDP)
        body.appendString("\r\n")
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"session\"\r\n")
        body.appendString("Content-Type: application/json\r\n\r\n")
        body.append(try sessionJSON(credential: credential))
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    private static func sessionJSON(credential: RealtimeSessionCredential) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(RealtimeCallSessionPayload(
            type: "realtime",
            model: credential.model,
            reasoning: RealtimeCallReasoningPayload(effort: credential.reasoningEffort),
            metadata: RealtimeCallMetadataPayload(
                coachingMode: credential.settings.coachingMode,
                proficiencyBand: credential.settings.proficiencyBand,
                targetLanguage: credential.settings.targetLanguage
            )
        ))
    }
}

private struct RealtimeCallSessionPayload: Encodable {
    let type: String
    let model: String
    let reasoning: RealtimeCallReasoningPayload
    let metadata: RealtimeCallMetadataPayload
}

private struct RealtimeCallReasoningPayload: Encodable {
    let effort: String
}

private struct RealtimeCallMetadataPayload: Encodable {
    let coachingMode: String
    let proficiencyBand: String
    let targetLanguage: String

    enum CodingKeys: String, CodingKey {
        case coachingMode = "coaching_mode"
        case proficiencyBand = "proficiency_band"
        case targetLanguage = "target_language"
    }
}

final class WebRTCPeerConnectionReadiness: @unchecked Sendable {
    private enum State {
        case waiting
        case connected
        case failed(String)
    }

    private let lock = NSLock()
    private var state: State = .waiting
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(timeoutNanoseconds: UInt64) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            switch state {
            case .connected:
                lock.unlock()
                continuation.resume()
            case .failed(let message):
                lock.unlock()
                continuation.resume(throwing: RealtimeTransportError.connectionFailed(message))
            case .waiting:
                self.continuation = continuation
                lock.unlock()
                Task {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    self.markFailed("WebRTC connection timed out.")
                }
            }
        }
    }

    func markConnected() {
        resume(state: .connected)
    }

    func markFailed(_ message: String) {
        resume(state: .failed(message))
    }

    private func resume(state newState: State) {
        let continuation: CheckedContinuation<Void, Error>?
        lock.lock()
        guard case .waiting = state else {
            lock.unlock()
            return
        }
        state = newState
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        switch newState {
        case .connected:
            continuation?.resume()
        case .failed(let message):
            continuation?.resume(throwing: RealtimeTransportError.connectionFailed(message))
        case .waiting:
            break
        }
    }
}

final class WebRTCTransportLifecycle: @unchecked Sendable {
    struct State {
        var connectionID: UUID?
        var peerConnection: RTCPeerConnection?
        var dataChannel: RTCDataChannel?
        var localAudioTrack: RTCAudioTrack?
        var remoteAudioTracks: [RTCAudioTrack]
        var readiness: WebRTCPeerConnectionReadiness?
    }

    private let lock = NSLock()
    private var state = State(
        connectionID: nil,
        peerConnection: nil,
        dataChannel: nil,
        localAudioTrack: nil,
        remoteAudioTracks: [],
        readiness: nil
    )

    func start(peerConnection: RTCPeerConnection, readiness: WebRTCPeerConnectionReadiness) -> UUID {
        let connectionID = UUID()
        lock.lock()
        state.connectionID = connectionID
        state.peerConnection = peerConnection
        state.readiness = readiness
        lock.unlock()
        return connectionID
    }

    func setDataChannel(_ dataChannel: RTCDataChannel) {
        lock.lock()
        state.dataChannel = dataChannel
        lock.unlock()
    }

    func setLocalAudioTrack(_ audioTrack: RTCAudioTrack) {
        audioTrack.isEnabled = true
        lock.lock()
        state.localAudioTrack = audioTrack
        lock.unlock()
    }

    func retainRemoteAudioTracks(_ audioTracks: [RTCAudioTrack]) {
        guard !audioTracks.isEmpty else { return }

        for audioTrack in audioTracks {
            audioTrack.isEnabled = true
        }

        lock.lock()
        state.remoteAudioTracks.append(contentsOf: audioTracks)
        lock.unlock()
    }

    func currentReadiness() -> WebRTCPeerConnectionReadiness? {
        lock.lock()
        let readiness = state.readiness
        lock.unlock()
        return readiness
    }

    func clear() -> State {
        lock.lock()
        let previous = state
        state = State(
            connectionID: nil,
            peerConnection: nil,
            dataChannel: nil,
            localAudioTrack: nil,
            remoteAudioTracks: [],
            readiness: nil
        )
        lock.unlock()
        return previous
    }

    func clearIfActive(_ connectionID: UUID) -> State {
        lock.lock()
        guard state.connectionID == connectionID else {
            lock.unlock()
            return State(
                connectionID: nil,
                peerConnection: nil,
                dataChannel: nil,
                localAudioTrack: nil,
                remoteAudioTracks: [],
                readiness: nil
            )
        }

        let previous = state
        state = State(
            connectionID: nil,
            peerConnection: nil,
            dataChannel: nil,
            localAudioTrack: nil,
            remoteAudioTracks: [],
            readiness: nil
        )
        lock.unlock()
        return previous
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}

// MARK: - RTCPeerConnectionFactory singleton

extension RTCPeerConnectionFactory {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }()

    static func sharedInstance() -> RTCPeerConnectionFactory {
        return factory
    }
}
