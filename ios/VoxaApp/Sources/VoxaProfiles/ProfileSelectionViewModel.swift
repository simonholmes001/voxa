import Observation

/// Drives the post-sign-in language-profile decision: zero profiles start
/// onboarding, one profile opens directly, and multiple profiles let the
/// learner choose. Selecting or adding a language never overwrites another
/// language's data (enforced by the backend's per-language idempotency).
@MainActor
@Observable
public final class ProfileSelectionViewModel {
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

    public init(service: any LanguageProfilesService) {
        self.service = service
    }

    /// The route the app should take once selection resolves: the active
    /// language key to open, or `nil` when onboarding is needed.
    public var resolvedActiveKey: String? { activeLanguageKey }

    public func load() async {
        state = .loading
        do {
            let list = try await service.list()
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
        } catch {
            state = .failed(Self.message(for: error))
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
