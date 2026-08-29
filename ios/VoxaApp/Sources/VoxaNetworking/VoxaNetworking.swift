import VoxaDomain

/// Namespace for the Voxa backend networking boundary.
///
/// Mobile clients call Voxa backend endpoints only. They must never call
/// OpenAI or any other privileged service directly, and must not embed
/// privileged service credentials (see `docs/engineering-guidelines.md`).
///
/// Concrete API contracts (client-secret issuance, learner state, lessons)
/// are defined by issue #14. This module currently only establishes the
/// networking module boundary.
public enum VoxaNetworking {
    /// Marker used to prove the module boundary is wired before real API
    /// clients land in #14.
    public static let moduleName = "VoxaNetworking"
}
