#if canImport(SwiftUI)
import SwiftUI
import VoxaPractice

#if canImport(PhotosUI)
import PhotosUI
#endif

#if os(iOS) && canImport(UIKit)
import UIKit
#endif

struct VocabularyQuizView: View {
    let model: PracticeLanguageToolViewModel
    let targetLanguage: String
    let proficiencyBand: String
    let defaultFocus: String?
    @State private var focus = ""

    var body: some View {
        List {
            Section {
                TextField("Focus", text: $focus, prompt: Text(defaultFocus ?? "Everyday vocabulary"))
                Button {
                    Task { await loadQuiz() }
                } label: {
                    Label("Generate test", systemImage: "checklist")
                }
                .disabled(model.isLoading)
            }
            if let quiz = model.vocabularyQuiz {
                Section {
                    ForEach(quiz.items) { item in
                        VocabularyQuizItemView(item: item, model: model)
                    }
                }
            }
            statusSection
        }
        .navigationTitle("Vocabulary test")
        .task {
            if model.vocabularyQuiz == nil {
                await loadQuiz()
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isLoading {
            Section { ProgressView("Working...") }
        } else if let error = model.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
        }
    }

    private func loadQuiz() async {
        await model.loadVocabularyQuiz(
            targetLanguage: targetLanguage,
            proficiencyBand: proficiencyBand,
            focus: focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultFocus : focus)
    }
}

private struct VocabularyQuizItemView: View {
    let item: VocabularyQuizItem
    let model: PracticeLanguageToolViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.prompt)
                .font(.headline)
            ForEach(Array(item.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    model.selectAnswer(index, for: item)
                } label: {
                    HStack {
                        Image(systemName: symbol(for: index))
                            .foregroundStyle(color(for: index))
                        Text(choice)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vocabulary-choice-\(index)")
            }
            if let isCorrect = model.isCorrect(item) {
                Text(isCorrect ? "Correct. \(item.explanation)" : "Not quite. \(item.explanation)")
                    .font(.caption)
                    .foregroundStyle(isCorrect ? .green : .orange)
            }
        }
        .padding(.vertical, 6)
    }

