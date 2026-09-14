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
            ?? SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechQuestionCaptureError.unavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        latestTranscript = ""

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard error == nil, let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in
                self?.latestTranscript = text
                onPartialTranscript(text)
            }
        }

        try AVAudioSession.sharedInstance().setCategory(.record, mode: .spokenAudio, options: [.duckOthers])
        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        engine.prepare()
        try engine.start()

        audioEngine = engine
        recognitionRequest = request
    }

    public func stop() async throws -> String {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
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
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        latestTranscript = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
}
#endif
