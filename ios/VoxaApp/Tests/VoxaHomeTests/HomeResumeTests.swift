import XCTest
@testable import VoxaHome

private final class FakeResumer: LearnerProfileResuming, @unchecked Sendable {
    var result: Result<LearnerProfileSummary?, Error>
    init(result: Result<LearnerProfileSummary?, Error>) { self.result = result }
    func resumeSession() async throws -> LearnerProfileSummary? {
        return try result.get()
    }
}

private struct LocalStubProvider: LearnerProfileProviding {
    let result: Result<LearnerProfileSummary?, Error>
    func load() async throws -> LearnerProfileSummary? { try result.get() }
}

@MainActor
final class HomeResumeTests: XCTestCase {
    func test_resume_sets_ready_when_profile_present() async throws {
        let summary = LearnerProfileSummary(languageName: "French", levelName: "B1-B2", goalName: "vocab", dailyMinutes: 20)
        let resumer = FakeResumer(result: Result<LearnerProfileSummary?, Error>.success(summary))
        let provider = LocalStubProvider(result: Result<LearnerProfileSummary?, Error>.success(nil))
        let model = HomeViewModel(provider: provider, resumer: resumer)

        await model.resumeIfAvailable()

        XCTAssertEqual(model.state, HomeViewModel.State.ready(summary))
    }

    func test_resume_failure_sets_failed() async throws {
        let resumer = FakeResumer(result: Result<LearnerProfileSummary?, Error>.failure(NSError(domain: "x", code: -1)))
        let provider = LocalStubProvider(result: Result<LearnerProfileSummary?, Error>.success(nil))
        let model = HomeViewModel(provider: provider, resumer: resumer)

        await model.resumeIfAvailable()

        if case .failed = model.state { /* expected */ } else {
            XCTFail("expected failed state")
        }
    }
}
