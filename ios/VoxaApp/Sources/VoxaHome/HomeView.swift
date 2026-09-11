#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The Home / Today surface shown after onboarding. It presents the learner's
/// active languages and a clear way back into the learning flow.
public struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let courseModel: LearnerCourseViewModel?
    private let talkModel: TalkSessionViewModel?
    private let languages: [LearnerLanguageSummary]
    private let onContinueLearning: () -> Void
    private let onVoicePractice: () -> Void
    private let onReviewPractice: (String) -> Void
    private let onSelectLanguage: (String) -> Void
    private let onStartTalk: (RealtimeTutorIntent) -> Void
    @State private var isPresentingReassessSheet = false

    public init(
        model: HomeViewModel,
        courseModel: LearnerCourseViewModel? = nil,
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
                    ReassessCourseSheet(model: courseModel) {
                        isPresentingReassessSheet = false
                    }
                }
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
            HStack {
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
        return "Lesson \(course.currentLessonIndex) of \(course.totalLessons)"
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
            if let plan = summary.activePlanTitle {
                Label(plan, systemImage: "map")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let lesson = summary.currentLessonTitle {
                Label(currentLessonText(lesson, stepIndex: summary.currentLessonStepIndex), systemImage: "bookmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: summary.dailyProgressFraction)
                    .accessibilityIdentifier("home-daily-progress")
                Text(summary.practicedTodayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private func currentLessonText(_ lesson: String, stepIndex: Int?) -> String {
        guard let stepIndex else { return "Continue \(lesson)" }
        return "Continue \(lesson), step \(stepIndex + 1)"
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
