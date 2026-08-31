import XCTest
@testable import VoxaHome

private struct StubProvider: LearnerProfileProviding {
    let result: Result<LearnerProfileSummary?, Error>
    func load() async throws -> LearnerProfileSummary? { try result.get() }
}

private struct BoomError: Error {}

@MainActor
final class HomeViewModelTests: XCTestCase {
    private let summary = LearnerProfileSummary(
        languageName: "French", levelName: "B1", goalName: "Travel", dailyMinutes: 15
    )

    func testLoadReadyWhenProfileExists() async {
        let model = HomeViewModel(provider: StubProvider(result: .success(summary)))
        await model.load()
        XCTAssertEqual(model.state, .ready(summary))
    }

    func testLoadNeedsOnboardingWhenNoProfile() async {
        let model = HomeViewModel(provider: StubProvider(result: .success(nil)))
        await model.load()
        XCTAssertEqual(model.state, .needsOnboarding)
    }

    func testLoadFailedOnError() async {
        let model = HomeViewModel(provider: StubProvider(result: .failure(BoomError())))
        await model.load()
        guard case .failed = model.state else { return XCTFail("expected failed") }
    }

    func testRetryRecovers() async {
        // First fail, then succeed on retry with a different provider is not
        // possible with a single stub; use a mutable provider.
        final class Mutable: LearnerProfileProviding, @unchecked Sendable {
            var result: Result<LearnerProfileSummary?, Error>
            init(_ r: Result<LearnerProfileSummary?, Error>) { result = r }
            func load() async throws -> LearnerProfileSummary? { try result.get() }
        }
        let provider = Mutable(.failure(BoomError()))
        let model = HomeViewModel(provider: provider)
        await model.load()
        guard case .failed = model.state else { return XCTFail("expected failed") }

        provider.result = .success(summary)
        await model.retry()
        XCTAssertEqual(model.state, .ready(summary))
    }
}

final class FallbackProfileProviderTests: XCTestCase {
    private let server = LearnerProfileSummary(languageName: "Spanish", levelName: "A2", goalName: "Work", dailyMinutes: 10)
    private let local = LearnerProfileSummary(languageName: "French", levelName: "B1", goalName: "Travel", dailyMinutes: 15)

    func testUsesPrimaryWhenItSucceeds() async throws {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .success(server)),
            fallback: StubProvider(result: .success(local))
        )
        let result = try await provider.load()
        XCTAssertEqual(result, server)
    }

    func testFallsBackWhenPrimaryThrows() async throws {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .failure(BoomError())),
            fallback: StubProvider(result: .success(local))
        )
        let result = try await provider.load()
        XCTAssertEqual(result, local)
    }

    func testPrimaryNilIsReturnedWithoutFallback() async throws {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .success(nil)),
            fallback: StubProvider(result: .success(local))
        )
        let result = try await provider.load()
        XCTAssertNil(result)
    }

    func testPropagatesWhenBothThrow() async {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .failure(BoomError())),
            fallback: StubProvider(result: .failure(BoomError()))
        )
        do {
            _ = try await provider.load()
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
