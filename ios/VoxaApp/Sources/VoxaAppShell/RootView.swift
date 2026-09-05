#if canImport(SwiftUI)
import SwiftUI
import VoxaAuth
import VoxaHome
import VoxaNetworking
import VoxaOnboarding
import VoxaProfiles
import VoxaRealtime

/// The root of the Voxa app. It composes the app's gates around the adaptive
/// navigation shell: first Sign in with Apple, then first-run onboarding, then
/// the tab bar (compact width) or split view (regular width).
public struct RootView: View {
    @State private var navigationModel: AppNavigationModel
    @State private var authModel: AuthViewModel
    @State private var onboardingModel: OnboardingViewModel
    #if DEBUG
    @State private var debugResetError: String?
    #endif
    private let homeModel: HomeViewModel?
    private let talkModel: TalkSessionViewModel?
    private let profileModel: ProfileSelectionViewModel?
    private let developerResetService: (any DeveloperResetService)?
    @State private var isAddingLanguage = false
    @State private var didChooseLanguage = false

    public init(
        navigationModel: AppNavigationModel = AppNavigationModel(),
        authModel: AuthViewModel? = nil,
        onboardingModel: OnboardingViewModel? = nil,
        homeModel: HomeViewModel? = nil,
        talkModel: TalkSessionViewModel? = nil,
        profileModel: ProfileSelectionViewModel? = nil,
        developerResetService: (any DeveloperResetService)? = nil
    ) {
        _navigationModel = State(initialValue: navigationModel)
        _authModel = State(initialValue: authModel ?? AuthViewModel())
        _onboardingModel = State(initialValue: onboardingModel ?? OnboardingViewModel())
        self.homeModel = homeModel
        self.talkModel = talkModel
        self.profileModel = profileModel
        self.developerResetService = developerResetService
    }

    public var body: some View {
        AuthGate(model: authModel) {
            signedInContent
        }
        #if DEBUG
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if developerResetService != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if let debugResetError {
                        Text(debugResetError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Reset first run") {
                        Task { await resetFirstRunForReview() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debug-reset-first-run")
                }
                .padding()
            }
        }
        #endif
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

    /// Post-sign-in content. When a profile model is provided, it drives the
    /// zero/one/multiple language decision; otherwise it falls back to the
    /// single-profile onboarding flow.
    @ViewBuilder
    private var signedInContent: some View {
        if let profileModel {
            profileFlow(profileModel)
        } else {
            onboardingThenShell
        }
    }

    @ViewBuilder
    private func profileFlow(_ profileModel: ProfileSelectionViewModel) -> some View {
        switch profileModel.state {
        case .loading:
            ProgressView("Loading your languages…")
                .task { await profileModel.load() }
        case .needsOnboarding:
            onboardingThenShell
        case let .single(profile):
            if profile.isComplete {
                mainShell
            } else {
                onboardingThenShell
            }
        case let .multiple(active, profiles):
            if isAddingLanguage {
                addingLanguageFlow(profileModel)
            } else if didChooseLanguage {
                mainShell
            } else {
                NavigationStack {
                    LanguageChoiceView(
                        profiles: profiles,
                        activeKey: active,
                        onContinue: { profile in
                            Task {
                                await profileModel.selectLanguage(profile.languageKey)
                                didChooseLanguage = true
                            }
                        },
                        onAddLanguage: {
                            onboardingModel.startNewLanguageOnboarding()
                            isAddingLanguage = true
                        }
                    )
                }
            }
        case let .failed(message):
            VStack(spacing: 16) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await profileModel.retry() } }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    /// Runs onboarding for a newly added language, then activates it so Home
    /// opens the new language rather than the previous active one.
    @ViewBuilder
    private func addingLanguageFlow(_ profileModel: ProfileSelectionViewModel) -> some View {
        onboardingThenShell
            .onChange(of: onboardingModel.isComplete) { _, complete in
                guard complete, let key = onboardingModel.draft.targetLanguage else { return }
                Task {
                    await profileModel.selectLanguage(key)
                    isAddingLanguage = false
                    didChooseLanguage = true
                }
            }
    }

    private var onboardingThenShell: some View {
        OnboardingGate(model: onboardingModel) { mainShell }
    }

    private var mainShell: some View {
        MainShellView(model: navigationModel, homeModel: homeModel, talkModel: talkModel)
    }

    #if DEBUG
    @MainActor
    private func resetFirstRunForReview() async {
        debugResetError = nil
        if let accessToken = authModel.state.session?.accessToken {
            do {
                try await developerResetService?.resetLearnerState(accessToken: accessToken)
            } catch {
                debugResetError = "Reset failed. Check backend dev reset is deployed."
                return
            }
        }
        await authModel.signOut()
        onboardingModel.resetForFirstRunReview()
        navigationModel.selectedRoute = .home
    }
    #endif
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
                    TabItemLabel(route: route, talkModel: talkModel)
                }
                .tag(route)
            }
        }
    }

    // Small view used for tab items that can show an inline active indicator
    // when the Talk session is connected. Kept minimal for easy testing.
    private struct TabItemLabel: View {
        let route: AppRoute
        let talkModel: TalkSessionViewModel?

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Label(route.title, systemImage: route.systemImageName)
                if route == .talk, let state = talkModel?.state, state == .connected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .offset(x: 12, y: -6)
                        .accessibilityIdentifier("talk-active-indicator")
                }
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
