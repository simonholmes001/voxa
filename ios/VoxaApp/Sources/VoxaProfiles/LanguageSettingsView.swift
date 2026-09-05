#if canImport(SwiftUI)
import SwiftUI
import VoxaOnboarding

/// Editable per-language settings for the active profile. Hosted by the app's
/// More/Settings surface.
public struct LanguageSettingsView: View {
    @Bindable private var model: LanguageSettingsViewModel
    @State private var customGoalText = ""
    @State private var customGoalError: String?

    private static let languages = OnboardingLanguages.sorted

    public init(model: LanguageSettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
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
                    set: { model.setMinutesPerDay($0) }
                )) {
                    ForEach(DailyTimeSelection.presetMinutes, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
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

            Section {
                Button("Save changes") { Task { await model.save() } }
                    .disabled(!model.canSave || model.state == .saving)
                    .accessibilityIdentifier("language-settings-save")
                statusRow
            }
        }
        .navigationTitle("\(model.displayName) settings")
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
}
#endif
