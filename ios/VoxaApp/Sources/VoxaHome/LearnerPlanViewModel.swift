import Observation
import VoxaRealtime

/// Fetches today's plan from the backend curriculum planner. Owned by
/// composition and injected into HomeView + PracticeHubView so both Today
/// cards render the same planner-driven recommendation.
///
/// On failure or when the service is unavailable, the state stays
/// `.failed(...)` or `.idle` and the Home / Practice views fall back to
/// the rule-based recommendation shipped in B3. The learner never sees a
/// blank card because of a network hiccup.
@MainActor
@Observable
public final class LearnerPlanViewModel {
    public private(set) var state: LearnerPlanState = .idle

    private let service: any LearnerPlanService
    private let accessTokenProvider: @MainActor @Sendable () -> String?
    private var inFlight: Task<Void, Never>?

    public init(
        service: any LearnerPlanService,
        accessTokenProvider: @escaping @MainActor @Sendable () -> String?
    ) {
        self.service = service
        self.accessTokenProvider = accessTokenProvider
    }

    /// Kicks off (or replaces) a load. Single-flight — a second call
    /// cancels the previous one before starting the new fetch.
    public func load() async {
        inFlight?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        inFlight = task
        await task.value
    }

    /// Explicitly clears the plan back to idle. Useful when the learner
    /// signs out or switches languages.
    public func reset() {
        inFlight?.cancel()
        inFlight = nil
        state = .idle
    }

    private func performLoad() async {
        guard let token = accessTokenProvider(), !token.isEmpty else {
            state = .failed("Please sign in again to load your learning plan.")
            return
        }
        state = .loading
        do {
            let plan = try await service.fetchTodayPlan(accessToken: token)
            state = .ready(plan)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LearnerPlanServiceError.authenticationRequired:
            return "Please sign in again to load your learning plan."
        case let LearnerPlanServiceError.notConfigured(reason):
            return reason
        case LearnerPlanServiceError.transport:
            return "We couldn't reach voxa to generate your plan. Using a general recommendation."
        case let LearnerPlanServiceError.server(code, _):
            return "The plan service returned an error (\(code)). Using a general recommendation."
        default:
            return "We couldn't generate a personalised plan this time."
        }
    }
}
