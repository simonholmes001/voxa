import VoxaDomain

/// Namespace for the on-device learner-state persistence boundary.
///
/// The durable-store strategy and the learner-state resume API are defined by
/// issues #21 and #22. This module currently only establishes the persistence
/// module boundary so the app shell can depend on a stable target.
public enum VoxaPersistence {
    /// Marker used to prove the module boundary is wired before real storage
    /// lands in #21/#22.
    public static let moduleName = "VoxaPersistence"
}
