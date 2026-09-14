#if canImport(SwiftUI)
import SwiftUI
import VoxaOnboarding
import VoxaRealtime

public enum LanguageSettingsTab: String, CaseIterable, Identifiable {
    case language
    case aiTutor

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .language: return "Language"
        case .aiTutor: return "AI tutor"
        }
    }
}

/// Editable per-language settings for the active profile. Hosted by the app's
/// More/Settings surface.
public struct LanguageSettingsView: View {
    @Bindable private var model: LanguageSettingsViewModel
    @State private var customGoalText = ""
    @State private var customGoalError: String?
    @State private var customMinutesText = ""
    @State private var selectedTab: LanguageSettingsTab
    private let showsTabPicker: Bool
    private let navigationTitleOverride: String?

    private static let languages = OnboardingLanguages.sorted

    public init(
        model: LanguageSettingsViewModel,
        initialTab: LanguageSettingsTab = .language,
        showsTabPicker: Bool = true,
        navigationTitle: String? = nil
    ) {
        self.model = model
        _selectedTab = State(initialValue: initialTab)
        self.showsTabPicker = showsTabPicker
        self.navigationTitleOverride = navigationTitle
    }

    public var body: some View {
        Form {
            if showsTabPicker {
                Picker("Settings", selection: $selectedTab) {
                    ForEach(LanguageSettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("language-settings-tab-picker")
            }

            switch selectedTab {
            case .language:
                languageSettings
            case .aiTutor:
                aiTutorSettings
            }

            Section {
                Button("Save changes") { Task { await model.save() } }
                    .disabled(!model.canSave || model.state == .saving)
                    .accessibilityIdentifier("language-settings-save")
                statusRow
            }
        }
        .navigationTitle(navigationTitleOverride ?? shortTitle)
        .onAppear {
            if let minutes = model.minutesPerDay,
               !DailyTimeSelection.isPreset(minutes) {
                customMinutesText = String(minutes)
            }
        }
    }

    @ViewBuilder
    private var languageSettings: some View {
            Section("Language") {
                LabeledContent("Learning", value: model.displayName)
                Picker("Native language", selection: $model.nativeLanguage) {
                    ForEach(Self.languages) { language in
                        Text(language.displayName).tag(language.key)
                    }
                }
            }

            Section("Goals") {
                ForEach(LearningGoal.allCases) { goal in
                    Toggle(goal.title, isOn: Binding(
                        get: { model.isGoalSelected(goal.rawValue) },
                        set: { _ in model.togglePredefinedGoal(goal) }
                    ))
                }
                ForEach(model.goals.filter(GoalSelection.isCustom), id: \.self) { value in
                    HStack {
                        Text(value)
                        Spacer()
                        Button(role: .destructive) { model.removeGoal(value) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add your own goal", text: $customGoalText)
                    Button("Add", action: addCustomGoal)
                        .disabled(customGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let customGoalError {
                    Text(customGoalError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Daily time") {
                Picker("Minutes per day", selection: Binding(
                    get: { model.minutesPerDay ?? DailyTimeSelection.presetMinutes.first! },
                    set: {
                        model.setMinutesPerDay($0)
                        customMinutesText = ""
                    }
                )) {
                    ForEach(DailyTimeSelection.presetMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                TextField("Custom minutes (5-180)", text: $customMinutesText)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                    .onChange(of: customMinutesText) { _, value in
                        _ = model.setCustomMinutes(value)
                    }
            }

            Section("Level") {
                Picker("Placement level", selection: Binding(
                    get: { model.placementLevel },
                    set: { model.setPlacementLevel($0) }
                )) {
                    ForEach(CEFRLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
            }
    }

    @ViewBuilder
    private var aiTutorSettings: some View {
        Section("Voice") {
            Picker("Voice", selection: Binding(
                get: { model.aiTutorPreferences.voice },
                set: {
                    model.aiTutorPreferences.voice = $0
                    Task { await model.previewTutor() }
                }
            )) {
                ForEach(AiTutorVoice.allCases) { voice in
                    Text(voice.title).tag(voice)
                }
            }
            Picker("Tone", selection: Binding(
                get: { model.aiTutorPreferences.tone },
                set: {
                    model.aiTutorPreferences.tone = $0
                    Task { await model.previewTutor() }
                }
            )) {
                ForEach(AiTutorTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(speedLabel)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { model.aiTutorPreferences.speed },
                        set: { model.aiTutorPreferences.speed = $0 }
                    ),
                    in: AiTutorPreferences.minimumSpeed...AiTutorPreferences.maximumSpeed,
                    step: 0.05
                ) { editing in
                    if !editing {
                        Task { await model.previewTutor() }
                    }
                }
                .accessibilityIdentifier("ai-tutor-speed-slider")
            }
        }

        Section {
            Button {
                Task { await model.previewTutor() }
            } label: {
                Label(previewButtonTitle, systemImage: "speaker.wave.2")
            }
            .disabled(!model.canPreviewTutor || model.previewState == .playing)
            .accessibilityIdentifier("ai-tutor-preview")

            TextField(
                "Extra direction",
                text: Binding(
                    get: { model.aiTutorPreferences.customInstructions },
                    set: { model.aiTutorPreferences.customInstructions = String($0.prefix(400)) }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
            .onSubmit { Task { await model.previewTutor() } }
            .accessibilityIdentifier("ai-tutor-custom-instructions")
        } header: {
            Text("Style")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tone guides the tutor's speaking style. Voice options are OpenAI Realtime voices, not gender labels.")
                previewStatus
            }
        }
    }

    @ViewBuilder
    private var previewStatus: some View {
        switch model.previewState {
        case .idle:
            EmptyView()
        case .playing:
            Text("Playing preview…")
        case .played:
            Text("Preview played.")
        case let .failed(message):
            Text(message)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.state {
        case .saving:
            Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .versionConflict:
            Text("These settings changed on another device. Reopen settings to get the latest before saving.")
                .font(.caption)
                .foregroundStyle(.orange)
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .editing:
            EmptyView()
        }
    }

    private func addCustomGoal() {
        if let error = model.addCustomGoal(customGoalText) {
            customGoalError = message(for: error)
        } else {
            customGoalText = ""
            customGoalError = nil
        }
    }

    private func message(for error: GoalSelection.CustomGoalError) -> String {
        switch error {
        case .empty: return "Enter a goal."
        case let .tooLong(max): return "Keep goals under \(max) characters."
        case .duplicate: return "You've already added that goal."
        case let .limitReached(max): return "You can add up to \(max) custom goals."
        }
    }

    private var shortTitle: String {
        model.displayName.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
    }

    private var speedLabel: String {
        "\(String(format: "%.2g", model.aiTutorPreferences.speed))x"
    }

    private var previewButtonTitle: String {
        model.previewState == .playing ? "Playing preview" : "Preview voice"
    }
}
#endif
