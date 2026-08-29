#if canImport(SwiftUI)
import SwiftUI
import VoxaAuth
import VoxaOnboarding

/// The root of the Voxa app. It composes the app's gates around the adaptive
/// navigation shell: first Sign in with Apple, then first-run onboarding, then
/// the tab bar (compact width) or split view (regular width).
public struct RootView: View {
    @State private var navigationModel: AppNavigationModel
    @State private var authModel: AuthViewModel
    @State private var onboardingModel: OnboardingViewModel

    public init(
        navigationModel: AppNavigationModel = AppNavigationModel(),
        authModel: AuthViewModel? = nil,
        onboardingModel: OnboardingViewModel? = nil
    ) {
        _navigationModel = State(initialValue: navigationModel)
        _authModel = State(initialValue: authModel ?? AuthViewModel())
        _onboardingModel = State(initialValue: onboardingModel ?? OnboardingViewModel())
    }

    public var body: some View {
        AuthGate(model: authModel) {
            OnboardingGate(model: onboardingModel) {
                MainShellView(model: navigationModel)
            }
        }
        .task { await authModel.restore() }
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

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        switch AdaptiveLayoutResolver.layout(for: resolvedSizeClass) {
        case .tabBar:
            TabLayout(model: model)
        case .splitView:
            SplitLayout(model: model)
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

    var body: some View {
        TabView(selection: $model.selectedRoute) {
            ForEach(AppRoute.allCases) { route in
                NavigationStack {
                    RouteDestinationView(route: route)
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

    var body: some View {
        NavigationSplitView {
            List(AppRoute.allCases, selection: sidebarSelection) { route in
                Label(route.title, systemImage: route.systemImageName)
                    .tag(route)
            }
            .navigationTitle("Voxa")
        } detail: {
            NavigationStack {
                RouteDestinationView(route: model.selectedRoute)
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
                    expiresAt: .distantFuture
                )
            )
        ),
        onboardingModel: OnboardingViewModel(
            store: InMemoryOnboardingDraftStore(draft: OnboardingDraft(isCompleted: true))
        )
    )
}
#endif
