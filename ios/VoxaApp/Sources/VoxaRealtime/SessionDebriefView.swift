#if canImport(SwiftUI)
import SwiftUI

/// The post-session debrief: summary card, up to 3 recurring mistakes, up to
/// 5 useful phrases the learner picked up, up to 3 pronunciation notes, and
/// one recommended next drill with a tap-to-launch action. Shown when
/// `TalkSessionViewModel.debriefState` is `.loading`, `.ready`, or `.failed`.
public struct SessionDebriefView: View {
    private let debriefState: DebriefState
    private let onStartNext: (RealtimeTutorIntent) -> Void
    private let onDismiss: () -> Void
    private let onRetry: () -> Void

    public init(
        debriefState: DebriefState,
        onStartNext: @escaping (RealtimeTutorIntent) -> Void,
        onDismiss: @escaping () -> Void,
        onRetry: @escaping () -> Void = {}
    ) {
        self.debriefState = debriefState
        self.onStartNext = onStartNext
        self.onDismiss = onDismiss
        self.onRetry = onRetry
    }

    public var body: some View {
        switch debriefState {
        case .idle, .loading:
            loadingBody
        case let .ready(debrief):
            readyBody(debrief)
        case let .failed(message):
            failedBody(message)
        }
    }

    // MARK: - Loading

    private var loadingBody: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing your session summary…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Just a moment while we look at what you practised.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("debrief-loading")
    }

    // MARK: - Ready

    @ViewBuilder
    private func readyBody(_ debrief: SessionDebrief) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard(debrief.summary)
                // Every section always renders — an empty list becomes a
                // "nothing to flag" placeholder rather than being hidden.
                // Hiding empty sections made short first sessions look like
                // the feature was broken.
                section(title: "Recurring mistakes", identifier: "debrief-mistakes") {
                    if debrief.recurringMistakes.isEmpty {
                        emptyPlaceholder("Nothing recurring flagged this session. Try a longer conversation for more feedback.")
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(debrief.recurringMistakes.enumerated()), id: \.offset) { _, mistake in
                                mistakeRow(mistake)
                            }
                        }
                    }
                }
                section(title: "Useful phrases", identifier: "debrief-phrases") {
                    if debrief.usefulPhrases.isEmpty {
                        emptyPlaceholder("No standout phrases yet — a longer session gives us more to work with.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(debrief.usefulPhrases.enumerated()), id: \.offset) { _, phrase in
                                Label(phrase, systemImage: "quote.bubble")
                                    .font(.body)
                            }
                        }
                    }
                }
                section(title: "Pronunciation notes", identifier: "debrief-pronunciation") {
                    if debrief.pronunciationNotes.isEmpty {
                        emptyPlaceholder("Nothing to note yet. Pronunciation drills give the tutor more to hear.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(debrief.pronunciationNotes.enumerated()), id: \.offset) { _, note in
                                Label(note, systemImage: "waveform")
                                    .font(.body)
                            }
                        }
                    }
                }
                nextDrillCard(debrief.recommendedNextDrill)
                doneButton
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Session summary")
        .accessibilityIdentifier("debrief-ready")
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Text(summary)
                .font(.title3)
                .fontWeight(.medium)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("debrief-summary")
    }

    private func emptyPlaceholder(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .italic()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func mistakeRow(_ mistake: DebriefRecurringMistake) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                severityChip(mistake.severity)
                Text(mistake.pattern)
                    .font(.headline)
            }
            Text("“\(mistake.example)”")
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func severityChip(_ severity: DebriefRecurringMistake.Severity) -> some View {
        let (label, tint): (String, Color) = {
            switch severity {
            case .low: return ("low", .green)
            case .medium: return ("med", .orange)
            case .high: return ("high", .red)
            }
        }()
        return Text(label.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .accessibilityIdentifier(identifier)
    }

    private func nextDrillCard(_ drill: DebriefRecommendedDrill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECOMMENDED NEXT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
            Text(drill.intent.title)
                .font(.title3)
                .fontWeight(.semibold)
            if !drill.reason.isEmpty {
                Text(drill.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                onStartNext(drill.intent)
            } label: {
                Label("Start this drill", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("debrief-start-next")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.tint.opacity(0.2)))
        .accessibilityIdentifier("debrief-next")
    }

    private var doneButton: some View {
        Button("Done", action: onDismiss)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("debrief-dismiss")
    }

    // MARK: - Failed

    private func failedBody(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Couldn't generate your summary")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("debrief-retry")
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debrief-dismiss")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("debrief-failed")
    }
}
#endif
