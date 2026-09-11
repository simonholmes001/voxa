#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The Progress tab. Renders real progress signals (course completion,
/// today's practice, review load) instead of the pre-E2 placeholder copy.
/// Reads from the `LearnerCourse` (for arc progress and the current
/// lesson) and the `LearnerProfileSummary` (for daily minutes, due
/// reviews, and recent-session count).
public struct ProgressDashboardView: View {
    private let summary: LearnerProfileSummary?
    private let courseState: LearnerCourseState
    private let onContinueLearning: () -> Void
    private let onStartTalk: (RealtimeTutorIntent) -> Void
    private let onOpenCourse: () -> Void

    public init(
        summary: LearnerProfileSummary?,
        courseState: LearnerCourseState = .idle,
        onContinueLearning: @escaping () -> Void,
        onStartTalk: @escaping (RealtimeTutorIntent) -> Void,
        onOpenCourse: @escaping () -> Void
    ) {
        self.summary = summary
        self.courseState = courseState
        self.onContinueLearning = onContinueLearning
        self.onStartTalk = onStartTalk
        self.onOpenCourse = onOpenCourse
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                courseProgressCard
                statsGrid
                currentLessonCard
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Progress")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your progress")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .textCase(.uppercase)
            Text(headline)
                .font(.title)
                .fontWeight(.bold)
            if let summary {
                Text("\(summary.levelName) · \(summary.dailyMinutes) min/day target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        guard let summary else { return "Getting started" }
        return "\(summary.languageName) in motion"
    }

    // MARK: - Course progress card

    @ViewBuilder
    private var courseProgressCard: some View {
        switch courseState {
        case .idle, .loading:
            statCard(title: "Course", body: {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading your course…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            })
        case let .ready(course):
            courseProgressBody(course)
        case let .reassessing(previous):
            courseProgressBody(previous)
        case .failed:
            statCard(title: "Course", body: {
                Text("Couldn't load your course.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            })
        }
    }

    private func courseProgressBody(_ course: LearnerCourse) -> some View {
        let completed = course.lessons.filter { $0.status == .completed }.count
        return statCard(title: "Course", body: {
            VStack(alignment: .leading, spacing: 10) {
                Text(course.title)
                    .font(.headline)
                Text("\(completed) of \(course.totalLessons) lessons complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: course.progressFraction)
                    .accessibilityIdentifier("progress-course-bar")
                Button(action: onOpenCourse) {
                    Label("See lesson plan", systemImage: "list.bullet")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("progress-see-course")
            }
        })
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            todayStat
            reviewStat
            sessionsStat
        }
    }

    private var todayStat: some View {
        smallStat(
            title: "Today",
            symbol: "clock",
            headline: summary.map { $0.practicedTodayLabel } ?? "0 min today",
            subtitle: summary.map { "Target \($0.dailyMinutes) min" } ?? "Set a daily target in More",
            progress: summary?.dailyProgressFraction ?? 0,
            identifier: "progress-today")
    }

    private var reviewStat: some View {
        let count = summary?.dueReviewCount ?? 0
        return smallStat(
            title: "Reviews",
            symbol: "tray.full",
            headline: count == 0 ? "None due" : "\(count) due",
            subtitle: count == 0
                ? "Reviews build up as you learn."
                : "Tap Review to work through them.",
            progress: nil,
            identifier: "progress-reviews")
    }

    private var sessionsStat: some View {
        let count = summary?.recentSessionCount ?? 0
        return smallStat(
            title: "Sessions",
            symbol: "waveform",
            headline: count == 0 ? "None yet" : "\(count) recent",
            subtitle: count == 0
                ? "Your first Talk session will show up here."
                : "Keep the streak going.",
            progress: nil,
            identifier: "progress-sessions")
    }

    // MARK: - Current lesson

    @ViewBuilder
    private var currentLessonCard: some View {
        if case let .ready(course) = courseState, let current = course.currentLesson {
            statCard(title: "Next up", body: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(current.title)
                        .font(.headline)
                    Text(current.learningObjective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        onStartTalk(current.intent)
                    } label: {
                        Label("Start this lesson", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("progress-start-current")
                }
            })
        } else if case let .reassessing(previous) = courseState, let current = previous.currentLesson {
            statCard(title: "Next up", body: {
                Text(current.title)
                    .font(.headline)
            })
        } else {
            statCard(title: "Continue", body: {
                Button(action: onContinueLearning) {
                    Label("Continue learning", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("progress-continue")
            })
        }
    }

    // MARK: - Card shells

    private func statCard<Content: View>(title: String, @ViewBuilder body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            body()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func smallStat(
        title: String,
        symbol: String,
        headline: String,
        subtitle: String,
        progress: Double?,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(headline)
                .font(.headline)
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            if let progress {
                ProgressView(value: progress)
                    .controlSize(.mini)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 120, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    NavigationStack {
        ProgressDashboardView(
            summary: LearnerProfileSummary(
                languageName: "German",
                levelName: "A1",
                goalName: "Travel",
                dailyMinutes: 30,
                dueReviewCount: 3,
                recentSessionCount: 7,
                minutesPracticedToday: 12,
                secondsPracticedToday: 720),
            courseState: .ready(LearnerCourse(
                correlationId: "c",
                planId: "p",
                title: "German for travel — A1",
                lessons: [
                    PlannedLesson(lessonId: "l1", title: "Greetings",
                                  learningObjective: "Say hello", order: 1,
                                  estimatedMinutes: 15, status: .completed),
                    PlannedLesson(lessonId: "l2", title: "Ordering food",
                                  learningObjective: "Order a meal", order: 2,
                                  estimatedMinutes: 15, status: .current),
                    PlannedLesson(lessonId: "l3", title: "Getting around",
                                  learningObjective: "Follow directions", order: 3,
                                  estimatedMinutes: 15, status: .pending),
                ])),
            onContinueLearning: {},
            onStartTalk: { _ in },
            onOpenCourse: {})
    }
}
#endif
