import Foundation

/// Optional cross-device resume contract. Implementations attempt to restore
/// a prior onboarding/profile checkpoint (for example when the user signs in
/// on a new device).
public protocol LearnerProfileResuming: Sendable {
    func resumeSession() async throws -> LearnerProfileSummary?
}
