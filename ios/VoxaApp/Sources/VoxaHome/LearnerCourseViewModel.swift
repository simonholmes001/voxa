import Observation
import VoxaRealtime

/// Owns the course fetch + reassess lifecycle. Home reads `state` to
/// render the course arc; a "Reassess my course" sheet drives
/// `reassess(request:)`; the `TalkSessionViewModel` may call `refresh()`
/// after a session ends so completion status reflects the just-recorded
/// lesson.
@MainActor
@Observable
public final class LearnerCourseViewModel {
    public private(set) var state: LearnerCourseState = .idle

    private let service: any LearnerCourseService
    private let accessTokenProvider: @MainActor @Sendable () -> String?
    private var inFlight: Task<Void, Never>?

    public init(
        service: any LearnerCourseService,
        accessTokenProvider: @escaping @MainActor @Sendable () -> String?
    ) {
        self.service = service
        self.accessTokenProvider = accessTokenProvider
    }

    /// Fetches (or re-fetches) the current course. Single-flight — a
    /// second call while the first is in flight cancels the earlier one.
    public func load() async {
        inFlight?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFetch()
        }
        inFlight = task
        await task.value
    }

    /// Runs a reassessment. `state` transitions through `.reassessing`
    /// (preserving the previous course so Home can render a "generating
    /// new plan" overlay without going blank), and lands on `.ready`
    /// with the new course. Failure surfaces a readable message.
    public func reassess(request reassessmentRequest: String?) async {
        inFlight?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReassess(request: reassessmentRequest)
        }
        inFlight = task
        await task.value
    }

    /// Explicitly clears the course, e.g. on sign-out / language switch.
    public func reset() {
        inFlight?.cancel()
        inFlight = nil
        state = .idle
    }

    private func performFetch() async {
        guard let token = accessTokenProvider(), !token.isEmpty else {
            state = .failed("Please sign in again to load your course.")
            return
        }
        // If we already had a course loaded, don't blank the screen on a
        // silent refresh — leave the existing course visible until the
        // new fetch resolves.
        if case .idle = state { state = .loading }
        if case .failed = state { state = .loading }
        do {
            let course = try await service.fetchCourse(accessToken: token)
            state = .ready(course)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private func performReassess(request reassessmentRequest: String?) async {
        guard let token = accessTokenProvider(), !token.isEmpty else {
            state = .failed("Please sign in again to reassess your course.")
            return
        }
        // Preserve the previous course through the reassess call so Home
        // can dim/overlay it rather than going blank while the model
        // works.
        let previous: LearnerCourse
        switch state {
        case let .ready(course):
            previous = course
        case let .reassessing(course):
            previous = course
        default:
            // No previous course to preserve — treat it as a plain load.
            await performFetch()
            return
        }
        state = .reassessing(previous: previous)
        do {
            let course = try await service.reassessCourse(
                request: reassessmentRequest,
                accessToken: token)
            state = .ready(course)
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LearnerCourseServiceError.authenticationRequired:
            return "Please sign in again to load your course."
        case let LearnerCourseServiceError.notConfigured(reason):
            return reason
        case LearnerCourseServiceError.notFound:
            return "Complete onboarding first to build your course."
        case LearnerCourseServiceError.transport:
            return "We couldn't reach voxa to load your course. Try again later."
        case let LearnerCourseServiceError.server(code, _):
            return "The course service returned an error (\(code)). Try again later."
        default:
            return "We couldn't load your course this time."
        }
    }
}
