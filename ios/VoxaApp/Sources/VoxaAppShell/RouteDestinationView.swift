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
        case .learn:
            MvpRouteView(
                route: route,
                symbol: "book.closed",
                title: "Build your next lesson",
                message: "Lessons will appear here after your learning plan is ready.",
                detail: "Start a Talk session to practise while lesson content is being prepared."
            )
        case .review:
            MvpRouteView(
                route: route,
                symbol: "arrow.triangle.2.circlepath",
                title: "Review when you're ready",
                message: "Your review queue will appear here after you complete a learning session.",
                detail: "There is nothing due yet."
            )
        case .settings:
            MvpRouteView(
                route: route,
                symbol: "person.crop.circle",
                title: "Your learning settings",
                message: "Language profiles and account preferences are managed here.",
                detail: "Select a language from the profile chooser to edit its onboarding settings."
            )
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

private struct MvpRouteView: View {
    let route: AppRoute
    let symbol: String
    let title: String
    let message: String
    let detail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(message)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(route.placeholderContent().headline)
    }
}

#Preview {
    RouteDestinationView(route: .learn)
}
#endif
