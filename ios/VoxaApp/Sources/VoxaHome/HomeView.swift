#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The Home / Today surface shown after onboarding. It presents the learner's
/// active languages and a clear way back into the learning flow.
public struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let courseModel: LearnerCourseViewModel?
    private let planModel: LearnerPlanViewModel?
    private let talkModel: TalkSessionViewModel?
    private let languages: [LearnerLanguageSummary]
    private let onContinueLearning: () -> Void
    private let onVoicePractice: () -> Void
    private let onReviewPractice: (String) -> Void
    private let onSelectLanguage: (String) -> Void
    private let onStartTalk: (RealtimeTutorIntent) -> Void
    @State private var isPresentingReassessSheet = false
    /// Pre-fills the Reassess sheet when the learner accepts the
    /// evidence-based banner. Cleared after the sheet closes.
    @State private var reassessHint: String = ""
    /// Drives the CourseDetailView sheet — opened when the learner taps
    /// the course card body to see every lesson in the arc.
    @State private var isPresentingCourseDetail = false

    public init(
        model: HomeViewModel,
        courseModel: LearnerCourseViewModel? = nil,
        planModel: LearnerPlanViewModel? = nil,
        talkModel: TalkSessionViewModel? = nil,
        languages: [LearnerLanguageSummary] = [],
        onContinueLearning: @escaping () -> Void,
        onVoicePractice: @escaping () -> Void,
        onReviewPractice: @escaping (String) -> Void = { _ in },
        onSelectLanguage: @escaping (String) -> Void = { _ in },
        onStartTalk: @escaping (RealtimeTutorIntent) -> Void = { _ in }
    ) {
        self.model = model
        self.courseModel = courseModel
        self.planModel = planModel
        self.talkModel = talkModel
        self.languages = languages
        self.onContinueLearning = onContinueLearning
        self.onVoicePractice = onVoicePractice
        self.onReviewPractice = onReviewPractice
        self.onSelectLanguage = onSelectLanguage
        self.onStartTalk = onStartTalk
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Home")
            .task { await model.resumeIfAvailable() }
            .task { await courseModel?.load() }
            .sheet(isPresented: $isPresentingReassessSheet) {
                if let courseModel {
                    ReassessCourseSheet(
                        model: courseModel,
                        initialText: reassessHint) {
                        isPresentingReassessSheet = false
                        reassessHint = ""
                    }
                }
            }
            .sheet(isPresented: $isPresentingCourseDetail) {
                if let courseModel, let course = readyCourse(courseModel) {
                    CourseDetailView(
                        course: course,
                        onStartLesson: { lesson in
                            isPresentingCourseDetail = false
                            onStartTalk(lesson.intent)
                        },
                        onReassess: {
                            isPresentingCourseDetail = false
                            isPresentingReassessSheet = true
                        },
                        onDismiss: { isPresentingCourseDetail = false }
                    )
                }
            }
    }

    /// Extracts the current LearnerCourse from the view model when it is in
    /// a state that has content to render — `.ready` or the transient
    /// `.reassessing` state (which carries the previous course).
    private func readyCourse(_ courseModel: LearnerCourseViewModel) -> LearnerCourse? {
        switch courseModel.state {
        case let .ready(course): return course
        case let .reassessing(previous): return previous
        default: return nil
        }
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
                reassessmentBanner
                if let courseModel {
                    courseArcSection(courseModel: courseModel)
                }
                todayCard(summary)
                practiceCard(summary)
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var reassessmentBanner: some View {
        let suggestion = ReassessmentSuggestion.evaluate(
            course: courseModel?.state ?? .idle,
            plan: planModel?.state ?? .idle)
        if case let .suggested(title, rationale, hint) = suggestion {
            Button {
                reassessHint = hint
                isPresentingReassessSheet = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(rationale)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.tint.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-reassessment-banner")
            .accessibilityLabel(title)
            .accessibilityHint(rationale)
        }
    }

    @ViewBuilder
    private func courseArcSection(courseModel: LearnerCourseViewModel) -> some View {
        switch courseModel.state {
        case .idle, .loading:
            courseCardShell {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading your course…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case let .ready(course):
            courseCard(course, isReassessing: false)
        case let .reassessing(previous):
            courseCard(previous, isReassessing: true)
        case let .failed(message):
            // Non-blocking — Home still shows Today card + Practice
            // action below. A small warning is enough.
            courseCardShell {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't load your course", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await courseModel.load() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func courseCard(_ course: LearnerCourse, isReassessing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your course")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .textCase(.uppercase)
                    Text(course.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    if course.totalLessons > 0 {
                        Text(progressCaption(for: course))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isReassessing {
                    ProgressView().controlSize(.small)
                }
            }
            if course.totalLessons > 0 {
                ProgressView(value: course.progressFraction)
                    .accessibilityIdentifier("home-course-progress")
            } else {
                // Zero-lesson recovery. The backend's course mint can fail
                // (rate limit, model timeout, unfamiliar language input) and
                // fall back to the placeholder plan title with no lessons.
                // Rather than stranding the learner on an empty card, give
                // them a prominent affordance that opens the Reassess sheet
                // — which under the hood calls the course author again.
                zeroLessonRecoveryCard()
            }
            if let current = course.currentLesson {
                Button {
                    onStartTalk(current.intent)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(current.learningObjective)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(12)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-course-current-lesson")
                .disabled(isReassessing)
            }
            HStack(spacing: 8) {
                if course.totalLessons > 0 {
                    Button {
                        isPresentingCourseDetail = true
                    } label: {
                        Label("See all \(course.totalLessons) lessons", systemImage: "list.bullet")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isReassessing)
                    .accessibilityIdentifier("home-course-see-all")
                    Button {
                        isPresentingReassessSheet = true
                    } label: {
                        Label("Reassess my course", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isReassessing)
                    .accessibilityIdentifier("home-reassess")
                }
                Spacer()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.tint.opacity(0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-course-card")
    }

    @ViewBuilder
    private func zeroLessonRecoveryCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your course isn't ready yet")
                        .font(.headline)
                    Text("We couldn't build your lessons automatically. Tap below to generate them now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Button {
                reassessHint = "Please generate my full course."
                isPresentingReassessSheet = true
            } label: {
                Label("Generate my course", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("home-course-generate")
        }
        .padding(12)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func courseCardShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your course")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .textCase(.uppercase)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("home-course-card")
    }

    private func progressCaption(for course: LearnerCourse) -> String {
        course.progressCaption
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
            if rows.count > 2 {
                // Compact chips: with 3+ languages the vertical list
                // pushes the course card off-screen. Horizontal chips
                // keep the switcher on one line no matter how many
                // languages the learner has added.
                languageChipRow(rows)
            } else {
                ForEach(rows) { language in
                    languageRow(language)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func languageRow(_ language: LearnerLanguageSummary) -> some View {
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

    private func languageChipRow(_ languages: [LearnerLanguageSummary]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(languages) { language in
                    languageChip(language)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("home-language-chips")
    }

    private func languageChip(_ language: LearnerLanguageSummary) -> some View {
        Button {
            onSelectLanguage(language.id)
        } label: {
            HStack(spacing: 6) {
                if language.isActive {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .accessibilityHidden(true)
                }
                Text(language.name)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(language.levelName)
                    .font(.caption)
                    .foregroundStyle(language.isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(language.isActive ? .white : .primary)
            .background(language.isActive ? Color.accentColor : Color.secondary.opacity(0.12),
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-language-chip-\(language.id)")
        .accessibilityLabel("\(language.name), \(language.levelName)\(language.isActive ? ", active" : "")")
    }

    /// Today card — the daily-practice quota surface. Deliberately narrow
    /// after C3.1: the Course card above already carries "which lesson
    /// next?" so this card focuses on "how much have I practised today?"
    /// and gives a single Continue-learning CTA that resumes the arc.
    /// Removes the pre-C3 activePlanTitle/currentLessonTitle rows because
    /// they duplicated the Course card and made the two cards read like
    /// competing surfaces on the same screen.
    private func todayCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's practice")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: summary.dailyProgressFraction)
                    .accessibilityIdentifier("home-daily-progress")
                Text(summary.practicedTodayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button(action: onContinueLearning) {
                    Label(continueLearningTitle, systemImage: "play.fill")
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

    /// Title for the Today-card CTA. When the course has a current
    /// lesson, name it so the button reads like a resumption, not a
    /// generic "Continue".
    private var continueLearningTitle: String {
        if let course = courseModel, case let .ready(loaded) = course.state,
           let current = loaded.currentLesson {
            return "Continue: \(current.title)"
        }
        return "Continue learning"
    }

    private func practiceCard(_ summary: LearnerProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice")
                .font(.headline)
            if summary.dueReviewCount > 0 || summary.recentSessionCount > 0 {
                HStack(spacing: 10) {
                    if summary.dueReviewCount > 0 {
                        statusPill("\(summary.dueReviewCount) due", "tray.full")
                    }
                    if summary.recentSessionCount > 0 {
                        statusPill("\(summary.recentSessionCount) sessions", "clock.arrow.circlepath")
                    }
                }
            }
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
        Button {
            onReviewPractice(title)
        } label: {
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-review-\(title.lowercased())")
    }

    private func statusPill(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.secondary.opacity(0.10), in: Capsule())
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
