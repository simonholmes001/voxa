#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The Practice tab. Replaces the previous Learn tab; that tab surfaced a
/// single guided lesson launcher, this one is the "what should I do now?"
/// hub — one Today card plus a grid of activity tiles that route into the
/// per-activity Realtime prompts B1 shipped.
public struct PracticeHubView: View {
    private let summary: LearnerProfileSummary?
    private let planState: LearnerPlanState
    private let courseState: LearnerCourseState
    private let languageToolModel: PracticeLanguageToolViewModel?
    private let onStartTalk: (RealtimeTutorIntent) -> Void

    public init(
        summary: LearnerProfileSummary?,
        planState: LearnerPlanState = .idle,
        courseState: LearnerCourseState = .idle,
        languageToolModel: PracticeLanguageToolViewModel? = nil,
        onStartTalk: @escaping (RealtimeTutorIntent) -> Void
    ) {
        self.summary = summary
        self.planState = planState
        self.courseState = courseState
        self.languageToolModel = languageToolModel
        self.onStartTalk = onStartTalk
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                todayCard
                languageToolsSection
                tileGridSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Practice")
    }

    private var todayCard: some View {
        let card = PracticeHub.todayCard(
            planState: planState,
            courseState: courseState,
            summary: summary)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Today")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                if case .loading = planState {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Loading your plan")
                }
            }
            Text(card.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(card.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !card.focusAreas.isEmpty {
                focusChips(card.focusAreas)
            }
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

    private func focusChips(_ areas: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(areas.enumerated()), id: \.offset) { _, area in
                Text(area)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint.opacity(0.2), in: Capsule())
            }
        }
        .accessibilityIdentifier("practice-today-focus-areas")
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

    @ViewBuilder
    private var languageToolsSection: some View {
        if let languageToolModel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Language tools")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    NavigationLink {
                        VocabularyQuizView(
                            model: languageToolModel,
                            targetLanguage: targetLanguage,
                            proficiencyBand: proficiencyBand,
                            defaultFocus: summary?.currentLessonTitle ?? summary?.activePlanTitle)
                    } label: {
                        toolCard("Vocabulary test", "checklist", "Multiple-choice word checks.")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice-tool-vocabulary-test")

                    NavigationLink {
                        AskAnythingView(
                            model: languageToolModel,
                            targetLanguage: targetLanguage,
                            nativeLanguage: nil)
                    } label: {
                        toolCard("Ask anything", "questionmark.bubble", "How do I say it?")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice-tool-ask-anything")

                    NavigationLink {
                        TranslationToolView(
                            model: languageToolModel,
                            targetLanguage: targetLanguage)
                    } label: {
                        toolCard("Translate", "character.bubble", "Text translation.")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice-tool-translate")

                    NavigationLink {
                        ImageTranslationToolView(
                            model: languageToolModel,
                            targetLanguage: targetLanguage)
                    } label: {
                        toolCard("Image translate", "camera.viewfinder", "Translate a photo.")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("practice-tool-image-translate")
                }
            }
        }
    }

    private func toolCard(_ title: String, _ symbol: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 116, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.tint.opacity(0.15), lineWidth: 1)
        )
    }

    private var targetLanguage: String {
        summary?.languageName ?? "your target language"
    }

    private var proficiencyBand: String {
        summary?.levelName ?? "A1-A2"
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
