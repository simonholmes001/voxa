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
    private let assistantStateLock = NSLock()
    private var lastAssistantSpeechTime: TimeInterval = 0
    private static let micGateTailSeconds: TimeInterval = 0.5
    #if os(iOS)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var inputConverter: AVAudioConverter?
    private static let playbackFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    #endif

    public init(playbackGain: Float = 3.0, session: URLSession = .shared) {
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
        // No OpenAI-Beta header — the Realtime beta is no longer accepted; the
        // GA API is served at /v1/realtime when the beta signal is absent.
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
        assistantStateLock.lock()
        lastAssistantSpeechTime = 0
        assistantStateLock.unlock()
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
                        // Raise threshold and silence duration: the tutor's own
                        // audio leaking through the speaker → mic path was
                        // triggering false end-of-turn events, which both cut
                        // the tutor mid-sentence and drove endless auto-replies.
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.75,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": 700,
                            "create_response": true,
                            "interrupt_response": true
                        ]
                    ],
                    "output": ["format": ["type": "audio/pcm", "rate": 24_000]]
                ],
                "instructions": tutorInstructions(for: settings)
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func tutorInstructions(for settings: RealtimeCoachingSettings) -> String {
        """
        You are a friendly conversational language tutor helping the learner \
        practise \(settings.targetLanguage) at level \(settings.proficiencyBand).

        Turn-taking rules — follow them strictly:
        - Say ONE or TWO short sentences, then STOP and wait for the learner to reply.
        - Never monologue or string multiple ideas together in one turn.
        - After you speak, do not start again until the learner has responded.
        - If the learner is silent, ask a single short question and wait.
        - Speak primarily in \(settings.targetLanguage), keeping vocabulary appropriate for their level.
        - Correct mistakes gently and briefly.
        """
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
                          let type = object["type"] as? String
                    else { continue }

                    switch type {
                    case "response.created":
                        // Mark the assistant as speaking and purge any mic
                        // audio the server has been accumulating. That audio
                        // is almost certainly the tutor's own echo — letting
                        // it commit would look to the server like a real
                        // "user turn" and immediately trigger another reply.
                        self.markAssistantSpeech()
                        try? await self.sendJSON(["type": "input_audio_buffer.clear"], on: socket)
                    case "response.output_audio.delta", "response.audio.delta":
                        self.markAssistantSpeech()
                        guard let encoded = object["delta"] as? String,
                              let audio = Data(base64Encoded: encoded) else { continue }
                        #if os(iOS)
                        self.schedule(audio: PCM16AudioProcessor.amplified(audio, gain: self.playbackGain, limit: 32_000))
                        #endif
                    default:
                        break
                    }
                }
            } catch {
                return
            }
        }
    }

    private func sendJSON(_ payload: [String: Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    /// Records the moment we last saw assistant audio (or the start of a new
    /// response). Used by `shouldGateMic()` to keep the mic muted while the
    /// tutor speaks, plus a short tail so the last buffered audio can drain
    /// before we start streaming mic again.
    private func markAssistantSpeech() {
        assistantStateLock.lock()
        lastAssistantSpeechTime = Date().timeIntervalSince1970
        assistantStateLock.unlock()
    }

    private func shouldGateMic() -> Bool {
        assistantStateLock.lock()
        let last = lastAssistantSpeechTime
        assistantStateLock.unlock()
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < Self.micGateTailSeconds
    }

    #if os(iOS)
    private func configureAudio() throws {
        let audio = AVAudioSession.sharedInstance()
        // .measurement bypasses Voice-Processing I/O entirely — no output AGC,
        // no echo cancellation — which gives the tutor its full loudness. We
        // don't need iOS's echo cancellation because the mic is client-gated
        // during assistant speech (see shouldGateMic), so the tutor can't
        // hear itself no matter how loud the speaker is.
        try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setActive(true)
        try audio.overrideOutputAudioPort(.speaker)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.playbackFormat)
    }

    private func startMicrophone(on input: AVAudioInputNode) throws {
        let format = input.outputFormat(forBus: 0)
        inputConverter = AVAudioConverter(
            from: format,
            to: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        )
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.sendMicrophoneBuffer(buffer)
        }
        try engine.start()
    }

    private func sendMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        // Drop mic frames while (and briefly after) the tutor is speaking.
        // Otherwise the tutor's own audio leaks back through the mic and the
        // server VAD treats it as a "user turn", cutting the tutor off and
        // firing another reply — the exact pattern of choppy playback and
        // reverting-to-monologue that first-turn works, subsequent ones don't.
        guard !shouldGateMic() else { return }
        let source: AVAudioPCMBuffer
        if let inputConverter,
           let converted = AVAudioPCMBuffer(
               pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!,
               frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 24_000 / buffer.format.sampleRate + 1)
           ) {
            var conversionError: NSError?
            var supplied = false
            inputConverter.convert(to: converted, error: &conversionError) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard conversionError == nil else { return }
            source = converted
        } else {
            source = buffer
        }
        guard let channel = source.floatChannelData?.pointee else { return }
        var data = Data(capacity: Int(source.frameLength) * 2)
        for index in 0..<Int(source.frameLength) {
            let sample = Int16(max(-1, min(1, channel[index])) * Float(Int16.max))
            data.append(UInt8(truncatingIfNeeded: sample))
            data.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        let event: [String: Any] = ["type": "input_audio_buffer.append", "audio": data.base64EncodedString()]
        guard let json = try? JSONSerialization.data(withJSONObject: event) else { return }
        Task { try? await socket?.send(.string(String(decoding: json, as: UTF8.self))) }
    }

    private func schedule(audio data: Data) {
        // The player node was connected to the mixer with Float32; scheduled
        // buffers must match that format or Core Audio silently drops them.
        // Convert the amplified Int16 PCM to Float32 in-place while copying.
        let frameCount = data.count / 2
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: Self.playbackFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let scale = 1.0 / Float(Int16.max)
        data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let destination = buffer.floatChannelData?.pointee else { return }
            for index in 0..<frameCount {
                destination[index] = Float(source[index]) * scale
            }
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }
    #endif
}
