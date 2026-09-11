import XCTest
@testable import VoxaRealtime

final class LearnerCourseModelsTests: XCTestCase {

    // MARK: - PlannedLessonStatus

    func testStatusParseAcceptsExactCaseFromServer() {
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: "Pending"), .pending)
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: "Current"), .current)
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: "Completed"), .completed)
    }

    func testStatusParseIsCaseInsensitive() {
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: "CURRENT"), .current)
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: "completed"), .completed)
    }

    func testStatusParseFallsBackToPendingForUnknownValues() {
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: "scheduled"), .pending)
        XCTAssertEqual(PlannedLessonStatus(rawFromServer: ""), .pending)
    }

    // MARK: - LearnerCourse.currentLesson

    func testCurrentLessonPrefersExplicitlyCurrentOverFirstPending() {
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: [
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l2", order: 2, status: .current),
                lesson(id: "l3", order: 3, status: .pending),
            ])
        XCTAssertEqual(course.currentLesson?.lessonId, "l2")
    }

    func testCurrentLessonFallsBackToFirstPendingWhenNothingIsCurrent() {
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: [
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l2", order: 2, status: .pending),
                lesson(id: "l3", order: 3, status: .pending),
            ])
        XCTAssertEqual(course.currentLesson?.lessonId, "l2")
    }

    func testCurrentLessonIsNilWhenCourseFullyCompleted() {
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: [
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l2", order: 2, status: .completed),
            ])
        XCTAssertNil(course.currentLesson)
    }

    // MARK: - LearnerCourse ordering

    func testInitSortsLessonsByOrderRegardlessOfInputOrder() {
        // Server returns unordered — the Home hero should still render
        // "Lesson 1 → Lesson 2 → Lesson 3" in the arc list.
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: [
                lesson(id: "l2", order: 2, status: .current),
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l3", order: 3, status: .pending),
            ])
        XCTAssertEqual(course.lessons.map(\.order), [1, 2, 3])
    }

    // MARK: - LearnerCourse.currentLessonIndex

    func testCurrentLessonIndexReturnsOneBasedIndexForHomeLabel() {
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: [
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l2", order: 2, status: .current),
                lesson(id: "l3", order: 3, status: .pending),
            ])
        XCTAssertEqual(course.currentLessonIndex, 2)
    }

    func testCurrentLessonIndexReturnsTotalWhenCourseCompleted() {
        // "Lesson 27 of 27" — a completed course still shows a coherent
        // label rather than "0 of 27".
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "Everyday German",
            lessons: [
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l2", order: 2, status: .completed),
            ])
        XCTAssertEqual(course.currentLessonIndex, 2)
    }

    // MARK: - progressFraction

    func testProgressFractionIsCompletedOverTotal() {
        let course = LearnerCourse(
            correlationId: "c",
            planId: "p",
            title: "…",
            lessons: [
                lesson(id: "l1", order: 1, status: .completed),
                lesson(id: "l2", order: 2, status: .completed),
                lesson(id: "l3", order: 3, status: .current),
                lesson(id: "l4", order: 4, status: .pending),
            ])
        XCTAssertEqual(course.progressFraction, 0.5, accuracy: 0.001)
    }

    func testProgressFractionIsZeroWhenNoLessons() {
        let course = LearnerCourse(correlationId: "c", planId: "p", title: "…", lessons: [])
        XCTAssertEqual(course.progressFraction, 0)
    }

    // MARK: - PlannedLesson.intent

    func testPlannedLessonIntentIsLessonWithTitle() {
        let l = lesson(id: "l1", order: 1, status: .current)
        XCTAssertEqual(l.intent, .lesson(title: l.title))
    }

    // MARK: - Helper

    private func lesson(id: String, order: Int, status: PlannedLessonStatus) -> PlannedLesson {
        PlannedLesson(
            lessonId: id,
            title: "Lesson \(order)",
            learningObjective: "Do a thing.",
            order: order,
            estimatedMinutes: 15,
            status: status)
    }
}
