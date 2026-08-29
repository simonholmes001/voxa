import Foundation

/// Persists the onboarding draft so an interrupted onboarding can be resumed.
///
/// This provides same-device resume. Cross-device resume (per #20) additionally
/// requires the backend to store profile/plan state; that sync is out of scope
/// for the iOS layer.
public protocol OnboardingDraftStore: Sendable {
    func load() throws -> OnboardingDraft?
    func save(_ draft: OnboardingDraft) throws
    func clear() throws
}

/// In-memory draft store for tests and previews.
public final class InMemoryOnboardingDraftStore: OnboardingDraftStore, @unchecked Sendable {
    private var draft: OnboardingDraft?

    public init(draft: OnboardingDraft? = nil) {
        self.draft = draft
    }

    public func load() throws -> OnboardingDraft? { draft }
    public func save(_ draft: OnboardingDraft) throws { self.draft = draft }
    public func clear() throws { draft = nil }
}

/// UserDefaults-backed draft store for same-device resume.
public struct UserDefaultsOnboardingDraftStore: OnboardingDraftStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.voxa.onboarding.draft") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> OnboardingDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(OnboardingDraft.self, from: data)
    }

    public func save(_ draft: OnboardingDraft) throws {
        defaults.set(try JSONEncoder().encode(draft), forKey: key)
    }

    public func clear() throws {
        defaults.removeObject(forKey: key)
    }
}
