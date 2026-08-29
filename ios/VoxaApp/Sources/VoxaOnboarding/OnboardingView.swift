#if canImport(SwiftUI)
import SwiftUI

/// The first-run onboarding flow: a short, stepped questionnaire that captures
/// the essentials (target/native language, goal, time, a quick placement) and
/// shows the estimated CEFR level before starting.
public struct OnboardingView: View {
    @Bindable private var model: OnboardingViewModel

    private static let languages = [
        "French", "Spanish", "German", "Italian", "Japanese",
        "English", "Mandarin", "Portuguese",
    ]
    private static let minuteOptions = [5, 10, 15, 30]

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
            header("Why are you learning?", "Pick the main reason for now.")
            ForEach(LearningGoal.allCases) { goal in
                choiceRow(goal.title, isSelected: model.draft.goal == goal) { model.setGoal(goal) }
            }
        case .time:
            header("How much time per day?", "You can change this anytime.")
            ForEach(Self.minuteOptions, id: \.self) { minutes in
                choiceRow("\(minutes) minutes", isSelected: model.draft.minutesPerDay == minutes) {
                    model.setMinutesPerDay(minutes)
                }
            }
        case .placement:
            header("Quick placement", "Tick everything you can already do.")
            ForEach(Array(PlacementEstimator.questions.enumerated()), id: \.element.id) { index, question in
                Toggle(question.prompt, isOn: placementBinding(index))
                    .padding(.vertical, 4)
            }
        case .summary:
            header("You're all set", "Here's where we'll start.")
            summaryRow("Learning", model.draft.targetLanguage ?? "—")
            summaryRow("Goal", model.draft.goal?.title ?? "—")
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
        case .goal: return model.draft.goal != nil
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

    private func picker(selection: Binding<String?>, options: [String]) -> some View {
        Picker("", selection: selection) {
            Text("Select").tag(String?.none)
            ForEach(options, id: \.self) { option in
                Text(option).tag(String?.some(option))
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
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
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
