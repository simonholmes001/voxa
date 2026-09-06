import Observation
import os

/// Drives the post-sign-in language-profile decision: zero profiles start
/// onboarding, one profile opens directly, and multiple profiles let the
/// learner choose. Selecting or adding a language never overwrites another
/// language's data (enforced by the backend's per-language idempotency).
@MainActor
@Observable
public final class ProfileSelectionViewModel {
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "profile-selection")
    public enum State: Sendable, Equatable {
        case loading
        /// No language profiles yet — begin first-language onboarding.
        case needsOnboarding
        /// Exactly one profile — open it directly.
        case single(LanguageProfile)
        /// Multiple profiles — let the learner continue/choose/add.
        case multiple(active: String?, profiles: [LanguageProfile])
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var activeLanguageKey: String?

    private let service: any LanguageProfilesService
    private var inFlight: Task<Void, Never>?
    /// Monotonic identity of the newest `load()`. Only the load whose id still
    /// equals this may mutate `state` — see `performLoad(_:)`.
    private var currentLoadID: UInt64 = 0

    public init(service: any LanguageProfilesService) {
        self.service = service
    }

    /// The route the app should take once selection resolves: the active
    /// language key to open, or `nil` when onboarding is needed.
    public var resolvedActiveKey: String? { activeLanguageKey }

    /// Every language profile the learner has, across any resolved state. Used
    /// by the in-app language manager (More surface) to list and switch between
    /// parallel courses.
    public var allProfiles: [LanguageProfile] {
        switch state {
        case let .single(profile): return [profile]
        case let .multiple(_, profiles): return profiles
        default: return []
        }
    }

    /// Whether the learner has at least one language profile.
    public var hasProfiles: Bool { !allProfiles.isEmpty }

    /// Reloads the profile list — call after editing a language's settings or
    /// adding a new language so versions and membership stay current.
    public func refresh() async { await load() }

    /// Loads the language-profile list.
    ///
    /// Single-flight and identity-guarded. A newer `load()` cancels the older
    /// in-flight one and takes a fresh identity; **only the newest load may
    /// mutate `state`** (including the initial `.loading`). The work runs in an
    /// unstructured task so it is not torn down if the SwiftUI `.task` that
    /// triggered it is cancelled mid-flight. Guarding by identity rather than
    /// `Task.isCancelled` closes the window where a superseded task — whose body
    /// happens to run after a newer load already reached a terminal state — could
    /// clobber that state back to `.loading` and strand the UI.
    public func load() async {
        inFlight?.cancel()
        currentLoadID &+= 1
        let id = currentLoadID
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(id)
        }
        inFlight = task
        await task.value
    }

    /// Whether `id` is still the newest load; only then may state be mutated.
    private func isCurrentLoad(_ id: UInt64) -> Bool { id == currentLoadID }

    private func performLoad(_ id: UInt64) async {
        // Superseded before this task even started — do not touch state.
        guard isCurrentLoad(id) else {
            Self.logger.info("profile.load.superseded")
            return
        }
        state = .loading
        Self.logger.info("profile.load.start")
        do {
            let list = try await service.list()
            // Superseded by a newer load — that one owns the terminal state.
            guard isCurrentLoad(id) else {
                Self.logger.info("profile.load.superseded")
                return
            }
            activeLanguageKey = list.activeLanguageKey ?? list.profiles.first?.languageKey
            switch list.profiles.count {
            case 0:
                activeLanguageKey = nil
                state = .needsOnboarding
            case 1:
                let only = list.profiles[0]
                activeLanguageKey = only.languageKey
                state = .single(only)
            default:
                state = .multiple(active: activeLanguageKey, profiles: list.profiles)
            }
            Self.logger.info("profile.load.done count=\(list.profiles.count, privacy: .public) state=\(self.stateLabel, privacy: .public)")
        } catch {
            // A superseded or cancelled load never overwrites state; the
            // superseding load (or a re-trigger) will drive the terminal state.
            guard isCurrentLoad(id) else {
                Self.logger.info("profile.load.superseded")
                return
            }
            if error is CancellationError {
                Self.logger.info("profile.load.cancelled")
                return
            }
            state = .failed(Self.message(for: error))
            Self.logger.error("profile.load.failed error=\(String(describing: error), privacy: .public)")
        }
    }

    /// Switches the active language. On success `activeLanguageKey` reflects the
    /// server's new active key and the profile list is preserved.
    @discardableResult
    public func selectLanguage(_ languageKey: String) async -> Bool {
        do {
            let newActive = try await service.selectActive(languageKey: languageKey)
            activeLanguageKey = newActive
            if case let .multiple(_, profiles) = state {
                state = .multiple(active: newActive, profiles: profiles)
            }
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    public func retry() async {
        await load()
    }

    private var stateLabel: String {
        switch state {
        case .loading: return "loading"
        case .needsOnboarding: return "needsOnboarding"
        case .single: return "single"
        case .multiple: return "multiple"
        case .failed: return "failed"
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LanguageProfilesError.authenticationRequired:
            return "Please sign in again to continue."
        case LanguageProfilesError.notConfigured:
            return "Language profiles aren't configured for this build yet."
        case LanguageProfilesError.transport:
            return "We couldn't reach Voxa. Check your connection and try again."
        default:
            return "We couldn't load your languages. Please try again."
        }
    }
}
