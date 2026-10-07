import XCTest
@testable import VoxaProfiles

final class LearningReminderCopyTests: XCTestCase {
    func testAuthorizedLoadedHomeStateSchedulesReminders() {
        let snapshot = LearningReminderSnapshot(
            languageName: "Greek", dailyMinutes: 10, minutesPracticedToday: 0)

        XCTAssertTrue(
            LearningReminderScheduling.shouldSchedule(
                snapshot: snapshot,
                notificationsAuthorized: true
            )
        )
    }

    func testAuthorizedUserWithoutLoadedHomeStateDoesNotScheduleOrClearByAccident() {
        XCTAssertFalse(
            LearningReminderScheduling.shouldSchedule(
                snapshot: nil,
                notificationsAuthorized: true
            )
        )
    }

    func testDeniedNotificationsNeverScheduleReminders() {
        let snapshot = LearningReminderSnapshot(
            languageName: "Greek", dailyMinutes: 10, minutesPracticedToday: 0)

        XCTAssertFalse(
            LearningReminderScheduling.shouldSchedule(
                snapshot: snapshot,
                notificationsAuthorized: false
            )
        )
    }

    func testDueReviewsAreCalledOut() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German", dailyMinutes: 15, minutesPracticedToday: 0, dueReviewCount: 3)

        let content = LearningReminderCopy.content(for: snapshot)

        XCTAssertEqual(content.title, "Your German review is ready")
        XCTAssertTrue(content.body.contains("3 reviews"))
    }

    func testPartialDailyProgressShowsRemainingTime() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German", dailyMinutes: 15, minutesPracticedToday: 6)

        let content = LearningReminderCopy.content(for: snapshot)

        XCTAssertEqual(content.title, "6 minutes of German logged")
        XCTAssertTrue(content.body.contains("9 more minutes"))
    }

    func testCopyVariesForScheduledDaysWhenNoProgressExists() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German", dailyMinutes: 15, minutesPracticedToday: 0)

        let messages = (0..<7).map { LearningReminderCopy.content(for: snapshot, variant: $0) }

        XCTAssertEqual(Set(messages.map(\.title)).count, 7)
        XCTAssertEqual(Set(messages.map(\.body)).count, 7)
    }

    func testLessonContextAppearsInFreshLearnerReminder() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German",
            dailyMinutes: 15,
            minutesPracticedToday: 0,
            currentLessonTitle: "Introducing yourself")

        let content = LearningReminderCopy.content(for: snapshot, variant: 2)

        XCTAssertTrue(content.title.contains("German") || content.title.contains("Introducing yourself"))
        XCTAssertTrue(content.body.contains("Introducing yourself"))
    }

    func testReviewCopyHasSevenDistinctPersonalizedVariants() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German",
            dailyMinutes: 15,
            minutesPracticedToday: 0,
            dueReviewCount: 3)

        let messages = (0..<7).map { LearningReminderCopy.content(for: snapshot, variant: $0) }

        XCTAssertEqual(Set(messages.map(\.title)).count, 7)
        XCTAssertTrue(messages.allSatisfy { $0.body.contains("3") })
    }

    func testCompletedGoalCelebratesProgress() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German", dailyMinutes: 15, minutesPracticedToday: 15)

        let content = LearningReminderCopy.content(for: snapshot)

        XCTAssertEqual(content.title, "Nice work in German today")
        XCTAssertTrue(content.body.contains("15-minute goal"))
    }
}
