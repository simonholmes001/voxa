#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The Practice tab. Replaces the previous Learn tab; that tab surfaced a
/// single guided lesson launcher, this one is the "what should I do now?"
/// hub — one Today card plus a grid of activity tiles that route into the
/// per-activity Realtime prompts B1 shipped.
public struct PracticeHubView: View {
    private let summary: LearnerProfileSummary?
    private let onStartTalk: (RealtimeTutorIntent) -> Void

    public init(
        summary: LearnerProfileSummary?,
        onStartTalk: @escaping (RealtimeTutorIntent) -> Void
    ) {
        self.summary = summary
        self.onStartTalk = onStartTalk
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                todayCard
                tileGridSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Practice")
    }

    private var todayCard: some View {
        let card = PracticeHub.todayCard(for: summary)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Text(card.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(card.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onStartTalk(PracticeHub.todayIntent(for: card.recommendation))
            } label: {
                Label(card.actionTitle, systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("practice-today-action")
        }
        .padding()
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice-today-card")
    }

    private var tileGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice options")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                spacing: 12
            ) {
                ForEach(PracticeHub.tiles(for: summary)) { tile in
                    tileButton(tile)
                }
            }
        }
    }

    private func tileButton(_ tile: PracticeHubTile) -> some View {
        Button {
            onStartTalk(PracticeHub.intent(for: tile.kind, summary: summary))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: tile.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(tile.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(tile.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding()
            .frame(minHeight: 128, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.tint.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("practice-tile-\(tile.id)")
        .accessibilityLabel(tile.title)
        .accessibilityHint(tile.subtitle)
    }
}

#Preview {
    NavigationStack {
        PracticeHubView(
            summary: LearnerProfileSummary(
                languageName: "French",
                levelName: "A2",
                goalName: "Travel",
                dailyMinutes: 15,
                activePlanTitle: "Everyday French",
                currentLessonTitle: "Past tense",
                currentLessonStepIndex: 2,
                dueReviewCount: 3,
                recentSessionCount: 4,
                minutesPracticedToday: 12
            ),
            onStartTalk: { _ in }
        )
    }
}
#endif
