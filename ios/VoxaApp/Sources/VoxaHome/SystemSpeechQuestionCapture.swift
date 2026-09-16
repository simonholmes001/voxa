import Foundation

#if os(iOS)
import AVFoundation
import Speech

@MainActor
public final class SystemSpeechQuestionCapture: SpeechQuestionCapture {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var hasInstalledTap = false

    public init() {}

    public func start(
        localeIdentifier: String,
        onPartialTranscript: @escaping @MainActor (String) -> Void
    ) async throws {
        cancel()

        guard await requestSpeechRecognitionPermission(),
              await requestMicrophonePermission() else {
            throw SpeechQuestionCaptureError.permissionDenied
        }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechQuestionCaptureError.unavailable
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            latestTranscript = ""

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechQuestionCaptureError.startFailed("Voice input could not start because no microphone input was available.")
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasInstalledTap = true

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard error == nil, let text = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in
                    self?.latestTranscript = text
                    onPartialTranscript(text)
                }
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            recognitionRequest = request
        } catch let error as SpeechQuestionCaptureError {
            cancel()
            throw error
        } catch {
            cancel()
            throw SpeechQuestionCaptureError.startFailed(Self.startFailureMessage(for: error))
        }
    }

    public func stop() async throws -> String {
        audioEngine?.stop()
        removeTapIfNeeded()
        recognitionRequest?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        try? await Task.sleep(nanoseconds: 450_000_000)
        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil

        guard !transcript.isEmpty else {
            throw SpeechQuestionCaptureError.recognitionFailed
        }
        return transcript
    }

    public func cancel() {
        audioEngine?.stop()
        removeTapIfNeeded()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        latestTranscript = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func removeTapIfNeeded() {
        guard hasInstalledTap else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        hasInstalledTap = false
    }

    private func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private static func startFailureMessage(for error: Error) -> String {
        let description = (error as NSError).localizedDescription
        guard !description.isEmpty else {
            return "Voice input could not start. Please try again."
        }
        return "Voice input could not start: \(description)"
    }
}
#endif
