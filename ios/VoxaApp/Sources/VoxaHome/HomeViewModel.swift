import Observation

/// Drives the Home/Today surface: loads the learner profile and exposes a
/// minimal set of states for the view.
@MainActor
@Observable
public final class HomeViewModel {
    public enum State: Sendable, Equatable {
        case loading
        case resuming
        case ready(LearnerProfileSummary)
        case needsOnboarding
        case failed(String)
    }

    public private(set) var state: State = .loading

    private let provider: any LearnerProfileProviding
    private let resumer: (any LearnerProfileResuming)?
    private let messageForError: @Sendable (Error) -> String
    private let isAuthenticationFailure: @Sendable (Error) -> Bool
    private let onAuthenticationFailure: @MainActor @Sendable () async -> Void

    public init(
        provider: any LearnerProfileProviding,
        resumer: (any LearnerProfileResuming)? = nil,
        messageForError: @escaping @Sendable (Error) -> String = { _ in
            "We couldn't load your learning home. Check your connection and try again."
        },
        isAuthenticationFailure: @escaping @Sendable (Error) -> Bool = { _ in false },
        onAuthenticationFailure: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.provider = provider
        self.resumer = resumer
        self.messageForError = messageForError
        self.isAuthenticationFailure = isAuthenticationFailure
        self.onAuthenticationFailure = onAuthenticationFailure
    }

    /// Loads the learner profile. New users (no profile) map to
    /// `needsOnboarding`; failures map to `failed` with a retry-friendly message.
    public func load() async {
        state = .loading
        do {
            if let summary = try await provider.load() {
                state = .ready(summary)
            } else {
                state = .needsOnboarding
            }
        } catch {
            state = .failed(messageForError(error))
            if isAuthenticationFailure(error) {
                await onAuthenticationFailure()
            }
        }
    }

    public func retry() async {
        await load()
    }

    // MARK: - Resume

    /// If a resumer has been provided by composition, attempt to resume a
    /// remote learner profile/session. On success the state transitions to
    /// `ready(_)`. If no resume is available the normal `load()` path is used.
    public func resumeIfAvailable() async {
        guard let resumer = resumer else { return }
        state = .resuming
        do {
            if let summary = try await resumer.resumeSession() {
                state = .ready(summary)
            } else {
                // No remote resume available: fall back to the normal load path
                await load()
            }
        } catch {
            state = .failed(messageForError(error))
            if isAuthenticationFailure(error) {
                await onAuthenticationFailure()
            }
        }
    }
}
