import Observation

/// Observable navigation state shared by the iPhone tab bar and iPad sidebar.
///
/// Keeping the selected route in a single model means the current destination
/// is preserved when the layout switches between tab bar and split view (for
/// example on rotation or multitasking size changes).
@Observable
public final class AppNavigationModel {
    /// The currently selected top-level route.
    public var selectedRoute: AppRoute

    public init(selectedRoute: AppRoute = .home) {
        self.selectedRoute = selectedRoute
    }

    /// Selects a top-level route.
    public func select(_ route: AppRoute) {
        selectedRoute = route
    }
}
