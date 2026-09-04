import XCTest
@testable import VoxaRealtime

final class Copilot2HomeResumeTests: XCTestCase {
    func test_resume_returns_profile() async throws {
        let expected = LearnerProfile(goal: "vocab", minutesPerDay: 20, language: "fr-FR", proficiencyBand: "B1-B2")
        let fake = FakeProfileProvider(resumeResult: expected)

        let result = try await fake.resumeSession()
        XCTAssertEqual(result, expected)
    }

    func test_resume_defaults_not_overwrite() async throws {
        let expected = LearnerProfile(goal: "listening", minutesPerDay: 10, language: "es-ES", proficiencyBand: "A2-B1")
        let fake = FakeProfileProvider(resumeResult: expected)

        let result = try await fake.resumeSession()
        XCTAssertEqual(result?.goal, "listening")
        XCTAssertEqual(result?.minutesPerDay, 10)
    }

    func test_resume_failure_shows_error() async throws {
        let fake = FakeProfileProvider(shouldThrowResume: true)

        do {
            _ = try await fake.resumeSession()
            XCTFail("Expected throw")
        } catch {
            // expected
            XCTAssertTrue((error as NSError).domain == "FakeProfileProvider")
        }
    }
}
