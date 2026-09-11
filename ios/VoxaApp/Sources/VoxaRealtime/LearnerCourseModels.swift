import Foundation

/// The learner's course arc — the ordered list of lessons that makes up
/// their personalised curriculum. Home renders this as the hero row
/// ("You're on lesson 4 of 27") and a scrollable lesson list. Ships from
/// the backend `GET /api/learner/course` and mutates via
/// `POST /api/learner/course/reassess`.
public struct LearnerCourse: Sendable, Equatable {
    public let correlationId: String
    public let planId: String
    public let title: String
    public let lessons: [PlannedLesson]

    public init(correlationId: String, planId: String, title: String, lessons: [PlannedLesson]) {
        self.correlationId = correlationId
        self.planId = planId
        self.title = title
        self.lessons = lessons.sorted { $0.order < $1.order }
    }

    /// The single lesson the learner should see as "current" in the Home
    /// arc. First `.current`, else first `.pending`, else nil when the
    /// course is fully completed.
    public var currentLesson: PlannedLesson? {
        return lessons.first(where: { $0.status == .current })
            ?? lessons.first(where: { $0.status == .pending })
    }

    /// One-based index of the current lesson for the "lesson N of M"
    /// progress label. Falls back to the count when the course is fully
    /// completed so the label reads "27 of 27".
    public var currentLessonIndex: Int {
        if let current = currentLesson,
           let index = lessons.firstIndex(where: { $0.lessonId == current.lessonId }) {
            return index + 1
        }
        return lessons.count
    }

    public var totalLessons: Int { lessons.count }

    /// Progress fraction (0…1) suitable for a ProgressView. Counts
    /// completed lessons over total.
    public var progressFraction: Double {
        guard !lessons.isEmpty else { return 0 }
        let completed = lessons.filter { $0.status == .completed }.count
        return Double(completed) / Double(lessons.count)
    }

    /// Number of lessons in the arc the learner has completed.
    public var completedLessonCount: Int {
        lessons.filter { $0.status == .completed }.count
    }

    /// One-line caption for the Home/Progress/CourseDetail cards. Adjusts
    /// so an unstarted, mid-course, and fully-completed arc each read
    /// naturally:
    ///  - unstarted (0 done): "Lesson 1 of 28"
    ///  - mid-course:         "Lesson 4 of 28 · 3 done"
    ///  - complete (N of N):  "28 of 28 — course complete"
    public var progressCaption: String {
        let completed = completedLessonCount
        let total = totalLessons
        if total == 0 { return "" }
        if completed == 0 {
            return "Lesson \(currentLessonIndex) of \(total)"
        }
        if completed == total {
            return "\(total) of \(total) — course complete"
        }
        return "Lesson \(currentLessonIndex) of \(total) · \(completed) done"
    }
}

public struct PlannedLesson: Sendable, Equatable, Identifiable {
    public var id: String { lessonId }
    public let lessonId: String
    public let title: String
    public let learningObjective: String
    public let order: Int
    public let estimatedMinutes: Int
    public let status: PlannedLessonStatus

    public init(
        lessonId: String,
        title: String,
        learningObjective: String,
        order: Int,
        estimatedMinutes: Int,
        status: PlannedLessonStatus
    ) {
        self.lessonId = lessonId
        self.title = title
        self.learningObjective = learningObjective
        self.order = order
        self.estimatedMinutes = estimatedMinutes
        self.status = status
    }

    /// The `RealtimeTutorIntent` a Home lesson-tap should launch. Guided
    /// lesson carries the lesson title so the tutor prompt sees the
    /// concrete focus.
    public var intent: RealtimeTutorIntent {
        return .lesson(title: title)
    }
}

public enum PlannedLessonStatus: String, Sendable, Equatable {
    case pending = "Pending"
    case current = "Current"
    case completed = "Completed"

    /// Case-insensitive parse for the JSON payload from the backend.
    /// Unknown strings fall back to `.pending` so a schema drift on the
    /// server doesn't hide the entire course.
    public init(rawFromServer: String) {
        switch rawFromServer.lowercased() {
        case "current": self = .current
        case "completed": self = .completed
        default: self = .pending
        }
    }
}

public enum LearnerCourseState: Sendable, Equatable {
    case idle
    case loading
    case ready(LearnerCourse)
    case failed(String)
    /// Distinct from `.loading` — used by the reassess flow so the UI
    /// can show a "Reassessing your course…" message instead of the
    /// generic loading spinner.
    case reassessing(previous: LearnerCourse)
}

public protocol LearnerCourseService: Sendable {
    func fetchCourse(accessToken: String) async throws -> LearnerCourse
    func reassessCourse(
        request: String?,
        accessToken: String
    ) async throws -> LearnerCourse
}

public enum LearnerCourseServiceError: Error, Equatable {
    case notConfigured(reason: String)
    case authenticationRequired
    case notFound
    case transport
    case server(code: Int, message: String)
}

public struct NotConfiguredLearnerCourseService: LearnerCourseService {
    private let reason: String

    public init(reason: String = "Personalised courses aren't configured for this build yet.") {
        self.reason = reason
    }

    public func fetchCourse(accessToken: String) async throws -> LearnerCourse {
        throw LearnerCourseServiceError.notConfigured(reason: reason)
    }

    public func reassessCourse(request: String?, accessToken: String) async throws -> LearnerCourse {
        throw LearnerCourseServiceError.notConfigured(reason: reason)
    }
}
