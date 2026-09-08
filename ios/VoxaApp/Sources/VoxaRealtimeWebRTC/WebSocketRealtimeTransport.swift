import AVFoundation
import Foundation
import VoxaRealtime

/// Realtime WebSocket transport with app-owned audio playback. Unlike the
/// WebRTC transport, the received PCM passes through an explicit gain and
/// limiter before it reaches the speaker.
public final class WebSocketRealtimeTransport: NSObject, RealtimeTransport, @unchecked Sendable {
    private let playbackGain: Float
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    #if os(iOS)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    #endif

    public init(playbackGain: Float = 2.0, session: URLSession = .shared) {
        self.playbackGain = playbackGain
        self.session = session
        super.init()
    }

    public func connect(using credential: RealtimeSessionCredential) async throws {
        guard !credential.isExpired() else {
            throw RealtimeTransportError.connectionFailed("Session credential has expired")
        }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.openai.com"
        components.path = "/v1/realtime"
        components.queryItems = [URLQueryItem(name: "model", value: credential.model)]
        guard let url = components.url else {
            throw RealtimeTransportError.connectionFailed("Invalid Realtime WebSocket URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(credential.clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()

        #if os(iOS)
        try configureAudio()
        #endif
        try await waitForServerEvent(type: "session.created", on: socket)
        try await sendSessionUpdate(credential.settings, on: socket)
        try await waitForServerEvent(type: "session.updated", on: socket)
        #if os(iOS)
        try startMicrophone(on: engine.inputNode)
        #endif
        receiveLoop(socket)
    }

    public func disconnect() async {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        #if os(iOS)
        engine.stop()
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    private func sendSessionUpdate(_ settings: RealtimeCoachingSettings, on socket: URLSessionWebSocketTask) async throws {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "output_modalities": ["audio"],
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24_000],
                        "turn_detection": ["type": "server_vad"]
                    ],
                    "output": ["format": ["type": "audio/pcm"]]
                ],
                "instructions": "Tutor the learner in \(settings.targetLanguage) at level \(settings.proficiencyBand)."
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func waitForServerEvent(type expectedType: String, on socket: URLSessionWebSocketTask) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.readUntilServerEvent(type: expectedType, on: socket) }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw RealtimeTransportError.connectionFailed("Timed out waiting for OpenAI Realtime session.")
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func readUntilServerEvent(type expectedType: String, on socket: URLSessionWebSocketTask) async throws {
        while true {
            let message = try await socket.receive()
            guard case let .string(text) = message,
                  let data = text.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else {
                continue
            }
            if type == "error" {
                let error = object["error"] as? [String: Any]
                let message = error?["message"] as? String ?? "OpenAI rejected the Realtime session."
                throw RealtimeTransportError.connectionFailed(message)
            }
            if type == expectedType { return }
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) {
        Task { [weak self] in
            guard let self else { return }
            do {
                while self.socket === socket {
                    let message = try await socket.receive()
                    guard case let .string(text) = message,
                          let data = text.data(using: .utf8),
                          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = object["type"] as? String,
                          (type == "response.output_audio.delta" || type == "response.audio.delta"),
                          let encoded = object["delta"] as? String,
                          let audio = Data(base64Encoded: encoded)
                    else { continue }
                    #if os(iOS)
                    schedule(audio: PCM16AudioProcessor.amplified(audio, gain: playbackGain))
                    #endif
                }
            } catch {
                return
            }
        }
    }

    #if os(iOS)
    private func configureAudio() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        try audio.overrideOutputAudioPort(.speaker)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
    }

    private func startMicrophone(on input: AVAudioInputNode) throws {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.sendMicrophoneBuffer(buffer)
        }
        try engine.start()
    }

    private func sendMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        var data = Data(capacity: Int(buffer.frameLength) * 2)
        for index in 0..<Int(buffer.frameLength) {
            let sample = Int16(max(-1, min(1, channel[index])) * Float(Int16.max))
            data.append(UInt8(truncatingIfNeeded: sample))
            data.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        let event: [String: Any] = ["type": "input_audio_buffer.append", "audio": data.base64EncodedString()]
        guard let json = try? JSONSerialization.data(withJSONObject: event) else { return }
        Task { try? await socket?.send(.string(String(decoding: json, as: UTF8.self))) }
    }

    private func schedule(audio data: Data) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 2)) else { return }
        buffer.frameLength = buffer.frameCapacity
        data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress, let destination = buffer.int16ChannelData?.pointee else { return }
            destination.assign(from: source.assumingMemoryBound(to: Int16.self), count: Int(buffer.frameLength))
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }
    #endif
}
