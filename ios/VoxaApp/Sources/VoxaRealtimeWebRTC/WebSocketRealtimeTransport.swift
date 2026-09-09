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
    // Single-loop handshake dispatch: the receive loop starts before we send
    // any handshake message. Callers waiting for a specific setup event
    // (session.created / session.updated) register here; the loop resumes
    // them when their event arrives — and never discards unrelated events.
    private let handshakeLock = NSLock()
    private var handshakeWaiters: [String: HandshakeContinuation] = [:]
    // The engine + player pair is a long-lived AVAudioEngine graph — attaching
    // an already-attached node raises an ObjC NSInternalInconsistencyException
    // that Swift can't catch and crashes the app. Every connect() flows through
    // configureAudio(), so we track "have we attached yet" and only wire the
    // graph on the FIRST connect. Reconnects (start → end → start on the same
    // TalkSessionViewModel-owned transport instance) reuse the same graph.
    //
    // These live outside the #if os(iOS) block so a macOS test host can
    // exercise the idempotency guard directly — the AVFoundation APIs used
    // here are available on both platforms; only the AVAudioSession path
    // stays iOS-only.
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    internal private(set) var audioPipelineConfigured = false
    private static let playbackFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    #if os(iOS)
    private var inputConverter: AVAudioConverter?
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
        // Start the single receive loop BEFORE any handshake step. All events
        // — including session.created / session.updated — flow through it;
        // waiters register interest via handshakeWaiters. The previous
        // per-step readUntilServerEvent silently dropped everything that
        // wasn't the exact type it wanted, which risked losing rate-limit or
        // early state events emitted around session setup.
        receiveLoop(socket)
        try await waitForHandshakeEvent("session.created")
        // Server sets these fields at client_secret mint time too, but observed
        // behaviour is that OpenAI's /v1/realtime/client_secrets endpoint
        // silently discards the audio.turn_detection block — the WebSocket
        // then falls back to defaults (create_response: true) and the tutor
        // auto-generates forever. session.update DOES land, so we re-send the
        // authoritative config here. Tampering vector tracked in issue #100.
        try await sendSessionUpdate(on: socket)
        try await waitForHandshakeEvent("session.updated")
        #if os(iOS)
        try startMicrophone(on: engine.inputNode)
        #endif
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
        failAllHandshakeWaiters(
            RealtimeTransportError.connectionFailed("Session disconnected before handshake completed."))
        assistantStateLock.lock()
        pendingPlaybackEnd = 0
        expectedResponses = 0
        assistantStateLock.unlock()
        #if os(iOS)
        engine.stop()
        player.stop()
        engine.inputNode.removeTap(onBus: 0)
        inputConverter = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        // Deliberately DO NOT detach player or clear audioPipelineConfigured —
        // the engine graph survives the session boundary so the next connect()
        // can restart the same nodes safely.
        #endif
    }

    /// Suspends until the single receive loop sees an event of the given type,
    /// or the timeout fires. Unlike the previous `readUntilServerEvent`, this
    /// does NOT consume the socket directly, so events that arrive between
    /// handshake steps are still delivered to the loop's normal handlers
    /// instead of being silently dropped.
    private func waitForHandshakeEvent(_ eventType: String, timeoutSeconds: TimeInterval = 10) async throws {
        let waiter = HandshakeContinuation()
        handshakeLock.lock()
        handshakeWaiters[eventType] = waiter
        handshakeLock.unlock()

        defer {
            handshakeLock.lock()
            _ = handshakeWaiters.removeValue(forKey: eventType)
            handshakeLock.unlock()
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    waiter.attach(cont)
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                let error = RealtimeTransportError.connectionFailed(
                    "Timed out waiting for OpenAI Realtime event \(eventType).")
                // Resolve the waiter first (unblocks the sibling task) AND
                // throw from this task — otherwise if group.next() returns
                // this task's Void completion before the sibling propagates
                // its throw, waitForHandshakeEvent would return successfully
                // on a timeout.
                waiter.fail(error)
                throw error
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Called by the receive loop for every parsed event. Wakes any handshake
    /// waiter interested in this event type, and short-circuits every waiter
    /// on a fatal server error.
    private func notifyHandshake(event type: String, object: [String: Any]) {
        if type == "error" {
            let error = object["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "OpenAI rejected the Realtime session."
            failAllHandshakeWaiters(RealtimeTransportError.connectionFailed(message))
            return
        }
        handshakeLock.lock()
        let waiter = handshakeWaiters.removeValue(forKey: type)
        handshakeLock.unlock()
        waiter?.succeed()
    }

    /// Fails every pending handshake waiter — used when the socket closes or
    /// the receive loop errors out before the handshake completes.
    private func failAllHandshakeWaiters(_ error: Error) {
        handshakeLock.lock()
        let waiters = handshakeWaiters
        handshakeWaiters.removeAll()
        handshakeLock.unlock()
        for (_, waiter) in waiters { waiter.fail(error) }
    }

    /// Single-shot continuation wrapper with a terminal-state memory so
    /// `succeed()` / `fail()` are safe when called BEFORE `attach()`.
    ///
    /// The dispatcher publishes the waiter into `handshakeWaiters` before the
    /// child task that owns the continuation gets a chance to run and attach
    /// it. If the receive loop reads a matching event in that gap and calls
    /// `succeed()`, the previous "just store the continuation" design would
    /// no-op (continuation still nil) and later `attach()` would stash a
    /// continuation nobody ever resumes — the caller would hang until the
    /// 10 s timeout. This state machine records the terminal decision so
    /// `attach()` can honour a resolution that already happened.
    ///
    /// `internal` so @testable importers can exercise both orderings directly.
    internal final class HandshakeContinuation: @unchecked Sendable {
        private let lock = NSLock()
        private enum State {
            case pending
            case waiting(CheckedContinuation<Void, Error>)
            case earlySuccess
            case earlyFailure(Error)
            case done
        }
        private var state: State = .pending

        func attach(_ cont: CheckedContinuation<Void, Error>) {
            lock.lock()
            switch state {
            case .pending:
                state = .waiting(cont)
                lock.unlock()
            case .earlySuccess:
                state = .done
                lock.unlock()
                cont.resume()
            case .earlyFailure(let error):
                state = .done
                lock.unlock()
                cont.resume(throwing: error)
            case .waiting, .done:
                // attach called twice, or after resolution. Resume the new
                // continuation immediately so its owner doesn't hang. Should
                // not happen in current code.
                state = .done
                lock.unlock()
                cont.resume()
            }
        }

        func succeed() {
            lock.lock()
            switch state {
            case .pending:
                state = .earlySuccess
                lock.unlock()
            case .waiting(let cont):
                state = .done
                lock.unlock()
                cont.resume()
            case .earlySuccess, .earlyFailure, .done:
                lock.unlock()
            }
        }

        func fail(_ error: Error) {
            lock.lock()
            switch state {
            case .pending:
                state = .earlyFailure(error)
                lock.unlock()
            case .waiting(let cont):
                state = .done
                lock.unlock()
                cont.resume(throwing: error)
            case .earlySuccess, .earlyFailure, .done:
                lock.unlock()
            }
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

                    // Route every event to any handshake waiters BEFORE the
                    // normal handler. session.created/session.updated wake
                    // their waiters here; unrelated events don't match any
                    // waiter and simply fall through — no events are lost.
                    self.notifyHandshake(event: type, object: object)

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
                // Socket closed or read failed. Any handshake step still
                // waiting on us would otherwise hang until its 10 s timeout;
                // fail them now with the underlying error instead.
                self.failAllHandshakeWaiters(error)
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

    /// Attach the player node to the engine and wire it into the main mixer.
    /// Idempotent: safe to call on every `connect()`; if the graph is already
    /// wired, this is a no-op. Without the guard, the second call would raise
    /// an ObjC `NSInternalInconsistencyException` (`required condition is
    /// false: !nodeimpl->HasEngineImpl()`) that Swift can't catch. `internal`
    /// so @testable importers can verify the idempotency directly.
    internal func configureAudioPipelineIfNeeded() {
        if !audioPipelineConfigured {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.playbackFormat)
            audioPipelineConfigured = true
        }
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
        configureAudioPipelineIfNeeded()
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
        // Use PCM16AudioProcessor.decodeToFloat32 rather than binding Data's
        // raw storage to Int16.self — the storage is not guaranteed to be
        // 2-byte aligned (base64-decoded WebSocket audio often isn't), and a
        // typed load through an unaligned pointer is undefined behaviour.
        let samples = PCM16AudioProcessor.decodeToFloat32(data)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: Self.playbackFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
              ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let destination = buffer.floatChannelData?.pointee else { return }
        for index in 0..<samples.count {
            destination[index] = samples[index]
        }
        player.scheduleBuffer(buffer)
        if !player.isPlaying { player.play() }
    }
    #endif
}
