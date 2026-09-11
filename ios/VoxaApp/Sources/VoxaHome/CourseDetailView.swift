#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// The full curriculum arc. Presented from Home's course card and gives the
/// learner sight of every lesson in their personalised course — completed
/// (with a checkmark), the current lesson (highlighted with a play glyph),
/// and everything still to come. Every row is tappable: the current lesson
/// starts a fresh session, a completed one offers to redo, an upcoming one
/// starts a guided lesson for that topic. The backend's out-of-order
/// handling (LearningSessionCompletionService) makes non-linear completion
/// safe — the arc's current pointer never leapfrogs.
public struct CourseDetailView: View {
    private let course: LearnerCourse
    private let onStartLesson: (PlannedLesson) -> Void
    private let onReassess: () -> Void
    private let onDismiss: () -> Void

    public init(
        course: LearnerCourse,
        onStartLesson: @escaping (PlannedLesson) -> Void,
        onReassess: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.course = course
        self.onStartLesson = onStartLesson
        self.onReassess = onReassess
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    lessonList
                }
                .padding()
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle("Your course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .accessibilityIdentifier("course-detail-close")
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(course.title)
                .font(.title2)
                .fontWeight(.bold)
            if course.totalLessons > 0 {
                Text(course.progressCaption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: course.progressFraction)
                    .accessibilityIdentifier("course-detail-progress")
            }
            Button {
                onReassess()
            } label: {
                Label("Reassess my course", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("course-detail-reassess")
        }
    }

    // MARK: - Lesson list

    private var lessonList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lessons")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(course.lessons) { lesson in
                lessonRow(lesson)
            }
        }
    }

    private func lessonRow(_ lesson: PlannedLesson) -> some View {
        Button {
            onStartLesson(lesson)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                statusGlyph(for: lesson)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title)
                        .font(.body)
                        .fontWeight(lesson.status == .current ? .semibold : .regular)
                        .foregroundColor(.primary)
                    Text(lesson.learningObjective)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    if lesson.estimatedMinutes > 0 {
                        Text("~\(lesson.estimatedMinutes) min")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(12)
            .background(rowBackground(for: lesson), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("course-detail-lesson-\(lesson.order)")
        .accessibilityLabel(accessibilityLabel(for: lesson))
    }

    @ViewBuilder
    private func statusGlyph(for lesson: PlannedLesson) -> some View {
        switch lesson.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        case .current:
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        case .pending:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func rowBackground(for lesson: PlannedLesson) -> Color {
        switch lesson.status {
        case .current: return .accentColor.opacity(0.12)
        case .completed: return .green.opacity(0.06)
        case .pending: return .secondary.opacity(0.06)
        }
    }

    private func accessibilityLabel(for lesson: PlannedLesson) -> String {
        let statusWord: String
        switch lesson.status {
        case .completed: statusWord = "Completed"
        case .current: statusWord = "Current"
        case .pending: statusWord = "Upcoming"
        }
        return "\(statusWord): \(lesson.title). \(lesson.learningObjective)"
    }
}

#Preview {
    let lessons: [PlannedLesson] = [
        PlannedLesson(lessonId: "l1", title: "Greeting people",
                      learningObjective: "Say hello and introduce yourself",
                      order: 1, estimatedMinutes: 15, status: .completed),
        PlannedLesson(lessonId: "l2", title: "Ordering food",
                      learningObjective: "Order a meal in a restaurant",
                      order: 2, estimatedMinutes: 15, status: .current),
        PlannedLesson(lessonId: "l3", title: "Getting around",
                      learningObjective: "Ask for and follow directions",
                      order: 3, estimatedMinutes: 15, status: .pending),
    ]
    return CourseDetailView(
        course: LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "German for travel — A1",
            lessons: lessons),
        onStartLesson: { _ in },
        onReassess: {},
        onDismiss: {})
}
#endif