    private func symbol(for index: Int) -> String {
        guard let selected = model.selectedAnswers[item.id] else {
            return "circle"
        }
        if index == selected {
            return selected == item.correctChoiceIndex ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        if index == item.correctChoiceIndex {
            return "checkmark.circle"
        }
        return "circle"
    }

    private func color(for index: Int) -> Color {
        guard let selected = model.selectedAnswers[item.id] else {
            return .secondary
        }
        if index == selected {
            return selected == item.correctChoiceIndex ? .green : .orange
        }
        if index == item.correctChoiceIndex {
            return .green
        }
        return .secondary
    }
}

struct AskAnythingView: View {
    let model: PracticeLanguageToolViewModel
    let targetLanguage: String
    let nativeLanguage: String?
    @State private var question = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $question)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("ask-anything-question")
                Button {
                    Task {
                        await model.askAnything(
                            question: question,
                            targetLanguage: targetLanguage,
                            nativeLanguage: nativeLanguage)
                    }
                } label: {
                    Label("Ask Voxa", systemImage: "questionmark.bubble")
                }
                .disabled(model.isLoading || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    Task { await toggleVoiceQuestion() }
                } label: {
                    Label(voiceQuestionButtonTitle, systemImage: voiceQuestionButtonSymbol)
                }
                .disabled(model.isLoading || model.speechQuestionState == .requestingPermission || model.speechQuestionState == .transcribing)
                if !model.spokenQuestionDraft.isEmpty {
                    Text(model.spokenQuestionDraft)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let result = model.askResult {
                Section("Answer") {
                    Text(result.answer)
                    ForEach(result.examples) { example in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example.target).font(.headline)
                            if !example.source.isEmpty {
                                Text(example.source).foregroundStyle(.secondary)
                            }
                            if !example.note.isEmpty {
                                Text(example.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            statusSection
        }
        .navigationTitle("Ask anything")
        .onChange(of: model.spokenQuestionDraft) { _, transcript in
            if model.isRecordingQuestion {
                question = transcript
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isLoading {
            Section { ProgressView("Working...") }
        } else if let error = model.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
        } else if case let .failed(message) = model.speechQuestionState {
            Section { Text(message).foregroundStyle(.red) }
        } else if model.speechQuestionState == .requestingPermission {
            Section { ProgressView("Preparing microphone...") }
        } else if model.speechQuestionState == .transcribing {
            Section { ProgressView("Transcribing...") }
        }
    }

    private var voiceQuestionButtonTitle: String {
        model.isRecordingQuestion ? "Stop and ask" : "Ask by voice"
    }

    private var voiceQuestionButtonSymbol: String {
        model.isRecordingQuestion ? "stop.circle.fill" : "mic.circle"
    }

    private func toggleVoiceQuestion() async {
        if model.isRecordingQuestion {
            guard let transcript = await model.stopVoiceQuestionInput() else { return }
            question = transcript
            await model.askAnything(
                question: transcript,
                targetLanguage: targetLanguage,
                nativeLanguage: nativeLanguage)
        } else {
            await model.startVoiceQuestionInput(
                localeIdentifier: speechLocaleIdentifier(for: nativeLanguage ?? Locale.current.localizedString(forIdentifier: Locale.current.identifier)))
        }
    }
}

struct TranslationToolView: View {
    let model: PracticeLanguageToolViewModel
    let targetLanguage: String
    @State private var sourceLanguage = ""
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextField("Source language", text: $sourceLanguage, prompt: Text("Detect automatically"))
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .accessibilityIdentifier("translation-text")
                Button {
                    Task {
                        await model.translate(
                            text: text,
                            sourceLanguage: trimmed(sourceLanguage),
                            targetLanguage: targetLanguage)
                    }
                } label: {
                    Label("Translate", systemImage: "character.bubble")
                }
                .disabled(model.isLoading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    Task { await toggleVoiceTranslation() }
                } label: {
                    Label(voiceTranslationButtonTitle, systemImage: voiceTranslationButtonSymbol)
                }
                .disabled(model.isLoading || model.speechQuestionState == .requestingPermission || model.speechQuestionState == .transcribing)
                if !model.spokenQuestionDraft.isEmpty {
                    Text(model.spokenQuestionDraft)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let result = model.translationResult {
                Section("Translation") {
                    Text(result.translatedText)
                        .font(.title3)
                    Text("\(result.sourceLanguage) -> \(result.targetLanguage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !result.notes.isEmpty {
                        Text(result.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            statusSection
        }
        .navigationTitle("Translate")
        .onChange(of: model.spokenQuestionDraft) { _, transcript in
            if model.isRecordingQuestion {
                text = transcript
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isLoading {
            Section { ProgressView("Working...") }
        } else if let error = model.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
        } else if case let .failed(message) = model.speechQuestionState {
            Section { Text(message).foregroundStyle(.red) }
        } else if model.speechQuestionState == .requestingPermission {
            Section { ProgressView("Preparing microphone...") }
        } else if model.speechQuestionState == .transcribing {
            Section { ProgressView("Transcribing...") }
        }
    }

    private var voiceTranslationButtonTitle: String {
        model.isRecordingQuestion ? "Stop and translate" : "Translate by voice"
    }

    private var voiceTranslationButtonSymbol: String {
        model.isRecordingQuestion ? "stop.circle.fill" : "mic.circle"
    }

    private func toggleVoiceTranslation() async {
        if model.isRecordingQuestion {
            guard let transcript = await model.stopVoiceQuestionInput() else { return }
            text = transcript
            await model.translate(
                text: transcript,
                sourceLanguage: trimmed(sourceLanguage),
                targetLanguage: targetLanguage)
        } else {
            await model.startVoiceQuestionInput(localeIdentifier: speechLocaleIdentifier(for: trimmed(sourceLanguage)))
        }
    }
}

struct ImageTranslationToolView: View {
    let model: PracticeLanguageToolViewModel
    let targetLanguage: String
    @State private var sourceLanguage = ""
    @State private var imageData: Data?
    @State private var mimeType = "image/jpeg"
    @State private var isShowingCamera = false

    #if canImport(PhotosUI)
    @State private var selectedPhoto: PhotosPickerItem?
    #endif

    var body: some View {
        Form {
            Section {
                TextField("Source language", text: $sourceLanguage, prompt: Text("Detect automatically"))
                #if os(iOS) && canImport(UIKit)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                }
                #endif
                #if canImport(PhotosUI)
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose photo", systemImage: "photo")
                }
                #endif
                Button {
                    Task { await translateImage() }
                } label: {
                    Label("Translate image", systemImage: "camera.viewfinder")
                }
                .disabled(model.isLoading || imageData == nil)
            }
            if let imageTranslation = model.imageTranslationResult {
                Section("Detected text") {
                    Text(imageTranslation.detectedText)
                }
                Section("Translation") {
                    Text(imageTranslation.translatedText)
                        .font(.title3)
                    Text("\(imageTranslation.sourceLanguage) -> \(imageTranslation.targetLanguage)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !imageTranslation.notes.isEmpty {
                        Text(imageTranslation.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            statusSection
        }
        .navigationTitle("Image translate")
        #if os(iOS) && canImport(UIKit)
        .sheet(isPresented: $isShowingCamera) {
            CameraCaptureView { data in
                imageData = data
                mimeType = "image/jpeg"
                isShowingCamera = false
            }
        }
        #endif
        #if canImport(PhotosUI)
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
        #endif
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isLoading {
            Section { ProgressView("Working...") }
        } else if let error = model.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
        } else if imageData != nil {
            Section { Label("Image ready", systemImage: "checkmark.circle") }
        }
    }

    private func translateImage() async {
        guard let imageData else { return }
        await model.translateImage(
            imageBase64: imageData.base64EncodedString(),
            mimeType: mimeType,
            sourceLanguage: trimmed(sourceLanguage),
            targetLanguage: targetLanguage)
    }

    #if canImport(PhotosUI)
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            imageData = data
            mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
        }
    }
    #endif
}

private func trimmed(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func speechLocaleIdentifier(for language: String?) -> String {
    guard let language else { return Locale.current.identifier }
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "arabic": return "ar-SA"
    case "chinese", "mandarin": return "zh-Hans"
    case "dutch": return "nl-NL"
    case "english": return "en-US"
    case "french": return "fr-FR"
    case "german": return "de-DE"
    case "italian": return "it-IT"
    case "japanese": return "ja-JP"
    case "korean": return "ko-KR"
    case "portuguese": return "pt-PT"
    case "spanish": return "es-ES"
    default: return Locale.current.identifier
    }
}

#if os(iOS) && canImport(UIKit)
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onImageData: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageData: onImageData)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImageData: (Data) -> Void

        init(onImageData: @escaping (Data) -> Void) {
            self.onImageData = onImageData
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.82) {
                onImageData(data)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif
#endif
