#if canImport(SwiftUI)
import SwiftUI
import VoxaHome
import VoxaRealtime

/// Destination for a top-level route.
///
/// The Home route hosts the Home/Today surface and the Talk route hosts the
/// Realtime voice session, when their view models are provided; other routes
/// render a Dynamic Type-friendly placeholder until their own issues land.
struct RouteDestinationView: View {
    let route: AppRoute
    var homeModel: HomeViewModel?
    var talkModel: TalkSessionViewModel?
    var onStartTalk: () -> Void = {}

    var body: some View {
        switch route {
        case .home where homeModel != nil:
            HomeView(model: homeModel!, onStartTalk: onStartTalk)
        case .talk where talkModel != nil:
            TalkView(model: talkModel!)
        default:
            placeholder
        }
    }

    private var placeholder: some View {
        let content = route.placeholderContent()
        return VStack(spacing: 12) {
            Image(systemName: route.systemImageName)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(content.headline)
                .font(.title2)
                .fontWeight(.semibold)
            Text(content.subheadline)
                .font(.body)
                .foregroundStyle(.secondary)
            if let action = content.actionTitle {
                Button(action) { }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("placeholder-action-\(route.rawValue)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(route.title)
    }
}

#Preview {
    RouteDestinationView(route: .learn)
}
#endif
