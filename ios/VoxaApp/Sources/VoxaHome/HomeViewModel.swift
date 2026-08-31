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

    public init(provider: any LearnerProfileProviding) {
        self.provider = provider
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
            state = .failed("We couldn't load your learning home. Check your connection and try again.")
        }
    }

    public func retry() async {
        await load()
    }
}
