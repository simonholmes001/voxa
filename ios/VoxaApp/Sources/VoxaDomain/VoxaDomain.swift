/// Namespace for Voxa domain models.
///
/// The canonical domain types, value objects, and their contracts are defined
/// by issue #14 ("Define canonical Voxa domain model and API contracts"). This
/// module currently exists only to establish the domain module boundary so the
/// app, networking, and persistence layers can depend on a stable target.
public enum VoxaDomain {
    /// Marker used to prove the module boundary is wired before real domain
    /// types land in #14.
    public static let moduleName = "VoxaDomain"
}
