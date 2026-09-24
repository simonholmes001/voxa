import XCTest
@testable import VoxaProfiles

final class LearningReminderCopyTests: XCTestCase {
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

        let first = LearningReminderCopy.content(for: snapshot, variant: 0)
        let second = LearningReminderCopy.content(for: snapshot, variant: 1)

        XCTAssertNotEqual(first.body, second.body)
    }

    func testCompletedGoalCelebratesProgress() {
        let snapshot = LearningReminderSnapshot(
            languageName: "German", dailyMinutes: 15, minutesPracticedToday: 15)

        let content = LearningReminderCopy.content(for: snapshot)

        XCTAssertEqual(content.title, "Nice work in German today")
        XCTAssertTrue(content.body.contains("15-minute goal"))
    }
}
