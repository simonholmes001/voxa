#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The Home / Today surface shown after onboarding. It presents the learner's
/// active languages and a clear way back into the learning flow.
public struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let talkModel: TalkSessionViewModel?
    private let languages: [LearnerLanguageSummary]
    private let onContinueLearning: () -> Void
    private let onVoicePractice: () -> Void
    private let onSelectLanguage: (String) -> Void

    public init(
        model: HomeViewModel,
        talkModel: TalkSessionViewModel? = nil,
        languages: [LearnerLanguageSummary] = [],
        onContinueLearning: @escaping () -> Void,
        onVoicePractice: @escaping () -> Void,
        onSelectLanguage: @escaping (String) -> Void = { _ in }
    ) {
        self.model = model
        self.talkModel = talkModel
        self.languages = languages
        self.onContinueLearning = onContinueLearning
        self.onVoicePractice = onVoicePractice
        self.onSelectLanguage = onSelectLanguage
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Home")
            .task { await model.resumeIfAvailable() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading, .resuming:
            ProgressView(model.state == .resuming ? "Resuming your session…" : "Loading your home…")
        case let .ready(summary):
            ready(summary)
        case .needsOnboarding:
            message(
                title: "Let's set up your learning",
                subtitle: "Finish onboarding to see your personalized home.",
                symbol: "person.crop.circle.badge.plus"
            )
        case .failed(let text):
            VStack(spacing: 16) {
                message(
                    title: "Something went wrong",
                    subtitle: text,
                    symbol: "exclamationmark.triangle"
                )
                Button("Try again") { Task { await model.retry() } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("home-retry")
            }
        }
    }

    private func ready(_ summary: LearnerProfileSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                languagesCard(summary)
                todayCard(summary)
                practiceCard(summary)
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func languagesCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your languages")
                    .font(.headline)
                Spacer()
                if summary.isStale {
                    Text("Offline")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Offline profile")
                    }
            }

            let rows = resolvedLanguages(for: summary)
            ForEach(rows) { language in
                Button {
                    onSelectLanguage(language.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: language.isActive ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(language.isActive ? .green : .secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(language.name)
                                .font(.body)
                                .fontWeight(.semibold)
                            Text("\(language.levelName) • \(language.dailyMinutes) min/day")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func todayCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
            Text("Continue \(summary.languageName)")
                .font(.title3)
                .fontWeight(.semibold)
            Text("\(summary.levelName) • \(summary.goalName.lowercased()) • about \(summary.dailyMinutes) min today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: onContinueLearning) {
                    Label("Continue learning", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("home-continue-learning")

                if let talk = talkModel, case .connected = talk.state {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .accessibilityIdentifier("home_talk_connected")
                        .help("Talk is connected")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func practiceCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice")
                .font(.headline)
            Button(action: onVoicePractice) {
                Label("Talk with your tutor", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("home-voice-practice")

            HStack(spacing: 10) {
                quickPractice("Mistakes", "exclamationmark.arrow.triangle.2.circlepath")
                quickPractice("Words", "textformat.abc")
                quickPractice("Pronunciation", "waveform")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.secondary.opacity(0.18))
        }
    }

    private func quickPractice(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resolvedLanguages(for summary: LearnerProfileSummary) -> [LearnerLanguageSummary] {
        if !languages.isEmpty {
            return languages
        }
        return [
            LearnerLanguageSummary(
                id: summary.languageName,
                name: summary.languageName,
                levelName: summary.levelName,
                dailyMinutes: summary.dailyMinutes,
                isActive: true
            )
        ]
    }

    private func message(title: String, subtitle: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
#endif
