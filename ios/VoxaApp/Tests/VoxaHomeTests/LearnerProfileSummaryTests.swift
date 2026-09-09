import XCTest
@testable import VoxaHome

final class LearnerProfileSummaryTests: XCTestCase {

    // MARK: - practicedTodayLabel

    func testPracticedTodayLabelForZeroMinutesShowsZeroOfTarget() {
        let summary = summary(seconds: 0, dailyMinutes: 15)
        XCTAssertEqual(summary.practicedTodayLabel, "0 of 15 minutes today")
    }

    func testPracticedTodayLabelForSubMinutePracticeShowsSecondsAndLessThanOneMinuteHint() {
        // Regression: a 30-second session used to round to "0 of 15 minutes
        // today", making it look like nothing was recorded. Now the label
        // surfaces the seconds directly.
        let summary = summary(seconds: 30, dailyMinutes: 15)
        XCTAssertEqual(summary.practicedTodayLabel, "30 sec today (< 1 min)")
    }

    func testPracticedTodayLabelForExactlyOneMinuteFlipsToMinutesRepresentation() {
        let summary = summary(seconds: 60, dailyMinutes: 15)
        XCTAssertEqual(summary.practicedTodayLabel, "1 of 15 minutes today")
    }

    func testPracticedTodayLabelForMultipleMinutesUsesMinutesRepresentation() {
        let summary = summary(seconds: 12 * 60 + 40, dailyMinutes: 15)
        XCTAssertEqual(summary.practicedTodayLabel, "12 of 15 minutes today")
    }

    // MARK: - dailyProgressFraction

    func testDailyProgressFractionAdvancesForSubMinuteSessionsToo() {
        // 30 seconds toward a 1-minute goal is 50% — the bar SHOULD show
        // half-filled even though the label rounds minutes.
        let summary = summary(seconds: 30, dailyMinutes: 1)
        XCTAssertEqual(summary.dailyProgressFraction, 0.5, accuracy: 0.001)
    }

    func testDailyProgressFractionSaturatesAtOne() {
        let summary = summary(seconds: 10 * 60, dailyMinutes: 5)
        XCTAssertEqual(summary.dailyProgressFraction, 1.0)
    }

    func testDailyProgressFractionIsZeroWhenDailyMinutesIsZero() {
        let summary = summary(seconds: 300, dailyMinutes: 0)
        XCTAssertEqual(summary.dailyProgressFraction, 0.0)
    }

    // MARK: - Helper

    private func summary(seconds: Int, dailyMinutes: Int) -> LearnerProfileSummary {
        LearnerProfileSummary(
            languageName: "French",
            levelName: "A1",
            goalName: "Travel",
            dailyMinutes: dailyMinutes,
            minutesPracticedToday: seconds / 60,
            secondsPracticedToday: seconds)
    }
}
