#if canImport(SwiftUI)
import SwiftUI
import VoxaRealtime

/// Destination for a top-level route.
///
/// The Talk route hosts the Realtime voice session (`TalkView`) when a session
/// view model is provided; other routes render a Dynamic Type-friendly
/// placeholder until their own issues land.
struct RouteDestinationView: View {
    let route: AppRoute
    var talkModel: TalkSessionViewModel?

    var body: some View {
        if route == .talk, let talkModel {
            TalkView(model: talkModel)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
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
