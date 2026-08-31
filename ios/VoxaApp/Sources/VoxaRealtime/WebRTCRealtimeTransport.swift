import AVFoundation
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
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var audioTrack: RTCAudioTrack?

    #if os(iOS)
    public init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
        super.init()
    }
    #else
    public override init() {
        super.init()
    }
    #endif

    public func connect(using credential: RealtimeSessionCredential) async throws {
        guard !credential.isExpired() else {
            throw RealtimeTransportError.connectionFailed("Session credential has expired")
        }

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

        guard let pc = RTCPeerConnectionFactory.sharedInstance().peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: nil
        ) else {
            throw RealtimeTransportError.connectionFailed("Failed to create peer connection")
        }
        self.peerConnection = pc

        // Add local audio track from microphone
        try addLocalAudioTrack(to: pc)

        // Create data channel for Realtime events
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = true
        guard let dc = pc.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig) else {
            throw RealtimeTransportError.connectionFailed("Failed to create data channel")
        }
        self.dataChannel = dc

        // Create SDP offer
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true"
            ],
            optionalConstraints: nil
        )

        let offer = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
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

        // Set local description
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(offer) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Send SDP to OpenAI Realtime API and get answer
        let answer = try await exchangeSDP(offer: offer.sdp, clientSecret: credential.clientSecret)

        // Set remote description
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: answer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(remoteDescription) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Wait for connection to be established (simplified - production would track state)
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds for ICE to complete
    }

    public func disconnect() async {
        dataChannel?.close()
        dataChannel = nil

        peerConnection?.close()
        peerConnection = nil

        audioTrack = nil

        #if os(iOS)
        // Deactivate audio session
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Private helpers

    private func configureAudioSession() throws {
        #if os(iOS)
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
        #endif
    }

    private func addLocalAudioTrack(to pc: RTCPeerConnection) throws {
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = RTCPeerConnectionFactory.sharedInstance().audioSource(with: audioConstraints)
        let audioTrack = RTCPeerConnectionFactory.sharedInstance().audioTrack(with: audioSource, trackId: "audio0")

        pc.add(audioTrack, streamIds: ["stream0"])
        self.audioTrack = audioTrack
    }

    private func exchangeSDP(offer: String, clientSecret: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/realtime/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = offer.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RealtimeTransportError.connectionFailed("Invalid response from OpenAI")
        }

        guard httpResponse.statusCode == 200 else {
            throw RealtimeTransportError.connectionFailed("OpenAI returned status \(httpResponse.statusCode)")
        }

        guard let answerSDP = String(data: data, encoding: .utf8) else {
            throw RealtimeTransportError.connectionFailed("Invalid SDP answer from OpenAI")
        }

        return answerSDP
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
