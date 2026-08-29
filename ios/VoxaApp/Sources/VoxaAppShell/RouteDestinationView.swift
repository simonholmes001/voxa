#if canImport(SwiftUI)
import SwiftUI

/// Placeholder destination for a top-level route.
///
/// Each MVP screen (Home, Talk, Learn, Review, Progress, Settings) will be
/// implemented in its own issue. This view establishes that the route exists
/// and renders with Dynamic Type-friendly system fonts so navigation and
/// layout remain intact across text sizes and orientations.
struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: route.systemImageName)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(route.title)
                .font(.title2)
                .fontWeight(.semibold)
            Text("Coming soon")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(route.title)
    }
}

#Preview {
    RouteDestinationView(route: .home)
}
#endif
