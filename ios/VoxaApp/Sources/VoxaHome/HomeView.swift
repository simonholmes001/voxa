#if canImport(SwiftUI)
import SwiftUI

/// The Home / Today surface shown after onboarding. It presents a compact
/// profile summary and a "today" card whose primary action routes into the
/// Talk (voice tutor) screen.
public struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let onStartTalk: () -> Void

    public init(model: HomeViewModel, onStartTalk: @escaping () -> Void) {
        self.model = model
        self.onStartTalk = onStartTalk
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Home")
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading your home…")
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
                profileCard(summary)
                todayCard(summary)
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func profileCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your plan")
                .font(.headline)
            HStack(spacing: 16) {
                label("Language", summary.languageName)
                label("Level", summary.levelName)
            }
            HStack(spacing: 16) {
                label("Goal", summary.goalName)
                label("Daily", "\(summary.dailyMinutes) min")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func todayCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
            Text("Ready to practise \(summary.languageName)?")
                .font(.title3)
                .fontWeight(.semibold)
            Text("\(summary.levelName) · about \(summary.dailyMinutes) min today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onStartTalk) {
                Label("Start talking", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("home-start-talk")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
