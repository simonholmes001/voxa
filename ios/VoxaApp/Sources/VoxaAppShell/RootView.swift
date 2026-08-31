#if canImport(SwiftUI)
import SwiftUI
import VoxaAuth
import VoxaHome
import VoxaOnboarding
import VoxaRealtime

/// The root of the Voxa app. It composes the app's gates around the adaptive
/// navigation shell: first Sign in with Apple, then first-run onboarding, then
/// the tab bar (compact width) or split view (regular width).
public struct RootView: View {
    @State private var navigationModel: AppNavigationModel
    @State private var authModel: AuthViewModel
    @State private var onboardingModel: OnboardingViewModel
    private let homeModel: HomeViewModel?
    private let talkModel: TalkSessionViewModel?

    public init(
        navigationModel: AppNavigationModel = AppNavigationModel(),
        authModel: AuthViewModel? = nil,
        onboardingModel: OnboardingViewModel? = nil,
        homeModel: HomeViewModel? = nil,
        talkModel: TalkSessionViewModel? = nil
    ) {
        _navigationModel = State(initialValue: navigationModel)
        _authModel = State(initialValue: authModel ?? AuthViewModel())
        _onboardingModel = State(initialValue: onboardingModel ?? OnboardingViewModel())
        self.homeModel = homeModel
        self.talkModel = talkModel
    }

    public var body: some View {
        AuthGate(model: authModel) {
            OnboardingGate(model: onboardingModel) {
                MainShellView(model: navigationModel, homeModel: homeModel, talkModel: talkModel)
            }
        }
        .task { await authModel.restore() }
        .task(id: authenticatedUserScope) {
            guard let session = authModel.state.session else { return }
            onboardingModel.scope(toTenantId: session.tenantId, userId: session.userId)
        }
    }

    private var authenticatedUserScope: String? {
        guard let session = authModel.state.session else { return nil }
        return "\(session.tenantId)|\(session.userId)"
    }
}

/// The adaptive navigation shell shown once the learner is signed in.
///
/// It reads the horizontal size class and presents either a tab bar (compact
/// width, typically iPhone) or a split/sidebar layout (regular width, typically
/// iPad). The selected route lives in `AppNavigationModel`, so the current
/// destination is preserved when the layout changes on rotation or
/// multitasking size changes.
struct MainShellView: View {
    var model: AppNavigationModel
    var homeModel: HomeViewModel?
    var talkModel: TalkSessionViewModel?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        switch AdaptiveLayoutResolver.layout(for: resolvedSizeClass) {
        case .tabBar:
            TabLayout(model: model, homeModel: homeModel, talkModel: talkModel)
        case .splitView:
            SplitLayout(model: model, homeModel: homeModel, talkModel: talkModel)
        }
    }

    private var resolvedSizeClass: InterfaceSizeClass? {
        #if os(iOS)
        switch horizontalSizeClass {
        case .compact: return .compact
        case .regular: return .regular
        default: return nil
        }
        #else
        return .regular
        #endif
    }
}

/// Compact-width layout: a bottom tab bar over the primary routes.
private struct TabLayout: View {
    @Bindable var model: AppNavigationModel
    var homeModel: HomeViewModel?
    var talkModel: TalkSessionViewModel?

    var body: some View {
        TabView(selection: $model.selectedRoute) {
            ForEach(AppRoute.allCases) { route in
                NavigationStack {
                    RouteDestinationView(
                        route: route,
                        homeModel: homeModel,
                        talkModel: talkModel,
                        onStartTalk: { model.selectedRoute = .talk }
                    )
                }
                .tabItem {
                    Label(route.title, systemImage: route.systemImageName)
                }
                .tag(route)
            }
        }
    }
}

/// Regular-width layout: a sidebar of routes with a detail column.
private struct SplitLayout: View {
    @Bindable var model: AppNavigationModel
    var homeModel: HomeViewModel?
    var talkModel: TalkSessionViewModel?

    var body: some View {
        NavigationSplitView {
            List(AppRoute.allCases, selection: sidebarSelection) { route in
                Label(route.title, systemImage: route.systemImageName)
                    .tag(route)
            }
            .navigationTitle("Voxa")
        } detail: {
            NavigationStack {
                RouteDestinationView(
                    route: model.selectedRoute,
                    homeModel: homeModel,
                    talkModel: talkModel,
                    onStartTalk: { model.selectedRoute = .talk }
                )
            }
        }
    }

    private var sidebarSelection: Binding<AppRoute?> {
        Binding(
            get: { model.selectedRoute },
            set: { newValue in
                if let newValue {
                    model.selectedRoute = newValue
                }
            }
        )
    }
}

#Preview {
    RootView(
        authModel: AuthViewModel(
            store: EphemeralSessionStore(
                session: AuthSession(
                    accessToken: "preview",
                    refreshToken: "preview",
                    expiresAt: .distantFuture,
                    refreshTokenExpiresAt: .distantFuture,
                    userId: "preview-user",
                    tenantId: "preview-tenant"
                )
            )
        ),
        onboardingModel: OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(draft: OnboardingDraft(isCompleted: true))
        )
    )
}
#endif
