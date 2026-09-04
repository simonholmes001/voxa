import XCTest
@testable import VoxaHome

private struct StubProvider: LearnerProfileProviding {
    let result: Result<LearnerProfileSummary?, Error>
    func load() async throws -> LearnerProfileSummary? { try result.get() }
}

private struct BoomError: Error {}
private enum AuthRequiredError: Error {
    case authenticationRequired
}

private struct StubResumer: LearnerProfileResuming {
    let result: Result<LearnerProfileSummary?, Error>

    func resumeSession() async throws -> LearnerProfileSummary? {
        try result.get()
    }
}

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

    func testLoadAuthFailureUsesSignInMessage() async {
        var authFailureCount = 0
        let model = HomeViewModel(
            provider: StubProvider(result: .failure(AuthRequiredError.authenticationRequired)),
            messageForError: { error in
                error as? AuthRequiredError == .authenticationRequired
                    ? "Please sign in again to load your learning home."
                    : "fallback"
            },
            isAuthenticationFailure: { error in
                error as? AuthRequiredError == .authenticationRequired
            },
            onAuthenticationFailure: {
                authFailureCount += 1
            }
        )
        await model.load()
        XCTAssertEqual(model.state, .failed("Please sign in again to load your learning home."))
        XCTAssertEqual(authFailureCount, 1)
    }

    func testLoadNonAuthFailureDoesNotTriggerAuthenticationFailure() async {
        var authFailureCount = 0
        let model = HomeViewModel(
            provider: StubProvider(result: .failure(BoomError())),
            isAuthenticationFailure: { error in
                error as? AuthRequiredError == .authenticationRequired
            },
            onAuthenticationFailure: {
                authFailureCount += 1
            }
        )
        await model.load()
        guard case .failed = model.state else { return XCTFail("expected failed") }
        XCTAssertEqual(authFailureCount, 0)
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

    func testResumeWithoutResumerLoadsProvider() async {
        let model = HomeViewModel(provider: StubProvider(result: .success(summary)))

        await model.resumeIfAvailable()

        XCTAssertEqual(model.state, .ready(summary))
    }

    func testResumeTransportFailureUsesLocalProviderFallback() async {
        let localSummary = LearnerProfileSummary(
            languageName: "French", levelName: "B1", goalName: "Travel", dailyMinutes: 15, isStale: true
        )
        let model = HomeViewModel(
            provider: StubProvider(result: .success(localSummary)),
            resumer: StubResumer(result: .failure(BoomError())),
            isFallbackEligible: { _ in true },
            isAuthenticationFailure: { error in
                error is AuthRequiredError
            }
        )

        await model.resumeIfAvailable()

        XCTAssertEqual(model.state, .ready(localSummary))
    }
}

final class FallbackProfileProviderTests: XCTestCase {
    private let server = LearnerProfileSummary(languageName: "Spanish", levelName: "A2", goalName: "Work", dailyMinutes: 10)
    private let local = LearnerProfileSummary(languageName: "French", levelName: "B1", goalName: "Travel", dailyMinutes: 15)

    func testUsesPrimaryWhenItSucceeds() async throws {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .success(server)),
            fallback: StubProvider(result: .success(local)),
            shouldFallback: { _ in true }
        )
        let result = try await provider.load()
        XCTAssertEqual(result, server)
    }

    func testFallsBackWhenPrimaryThrows() async throws {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .failure(BoomError())),
            fallback: StubProvider(result: .success(local)),
            shouldFallback: { _ in true }
        )
        let result = try await provider.load()
        XCTAssertEqual(result, local)
    }

    func testDoesNotFallBackWhenPrimaryErrorIsNotEligible() async {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .failure(BoomError())),
            fallback: StubProvider(result: .success(local)),
            shouldFallback: { _ in false }
        )

        do {
            _ = try await provider.load()
            XCTFail("expected primary error to be rethrown")
        } catch {
            XCTAssertTrue(error is BoomError)
        }
    }

    func testPrimaryNilIsReturnedWithoutFallback() async throws {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .success(nil)),
            fallback: StubProvider(result: .success(local)),
            shouldFallback: { _ in true }
        )
        let result = try await provider.load()
        XCTAssertNil(result)
    }

    func testPropagatesWhenBothThrow() async {
        let provider = FallbackProfileProvider(
            primary: StubProvider(result: .failure(BoomError())),
            fallback: StubProvider(result: .failure(BoomError())),
            shouldFallback: { _ in true }
        )
        do {
            _ = try await provider.load()
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
