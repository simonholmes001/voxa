import Observation

/// Drives the Home/Today surface: loads the learner profile and exposes a
/// minimal set of states for the view.
@MainActor
@Observable
public final class HomeViewModel {
    public enum State: Sendable, Equatable {
        case loading
        case ready(LearnerProfileSummary)
        case needsOnboarding
        case failed(String)
    }

    public private(set) var state: State = .loading

    private let provider: any LearnerProfileProviding
    private let messageForError: @Sendable (Error) -> String
    private let isAuthenticationFailure: @Sendable (Error) -> Bool
    private let onAuthenticationFailure: @MainActor @Sendable () async -> Void

    public init(
        provider: any LearnerProfileProviding,
        messageForError: @escaping @Sendable (Error) -> String = { _ in
            "We couldn't load your learning home. Check your connection and try again."
        },
        isAuthenticationFailure: @escaping @Sendable (Error) -> Bool = { _ in false },
        onAuthenticationFailure: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.provider = provider
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
}
