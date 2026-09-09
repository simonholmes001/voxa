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
    // Wall-clock time at which the currently-queued tutor audio is expected
    // to finish PLAYING (not just arriving on the socket). Each audio delta
    // advances this by its own PCM duration, so the gate is anchored to what
    // the speaker is actually still emitting, not to a wall-clock timer.
    private var pendingPlaybackEnd: TimeInterval = 0
    // Number of response.create events we've sent but not yet seen echoed
    // back as response.created. If a response.created arrives with this at 0,
    // the SERVER generated a response we didn't ask for — likely because our
    // `create_response: false` wasn't honoured. We cancel those defensively.
    private var expectedResponses: Int = 0
    // 700 ms tail past the estimated playback end — covers hardware audio
    // buffer latency + slack for late deltas after we thought playback ended.
    private static let micGateTailSeconds: TimeInterval = 0.7
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
        // Server sets these fields at client_secret mint time too, but observed
        // behaviour is that OpenAI's /v1/realtime/client_secrets endpoint
        // silently discards the audio.turn_detection block — the WebSocket
        // then falls back to defaults (create_response: true) and the tutor
        // auto-generates forever. session.update DOES land, so we re-send the
        // authoritative config here. Tampering vector tracked in issue #100.
        try await sendSessionUpdate(on: socket)
        try await waitForServerEvent(type: "session.updated", on: socket)
        #if os(iOS)
        try startMicrophone(on: engine.inputNode)
        #endif
        receiveLoop(socket)
        // Turn boundaries: an initial response.create here kicks off the
        // tutor's greeting; receiveLoop sends another response.create when
        // server VAD tells us the learner finished a turn — and only if we
        // aren't currently gating the mic (i.e., the speech_stopped isn't
        // just tutor-echo bleeding into the input path).
        registerRequestedResponse()
        try await sendJSON(["type": "response.create"], on: socket)
    }

    private func sendSessionUpdate(on socket: URLSessionWebSocketTask) async throws {
        // Instructions are intentionally NOT set here — they came from the
        // backend at client_secret mint time and we don't overwrite them.
        // Only the strict turn-taking config, which the mint endpoint drops.
        //
        // Built as a JSON literal because Foundation's JSONSerialization
        // renders Doubles with 17+ decimal digits, which OpenAI rejects with
        // "max decimal places exceeded". Writing the literal ourselves gives
        // us exact control over the number formatting.
        //
        // threshold=0.85: aggressive enough to survive ambient noise picked
        //   up by the .measurement-mode mic (no noise suppression).
        // silence_duration_ms=1500: real thinking time; short mid-answer
        //   hesitation doesn't end the learner's turn.
        // create_response=false / interrupt_response=true: the fields that
        //   make monologue architecturally impossible — the server never
        //   auto-creates a response, and it does cancel the current one if
        //   the learner starts speaking.
        let payload = """
        {"type":"session.update","session":{"type":"realtime","output_modalities":["audio"],"audio":{"input":{"format":{"type":"audio/pcm","rate":24000},"turn_detection":{"type":"server_vad","threshold":0.85,"prefix_padding_ms":300,"silence_duration_ms":1500,"create_response":false,"interrupt_response":true}},"output":{"format":{"type":"audio/pcm","rate":24000}}}}}
        """
        try await socket.send(.string(payload))
    }

    public func interrupt() async {
        // 1. Stop the local player and flush any queued PCM. This is what the
        //    learner physically experiences as "the tutor stopped mid-sentence".
        #if os(iOS)
        player.stop()
        #endif
        // 2. Release the mic gate so the learner's next words reach the server
        //    immediately instead of being blocked by the tutor-audio tail.
        assistantStateLock.lock()
        pendingPlaybackEnd = 0
        assistantStateLock.unlock()
        // 3. Ask the server to stop generating this response. Without this the
        //    server keeps producing tokens (which we bill) that we then drop.
        if let socket {
            try? await sendJSON(["type": "response.cancel"], on: socket)
        }
    }

    public func disconnect() async {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        assistantStateLock.lock()
        pendingPlaybackEnd = 0
        expectedResponses = 0
        assistantStateLock.unlock()
        #if os(iOS)
        engine.stop()
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
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
                        // If we didn't ask for this response, the server
                        // generated it on its own — meaning our
                        // `create_response: false` wasn't honoured. Cancel
                        // the spurious response so the tutor stops mid-flight
                        // instead of monologuing.
                        if self.consumeExpectedResponseIfAny() {
                            self.markAssistantResponseStart()
                        } else {
                            let responseId = object["response"] as? [String: Any]
                            var cancel: [String: Any] = ["type": "response.cancel"]
                            if let id = responseId?["id"] as? String { cancel["response_id"] = id }
                            try? await self.sendJSON(cancel, on: socket)
                        }
                    case "response.output_audio.delta", "response.audio.delta":
                        guard let encoded = object["delta"] as? String,
                              let audio = Data(base64Encoded: encoded) else { continue }
                        let amplified = PCM16AudioProcessor.amplified(audio, gain: self.playbackGain, limit: 32_000)
                        // Anchor the mic gate to the summed PCM duration of
                        // what's been queued for playback, not to wall-clock.
                        let durationSeconds = Double(amplified.count / 2) / 24_000
                        self.extendPendingPlayback(bySeconds: durationSeconds)
                        #if os(iOS)
                        self.schedule(audio: amplified)
                        #endif
                    case "input_audio_buffer.speech_stopped":
                        // Server VAD said "a user turn ended". If the mic
                        // gate is currently ACTIVE, this was almost certainly
                        // tutor audio bleeding through the speaker → mic path
                        // (no headphones, no VP-IO echo cancellation) —
                        // creating a response for it would start the tutor
                        // talking to itself. Only create a response when we
                        // know it was a real learner turn.
                        guard !self.shouldGateMic() else { break }
                        self.registerRequestedResponse()
                        try? await self.sendJSON(["type": "response.create"], on: socket)
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

    /// Advances the expected end-of-playback time by the duration of one
    /// audio delta. Deltas arrive faster on the socket than they play through
    /// the speaker, so a time-since-last-delta gate opens too early. Anchoring
    /// to the summed PCM duration is what actually tracks the speaker.
    private func extendPendingPlayback(bySeconds seconds: Double) {
        assistantStateLock.lock()
        let now = Date().timeIntervalSince1970
        let playbackStart = max(pendingPlaybackEnd, now)
        pendingPlaybackEnd = playbackStart + seconds
        assistantStateLock.unlock()
    }

    /// Bumps the gate by a small floor when a response starts, in case
    /// there is a brief delay before the first audio delta arrives.
    private func markAssistantResponseStart() {
        assistantStateLock.lock()
        let now = Date().timeIntervalSince1970
        pendingPlaybackEnd = max(pendingPlaybackEnd, now + 0.3)
        assistantStateLock.unlock()
    }

    private func shouldGateMic() -> Bool {
        assistantStateLock.lock()
        let end = pendingPlaybackEnd
        assistantStateLock.unlock()
        guard end > 0 else { return false }
        return Date().timeIntervalSince1970 < end + Self.micGateTailSeconds
    }

    /// Registers our intent to create a response. `response.created` events
    /// that don't consume one of these are treated as server-side spurious
    /// generations and cancelled.
    private func registerRequestedResponse() {
        assistantStateLock.lock()
        expectedResponses += 1
        assistantStateLock.unlock()
    }

    /// Consumes one pending expected response if any. Returns true if the
    /// arriving `response.created` matched one we requested.
    private func consumeExpectedResponseIfAny() -> Bool {
        assistantStateLock.lock()
        defer { assistantStateLock.unlock() }
        if expectedResponses > 0 {
            expectedResponses -= 1
            return true
        }
        return false
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
