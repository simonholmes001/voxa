/// Supplies the learner profile summary for the Home surface. Returns `nil`
/// when there is no profile yet (a new user).
public protocol LearnerProfileProviding: Sendable {
    func load() async throws -> LearnerProfileSummary?
}

/// A closure-backed provider whose loader runs on the main actor, so it can
/// safely read main-actor app state (view models) during composition.
public struct MainActorProfileProvider: LearnerProfileProviding {
    private let loader: @MainActor () async throws -> LearnerProfileSummary?

    public init(_ loader: @escaping @MainActor () async throws -> LearnerProfileSummary?) {
        self.loader = loader
    }

    public func load() async throws -> LearnerProfileSummary? {
        try await loader()
    }
}

/// Treats `primary` as the source of truth (e.g. server learner state) and only
/// falls back to `fallback` (e.g. the locally captured onboarding profile) when
/// `primary` throws — for example when the device is offline. If `primary`
/// succeeds with `nil` (no profile), that new-user result is returned as-is.
public struct FallbackProfileProvider: LearnerProfileProviding {
    private let primary: any LearnerProfileProviding
    private let fallback: any LearnerProfileProviding

    public init(primary: any LearnerProfileProviding, fallback: any LearnerProfileProviding) {
        self.primary = primary
        self.fallback = fallback
    }

    public func load() async throws -> LearnerProfileSummary? {
        do {
            return try await primary.load()
        } catch {
            return try await fallback.load()
        }
    }
}
