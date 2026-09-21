#if canImport(SwiftUI)
import SwiftUI
import VoxaPractice

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(AVFoundation)
import AVFoundation
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
    @State private var sourceLanguageOption: TranslationLanguageOption
    @State private var sourceCustomLanguage = ""
    @State private var targetLanguageOption: TranslationLanguageOption
    @State private var targetCustomLanguage = ""
    @State private var text = ""
    @State private var speechAlertMessage: String?
    @FocusState private var focusedField: TranslationInputField?

    #if canImport(AVFoundation)
    @State private var speechPlayer = TranslationSpeechPlayer()
    #endif

    init(model: PracticeLanguageToolViewModel, targetLanguage: String, nativeLanguage: String? = nil) {
        self.model = model
        let source = TranslationLanguageOption.option(for: nativeLanguage, allowsAutomatic: true)
        let target = TranslationLanguageOption.option(for: targetLanguage, allowsAutomatic: false)
        _sourceLanguageOption = State(initialValue: source.option)
        _sourceCustomLanguage = State(initialValue: source.customLanguage)
        _targetLanguageOption = State(initialValue: target.option)
        _targetCustomLanguage = State(initialValue: target.customLanguage)
    }

    var body: some View {
        Form {
            Section("Languages") {
                sourceLanguagePicker
                if sourceLanguageOption == .custom {
                    TextField("Source language", text: $sourceCustomLanguage)
                        .focused($focusedField, equals: .sourceLanguage)
                        .submitLabel(.done)
                        .onSubmit { dismissInputs() }
                        .accessibilityIdentifier("translation-source-custom-language")
                }
                Button(action: swapLanguages) {
                    Label("Swap languages", systemImage: "arrow.up.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("translation-swap-languages")
                targetLanguagePicker
                if targetLanguageOption == .custom {
                    TextField("Target language", text: $targetCustomLanguage)
                        .focused($focusedField, equals: .targetLanguage)
                        .submitLabel(.done)
                        .onSubmit { dismissInputs() }
                        .accessibilityIdentifier("translation-target-custom-language")
                }
            }

            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 140)
                    .focused($focusedField, equals: .text)
                    .accessibilityIdentifier("translation-text")
                HStack {
                    Button {
                        dismissInputs()
                        Task {
                            await model.translate(
                                text: text,
                                sourceLanguage: resolvedSourceLanguage,
                                targetLanguage: resolvedTargetLanguage)
                        }
                    } label: {
                        if model.isLoading {
                            Label {
                                Text("Translating...")
                            } icon: {
                                ProgressView()
                            }
                        } else {
                            Label("Translate", systemImage: "character.bubble")
                        }
                    }
                    .disabled(model.isLoading || !canTranslate)
                    .buttonStyle(.borderedProminent)
                    Spacer(minLength: 0)
                }
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
                    #if canImport(AVFoundation)
                    Button {
                        speak(result.translatedText, language: result.targetLanguage)
                    } label: {
                        Label("Play translation", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("translation-play-audio")
                    #endif
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
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissInputs() }
                    .fontWeight(.semibold)
            }
        }
        #endif
        .alert(
            "Voice playback unavailable",
            isPresented: Binding(
                get: { speechAlertMessage != nil },
                set: { if !$0 { speechAlertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(speechAlertMessage ?? "")
        }
        .onChange(of: model.spokenQuestionDraft) { _, transcript in
            if model.isRecordingQuestion {
                text = transcript
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if model.isLoading {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Translating...")
                }
            }
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
        model.isRecordingQuestion ? "Stop and translate" : "Use voice"
    }

    private var voiceTranslationButtonSymbol: String {
        model.isRecordingQuestion ? "stop.circle.fill" : "mic.circle"
    }

    private func toggleVoiceTranslation() async {
        if model.isRecordingQuestion {
            guard let transcript = await model.stopVoiceQuestionInput() else { return }
            text = transcript
            dismissInputs()
            await model.translate(
                text: transcript,
                sourceLanguage: resolvedSourceLanguage,
                targetLanguage: resolvedTargetLanguage)
        } else {
            dismissInputs()
            await model.startVoiceQuestionInput(localeIdentifier: speechLocaleIdentifier(for: resolvedSourceLanguage))
        }
    }

    private func dismissInputs() {
        focusedField = nil
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private var sourceLanguagePicker: some View {
        Picker("From", selection: $sourceLanguageOption) {
            Text("Detect automatically").tag(TranslationLanguageOption.automatic)
            ForEach(TranslationLanguageOption.commonLanguages) { language in
                Text(language.name).tag(TranslationLanguageOption.language(language.name))
            }
            Text("Other...").tag(TranslationLanguageOption.custom)
        }
    }

    private var targetLanguagePicker: some View {
        Picker("To", selection: $targetLanguageOption) {
            ForEach(TranslationLanguageOption.commonLanguages) { language in
                Text(language.name).tag(TranslationLanguageOption.language(language.name))
            }
            Text("Other...").tag(TranslationLanguageOption.custom)
        }
    }

    private func swapLanguages() {
        let fallbackTarget = TranslationLanguageOption.option(
            for: Locale.current.language.languageCode?.identifier,
            allowsAutomatic: false)
        let swapped = TranslationLanguageOption.swapped(
            source: (sourceLanguageOption, sourceCustomLanguage),
            target: (targetLanguageOption, targetCustomLanguage),
            automaticTargetFallback: fallbackTarget)
        sourceLanguageOption = swapped.source.option
        sourceCustomLanguage = swapped.source.customLanguage
        targetLanguageOption = swapped.target.option
        targetCustomLanguage = swapped.target.customLanguage
    }

    private var resolvedSourceLanguage: String? {
        switch sourceLanguageOption {
        case .automatic:
            return nil
        case let .language(name):
            return name
        case .custom:
            return trimmed(sourceCustomLanguage)
        }
    }

    private var resolvedTargetLanguage: String {
        switch targetLanguageOption {
        case .automatic:
            return "English"
        case let .language(name):
            return name
        case .custom:
            return trimmed(targetCustomLanguage) ?? ""
        }
    }

    private var canTranslate: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !resolvedTargetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    #if canImport(AVFoundation)
    private func speak(_ text: String, language: String) {
        do {
            try speechPlayer.speak(text, languageIdentifier: speechLocaleIdentifier(for: language), languageName: language)
        } catch {
            speechAlertMessage = TranslationSpeechPlayer.message(for: error, languageName: language)
        }
    }
    #endif
}

private enum TranslationInputField: Hashable {
    case sourceLanguage
    case targetLanguage
    case text
}

#if canImport(AVFoundation)
@MainActor
private final class TranslationSpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()

    enum SpeechError: Error {
        case unsupportedLanguage
    }

    func speak(_ text: String, languageIdentifier: String, languageName: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let voice = AVSpeechSynthesisVoice(language: languageIdentifier) else {
            throw SpeechError.unsupportedLanguage
        }

        #if os(iOS)
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
        #endif

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    static func message(for error: Error, languageName: String) -> String {
        switch error {
        case SpeechError.unsupportedLanguage:
            return "This device does not have a voice installed for \(languageName). Voxa can still show the translation as text."
        default:
            return "Voxa could not play this translation aloud. Please try again."
        }
    }
}
#endif

enum TranslationLanguageOption: Hashable {
    case automatic
    case language(String)
    case custom

    struct CommonLanguage: Identifiable {
        let name: String
        var id: String { name }
    }

    static let commonLanguages: [CommonLanguage] = [
        "Arabic",
        "Chinese",
        "Dutch",
        "English",
        "French",
        "German",
        "Hindi",
        "Greek",
        "Italian",
        "Japanese",
        "Korean",
        "Portuguese",
        "Spanish"
    ].map(CommonLanguage.init(name:))

    static func option(
        for language: String?,
        allowsAutomatic: Bool
    ) -> (option: TranslationLanguageOption, customLanguage: String) {
        let displayName = displayName(for: language)
        guard !displayName.isEmpty else {
            return (allowsAutomatic ? .automatic : .language("English"), "")
        }
        if commonLanguages.contains(where: { $0.name.caseInsensitiveCompare(displayName) == .orderedSame }) {
            return (.language(displayName), "")
        }
        return (.custom, displayName)
    }

    static func swapped(
        source: (option: TranslationLanguageOption, customLanguage: String),
        target: (option: TranslationLanguageOption, customLanguage: String),
        automaticTargetFallback: (option: TranslationLanguageOption, customLanguage: String)
    ) -> (
        source: (option: TranslationLanguageOption, customLanguage: String),
        target: (option: TranslationLanguageOption, customLanguage: String)
    ) {
        let newTarget = source.option == .automatic ? automaticTargetFallback : source
        return (source: target, target: newTarget)
    }

    private static func displayName(for language: String?) -> String {
        guard let language else { return "" }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalizedIdentifier = trimmed.replacingOccurrences(of: "_", with: "-")
        let languageCode = normalizedIdentifier.split(separator: "-").first.map(String.init) ?? normalizedIdentifier
        return Locale.current.localizedString(forLanguageCode: languageCode)?.localizedCapitalized
            ?? trimmed.localizedCapitalized
    }
}

struct ImageTranslationToolView: View {
    let model: PracticeLanguageToolViewModel
    @State private var sourceLanguageOption: TranslationLanguageOption
    @State private var sourceCustomLanguage = ""
    @State private var targetLanguageOption: TranslationLanguageOption
    @State private var targetCustomLanguage = ""
    @State private var imageData: Data?
    @State private var mimeType = "image/jpeg"
    @State private var imagePreparationError: String?
    @State private var isShowingCamera = false

    init(model: PracticeLanguageToolViewModel, targetLanguage: String, nativeLanguage: String? = nil) {
        self.model = model
        let source = TranslationLanguageOption.option(for: nativeLanguage, allowsAutomatic: true)
        let target = TranslationLanguageOption.option(for: targetLanguage, allowsAutomatic: false)
        _sourceLanguageOption = State(initialValue: source.option)
        _sourceCustomLanguage = State(initialValue: source.customLanguage)
        _targetLanguageOption = State(initialValue: target.option)
        _targetCustomLanguage = State(initialValue: target.customLanguage)
    }

    #if canImport(PhotosUI)
    @State private var selectedPhoto: PhotosPickerItem?
    #endif

    var body: some View {
        Form {
            Section("Languages") {
                Picker("From", selection: $sourceLanguageOption) {
                    Text("Detect automatically").tag(TranslationLanguageOption.automatic)
                    ForEach(TranslationLanguageOption.commonLanguages) { language in
                        Text(language.name).tag(TranslationLanguageOption.language(language.name))
                    }
                    Text("Other...").tag(TranslationLanguageOption.custom)
                }
                if sourceLanguageOption == .custom {
                    TextField("Source language", text: $sourceCustomLanguage)
                }
                Picker("To", selection: $targetLanguageOption) {
                    ForEach(TranslationLanguageOption.commonLanguages) { language in
                        Text(language.name).tag(TranslationLanguageOption.language(language.name))
                    }
                    Text("Other...").tag(TranslationLanguageOption.custom)
                }
                if targetLanguageOption == .custom {
                    TextField("Target language", text: $targetCustomLanguage)
                }
            }
            Section {
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
                .disabled(model.isLoading || imageData == nil || resolvedTargetLanguage.isEmpty)
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
                do {
                    let payload = try ImageTranslationPayloadPreparer.prepareJPEG(from: data)
                    imageData = payload.data
                    mimeType = payload.mimeType
                    imagePreparationError = nil
                } catch {
                    imageData = nil
                    mimeType = "image/jpeg"
                    imagePreparationError = ImageTranslationPayloadPreparer.message(for: error)
                }
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
        } else if let imagePreparationError {
            Section { Text(imagePreparationError).foregroundStyle(.red) }
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
            sourceLanguage: resolvedSourceLanguage,
            targetLanguage: resolvedTargetLanguage)
    }

    private var resolvedSourceLanguage: String? {
        switch sourceLanguageOption {
        case .automatic: return nil
        case let .language(name): return name
        case .custom: return trimmed(sourceCustomLanguage)
        }
    }

    private var resolvedTargetLanguage: String {
        switch targetLanguageOption {
        case .automatic: return "English"
        case let .language(name): return name
        case .custom: return trimmed(targetCustomLanguage) ?? ""
        }
    }

    #if canImport(PhotosUI)
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        #if os(iOS) && canImport(UIKit)
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw ImageTranslationPayloadPreparationError.unreadable
            }
            let payload = try ImageTranslationPayloadPreparer.prepareJPEG(from: data)
            imageData = payload.data
            mimeType = payload.mimeType
            imagePreparationError = nil
        } catch {
            imageData = nil
            mimeType = "image/jpeg"
            imagePreparationError = ImageTranslationPayloadPreparer.message(for: error)
        }
        #else
        imageData = nil
        mimeType = "image/jpeg"
        imagePreparationError = "Image translation is not available for this build."
        #endif
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
    case "hindi": return "hi-IN"
    case "italian": return "it-IT"
    case "japanese": return "ja-JP"
    case "korean": return "ko-KR"
    case "portuguese": return "pt-PT"
    case "spanish": return "es-ES"
    default: return Locale.current.identifier
    }
}

#if os(iOS) && canImport(UIKit)
struct PreparedImageTranslationPayload: Equatable {
    let data: Data
    let mimeType: String
}

enum ImageTranslationPayloadPreparationError: Error, Equatable {
    case unreadable
    case compressionFailed
}

enum ImageTranslationPayloadPreparer {
    static let maxBytes = 5_000_000
    private static let initialMaxPixelDimension: CGFloat = 1_800
    private static let minimumMaxPixelDimension: CGFloat = 480
    private static let compressionQualities: [CGFloat] = [0.86, 0.76, 0.66, 0.56, 0.46]

    static func prepareJPEG(from data: Data, maxBytes: Int = maxBytes) throws -> PreparedImageTranslationPayload {
        guard let image = UIImage(data: data) else {
            throw ImageTranslationPayloadPreparationError.unreadable
        }
        return try prepareJPEG(from: image, maxBytes: maxBytes)
    }

    static func prepareJPEG(from image: UIImage, maxBytes: Int = maxBytes) throws -> PreparedImageTranslationPayload {
        let largestPixelDimension = max(image.size.width * image.scale, image.size.height * image.scale)
        var targetMaxPixelDimension = min(max(largestPixelDimension, minimumMaxPixelDimension), initialMaxPixelDimension)

        while targetMaxPixelDimension >= minimumMaxPixelDimension {
            let resized = image.resizedToFit(maxPixelDimension: targetMaxPixelDimension)
            for quality in compressionQualities {
                guard let data = resized.jpegData(compressionQuality: quality) else {
                    continue
                }
                if data.count <= maxBytes {
                    return PreparedImageTranslationPayload(data: data, mimeType: "image/jpeg")
                }
            }
            targetMaxPixelDimension *= 0.75
        }

        throw ImageTranslationPayloadPreparationError.compressionFailed
    }

    static func message(for error: Error) -> String {
        switch error {
        case ImageTranslationPayloadPreparationError.unreadable:
            return "This photo couldn't be read. Please choose another image."
        case ImageTranslationPayloadPreparationError.compressionFailed:
            return "This photo is too large to translate. Please choose a smaller image."
        default:
            return "This photo couldn't be prepared for translation. Please try another image."
        }
    }
}

private extension UIImage {
    func resizedToFit(maxPixelDimension: CGFloat) -> UIImage {
        let sourcePixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let largestDimension = max(sourcePixelSize.width, sourcePixelSize.height)
        guard largestDimension > maxPixelDimension else {
            return normalizedForJPEG()
        }

        let ratio = maxPixelDimension / largestDimension
        let targetPixelSize = CGSize(
            width: max(1, floor(sourcePixelSize.width * ratio)),
            height: max(1, floor(sourcePixelSize.height * ratio)))
        let targetPointSize = CGSize(
            width: targetPixelSize.width / UIScreen.main.scale,
            height: targetPixelSize.height / UIScreen.main.scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetPointSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetPointSize))
        }
    }

    func normalizedForJPEG() -> UIImage {
        guard imageOrientation != .up || hasAlpha else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    var hasAlpha: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}

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
