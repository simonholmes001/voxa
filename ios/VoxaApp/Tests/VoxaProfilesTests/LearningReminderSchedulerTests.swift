#if canImport(UserNotifications)
import Foundation
import UserNotifications
import XCTest
@testable import VoxaProfiles

@MainActor
final class LearningReminderSchedulerTests: XCTestCase {
    private let snapshot = LearningReminderSnapshot(
        languageName: "Greek", dailyMinutes: 15, minutesPracticedToday: 15,
        dueReviewCount: 42, recentSessionCount: 10)

    func testRemindersContinueBeyondTheFirstWeekWithOneRequestPerDay() async {
        let center = ReminderCenterFake()
        let defaults = makeDefaults()
        let result = await LearningReminderScheduler.schedule(snapshot: snapshot, on: center, defaults: defaults)

        XCTAssertEqual(result, .scheduled)
        XCTAssertEqual(center.requests.count, 7)
        let start = ISO8601DateFormatter().date(from: "2026-10-23T19:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var dates = [Date]()
        for request in center.requests.values {
            let trigger = request.trigger as! UNCalendarNotificationTrigger
            XCTAssertTrue(trigger.repeats)
            XCTAssertNil(trigger.dateComponents.year)
            XCTAssertNil(trigger.dateComponents.month)
            XCTAssertNil(trigger.dateComponents.day)
            var after = start
            for _ in 0..<9 {
                let next = calendar.nextDate(after: after, matching: trigger.dateComponents, matchingPolicy: .nextTime)!
                XCTAssertEqual(calendar.component(.hour, from: next), 18)
                dates.append(next)
                after = next
            }
        }
        XCTAssertEqual(Set(dates).count, 63)
        XCTAssertEqual(Set(center.requests.values.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday
        }), Set(1...7))
    }

    func testRecurringCopyDoesNotRepeatOldDailyProgressOrReviewCounts() async {
        let center = ReminderCenterFake()
        _ = await LearningReminderScheduler.schedule(snapshot: snapshot, on: center, defaults: makeDefaults())
        let evergreen = LearningReminderSnapshot(languageName: "Greek", dailyMinutes: 15, minutesPracticedToday: 0)
        let expected = Set((0..<7).map { LearningReminderCopy.content(for: evergreen, variant: $0).body })
        XCTAssertEqual(Set(center.requests.values.map(\.content.body)), expected)
    }

    func testMissingHomeDataUsesSavedSnapshotWithoutLosingSchedule() async {
        let defaults = makeDefaults()
        LearningReminderSnapshotStore.save(snapshot, defaults: defaults)
        let center = ReminderCenterFake()
        let result = await LearningReminderScheduler.schedule(snapshot: nil, on: center, defaults: defaults)
        XCTAssertEqual(result, .scheduled)
        XCTAssertEqual(center.requests.count, 7)
    }

    func testMissingSnapshotPreservesExistingRequestsAndDoesNotClaimEnabled() async {
        let center = ReminderCenterFake()
        center.requests["voxa.daily-learning-reminder"] = legacyRequest()
        let result = await LearningReminderScheduler.schedule(snapshot: nil, on: center, defaults: makeDefaults())
        XCTAssertEqual(result, .needsProfile)
        XCTAssertNotNil(center.requests["voxa.daily-learning-reminder"])
        XCTAssertTrue(center.removed.isEmpty)
    }

    func testFailedReplacementPreservesLegacyScheduleAndReportsFailure() async {
        let center = ReminderCenterFake()
        center.requests["voxa.daily-learning-reminder"] = legacyRequest()
        center.failAdding = true
        let result = await LearningReminderScheduler.schedule(snapshot: snapshot, on: center, defaults: makeDefaults())
        XCTAssertEqual(result, .failed)
        XCTAssertNotNil(center.requests["voxa.daily-learning-reminder"])
        XCTAssertTrue(center.removed.isEmpty)
    }

    func testPermissionAloneOrMissingPendingRequestsCannotReportScheduled() async {
        let center = ReminderCenterFake()
        center.discardAdds = true
        let result = await LearningReminderScheduler.schedule(snapshot: snapshot, on: center, defaults: makeDefaults())
        XCTAssertEqual(result, .failed)
    }

    func testRepeatedSchedulingReplacesInPlaceAndRetiresLegacyOnlyAfterVerification() async {
        let center = ReminderCenterFake()
        center.requests["voxa.daily-learning-reminder"] = legacyRequest()
        let defaults = makeDefaults()
        _ = await LearningReminderScheduler.schedule(snapshot: snapshot, on: center, defaults: defaults)
        let updated = LearningReminderSnapshot(languageName: "German", dailyMinutes: 10, minutesPracticedToday: 0)
        let result = await LearningReminderScheduler.schedule(snapshot: updated, on: center, defaults: defaults)
        XCTAssertEqual(result, .scheduled)
        XCTAssertEqual(center.requests.count, 7)
        XCTAssertEqual(center.removed, ["voxa.daily-learning-reminder", "voxa.daily-learning-reminder"])
        XCTAssertTrue(center.requests.values.allSatisfy { $0.content.title.contains("German") || $0.content.body.contains("German") })
        XCTAssertEqual(LearningReminderSnapshotStore.load(defaults: defaults), updated)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "LearningReminderSchedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func legacyRequest() -> UNNotificationRequest {
        UNNotificationRequest(identifier: "voxa.daily-learning-reminder", content: UNMutableNotificationContent(), trigger: nil)
    }
}

@MainActor
private final class ReminderCenterFake: LearningReminderNotificationCenter {
    var requests = [String: UNNotificationRequest]()
    var removed = [String]()
    var failAdding = false
    var discardAdds = false

    func add(_ request: UNNotificationRequest) async throws {
        if failAdding { throw NSError(domain: "ReminderTest", code: 1) }
        if !discardAdds { requests[request.identifier] = request }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        Array(requests.values)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removed.append(contentsOf: identifiers)
        identifiers.forEach { requests.removeValue(forKey: $0) }
    }
}
#endif
