#if canImport(SwiftUI)
import SwiftUI

/// The first-run onboarding flow: a short, stepped questionnaire that captures
/// the essentials (target/native language, goals, time, a quick placement) and
/// shows the estimated CEFR level before starting.
public struct OnboardingView: View {
    @Bindable private var model: OnboardingViewModel
    @State private var customGoalText = ""
    @State private var customGoalError: String?

    private static let languages = OnboardingLanguages.sorted

    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 24) {
            ProgressView(value: progress)
                .accessibilityIdentifier("onboarding-progress")
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            controls
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progress: Double {
        Double(model.currentStep.rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.currentStep {
        case .welcome:
            header("Welcome to Voxa", "Answer a few quick questions and we'll tailor your learning plan.")
        case .targetLanguage:
            header("What do you want to learn?", "Choose your target language.")
            picker(selection: targetLanguageBinding, options: Self.languages)
        case .nativeLanguage:
            header("What's your native language?", "This helps us explain things clearly.")
            picker(selection: nativeLanguageBinding, options: Self.languages)
        case .goal:
            goalStep
        case .time:
            timeStep
        case .placement:
            header("Quick placement", "Tick everything you can already do.")
            ForEach(Array(PlacementEstimator.questions.enumerated()), id: \.element.id) { index, question in
                Toggle(question.prompt, isOn: placementBinding(index))
                    .padding(.vertical, 4)
            }
        case .summary:
            header("You're all set", "Here's where we'll start.")
            summaryRow("Learning", model.draft.targetLanguage.map(OnboardingLanguages.displayName(forKey:)) ?? "—")
            summaryRow("Goals", goalsSummary)
            summaryRow("Daily time", model.draft.minutesPerDay.map { "\($0) min" } ?? "—")
            summaryRow("Starting level", model.placementEstimate.displayName)
            if case let .failed(message) = model.phase {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("onboarding-error")
            }
        }
    }

    // MARK: - Goal step (multi-select + custom)

    @ViewBuilder
    private var goalStep: some View {
        header("Why are you learning?", "Pick one or more, or add your own.")

        ForEach(LearningGoal.allCases) { goal in
            choiceRow(goal.title, isSelected: model.isGoalSelected(goal.rawValue)) {
                model.togglePredefinedGoal(goal)
            }
        }

        ForEach(customGoals, id: \.self) { value in
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                Text(value)
                Spacer()
                Button {
                    model.removeGoal(value)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(value)")
            }
            .padding(.vertical, 8)
        }

        HStack {
            TextField("Add your own goal", text: $customGoalText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(addCustomGoal)
                .accessibilityIdentifier("onboarding-custom-goal-field")
            Button("Add", action: addCustomGoal)
                .buttonStyle(.bordered)
                .disabled(customGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("onboarding-custom-goal-add")
        }
        .padding(.top, 4)

        if let customGoalError {
            Text(customGoalError)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("onboarding-custom-goal-error")
        }
    }

    private var customGoals: [String] {
        model.selectedGoals.filter(GoalSelection.isCustom)
    }

    private var goalsSummary: String {
        let titles = model.selectedGoals.map(GoalSelection.displayTitle)
        return titles.isEmpty ? "—" : titles.joined(separator: ", ")
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
        case .empty:
            return "Enter a goal."
        case let .tooLong(max):
            return "Keep goals under \(max) characters."
        case .duplicate:
            return "You've already added that goal."
        case let .limitReached(max):
            return "You can add up to \(max) custom goals."
        }
    }

    // MARK: - Time step (presets + custom)

    @ViewBuilder
    private var timeStep: some View {
        header("How much time per day?", "You can change this anytime.")

        ForEach(DailyTimeSelection.presetMinutes, id: \.self) { minutes in
            choiceRow("\(minutes) minutes", isSelected: !model.isCustomTimeMode && model.draft.minutesPerDay == minutes) {
                model.setMinutesPerDay(minutes)
            }
        }

        choiceRow("Custom…", isSelected: model.isCustomTimeMode) {
            model.enterCustomTimeMode()
        }

        if model.isCustomTimeMode {
            HStack {
                TextField("Minutes per day", text: customTimeBinding)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .accessibilityIdentifier("onboarding-custom-time-field")
            }
            .padding(.top, 4)

            if let error = model.customTimeError {
                Text(message(for: error))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("onboarding-custom-time-error")
            } else {
                Text("Between \(DailyTimeSelection.minMinutes) and \(DailyTimeSelection.maxMinutes) minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var customTimeBinding: Binding<String> {
        Binding(get: { model.customTimeText }, set: { model.updateCustomTime($0) })
    }

    private func message(for error: DailyTimeSelection.DailyTimeError) -> String {
        switch error {
        case .empty:
            return "Enter your daily practice time."
        case .notANumber:
            return "Enter a whole number of minutes."
        case let .outOfRange(min, max):
            return "Choose between \(min) and \(max) minutes."
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            if model.currentStep.rawValue > 0 {
                Button("Back") { model.goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if model.currentStep.isLast {
                Button("Start learning") {
                    Task { await model.finish() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.phase == .submitting)
                .accessibilityIdentifier("onboarding-finish")
            } else {
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                    .accessibilityIdentifier("onboarding-continue")
            }
        }
    }

    private var canAdvance: Bool {
        switch model.currentStep {
        case .welcome, .placement: return true
        case .targetLanguage: return !(model.draft.targetLanguage ?? "").isEmpty
        case .nativeLanguage: return !(model.draft.nativeLanguage ?? "").isEmpty
        case .goal: return !model.selectedGoals.isEmpty
        case .time: return model.draft.minutesPerDay != nil
        case .summary: return true
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title).fontWeight(.bold)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
    }

    private func picker(selection: Binding<String?>, options: [SupportedLanguage]) -> some View {
        Picker("", selection: selection) {
            Text("Select").tag(String?.none)
            ForEach(options) { language in
                Text(language.displayName).tag(String?.some(language.key))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private func choiceRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings

    private var targetLanguageBinding: Binding<String?> {
        Binding(get: { model.draft.targetLanguage }, set: { if let v = $0 { model.setTargetLanguage(v) } })
    }

    private var nativeLanguageBinding: Binding<String?> {
        Binding(get: { model.draft.nativeLanguage }, set: { if let v = $0 { model.setNativeLanguage(v) } })
    }

    private func placementBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: {
                index < model.draft.placementAnswers.count ? model.draft.placementAnswers[index] : false
            },
            set: { model.answerPlacement(index, $0) }
        )
    }
}
#endif
