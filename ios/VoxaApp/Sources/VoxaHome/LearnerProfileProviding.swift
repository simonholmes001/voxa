/// Supplies the learner profile summary for the Home surface. Returns `nil`
/// when there is no profile yet (a new user).
public protocol LearnerProfileProviding: Sendable {
    func load() async throws -> LearnerProfileSummary?
}

/// A closure-backed provider whose loader runs on the main actor, so it can
/// safely read main-actor app state (view models) during composition.
public struct MainActorProfileProvider: LearnerProfileProviding {
    private let loader: @MainActor @Sendable () async throws -> LearnerProfileSummary?

    public init(_ loader: @escaping @MainActor @Sendable () async throws -> LearnerProfileSummary?) {
        self.loader = loader
    }

    public func load() async throws -> LearnerProfileSummary? {
        try await loader()
    }
}

/// Treats `primary` as the source of truth (e.g. server learner state). Fallback
/// is allowed only when the caller explicitly classifies the thrown error as
/// eligible, such as an offline transport failure.
public struct FallbackProfileProvider: LearnerProfileProviding {
    private let primary: any LearnerProfileProviding
    private let fallback: any LearnerProfileProviding
    private let shouldFallback: @Sendable (Error) -> Bool

    public init(
        primary: any LearnerProfileProviding,
        fallback: any LearnerProfileProviding,
        shouldFallback: @escaping @Sendable (Error) -> Bool
    ) {
        self.primary = primary
        self.fallback = fallback
        self.shouldFallback = shouldFallback
    }

    public func load() async throws -> LearnerProfileSummary? {
        do {
            return try await primary.load()
        } catch {
            guard shouldFallback(error) else {
                throw error
            }
            return try await fallback.load()
        }
    }
}
