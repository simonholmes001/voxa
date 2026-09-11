#if canImport(SwiftUI)
import SwiftUI
import VoxaHome
import VoxaProfiles
import VoxaRealtime

/// Destination for a top-level route.
///
/// Home hosts the learning dashboard, Talk hosts the Realtime tutor, and
/// Learn/Review/Progress render assistant-plan surfaces from the active
/// profile. Settings renders the language manager when its dependencies are
/// available.
struct RouteDestinationView: View {
    let route: AppRoute
    var homeModel: HomeViewModel?
    var talkModel: TalkSessionViewModel?
    var learnerPlanModel: LearnerPlanViewModel?
    var learnerCourseModel: LearnerCourseViewModel?
    var languageManager: LanguageManagerContext?
    var onContinueLearning: () -> Void = {}
    var onStartTalk: (RealtimeTutorIntent) -> Void = { _ in }

    var body: some View {
        switch route {
        case .home where homeModel != nil:
            HomeView(
                model: homeModel!,
                courseModel: learnerCourseModel,
                talkModel: talkModel,
                languages: homeLanguages,
                onContinueLearning: onContinueLearning,
                onVoicePractice: { onStartTalk(.openPractice) },
                onReviewPractice: { topic in
                    onStartTalk(.review(dueCount: learningContext.dueReviewCount, focusTitle: topic))
                },
                onSelectLanguage: selectLanguage,
                onStartTalk: onStartTalk
            )
        case .talk where talkModel != nil:
            TalkView(model: talkModel!)
        case .practice:
            PracticeHubView(
                summary: practiceSummary,
                planState: learnerPlanModel?.state ?? .idle,
                onStartTalk: onStartTalk
            )
            .task { await learnerPlanModel?.load() }
        case .review:
            LearningRouteView(
                content: learningPlan.review,
                primaryAction: { onStartTalk(.review(dueCount: learningContext.dueReviewCount)) },
                rowAction: { row in
                    onStartTalk(.review(dueCount: learningContext.dueReviewCount, focusTitle: row.title))
                }
            )
        case .progress:
            LearningRouteView(
                content: learningPlan.progress,
                primaryAction: onContinueLearning,
                rowAction: { _ in onContinueLearning() }
            )
        case .settings where languageManager != nil:
            LanguageManagementView(
                profiles: languageManager!.profileModel.allProfiles,
                activeKey: languageManager!.profileModel.activeLanguageKey,
                makeSettingsModel: languageManager!.makeSettingsModel,
                onSwitch: languageManager!.onSwitch,
                onAddLanguage: languageManager!.onAddLanguage,
                onSaved: { await languageManager!.profileModel.refresh() },
                onDelete: languageManager!.onDelete,
                onSignOut: languageManager!.onSignOut
            )
        case .settings:
            LearningRouteView(
                content: learningPlan.settings,
                primaryAction: languageManager?.onAddLanguage ?? {},
                rowAction: { _ in languageManager?.onAddLanguage() }
            )
        default:
            placeholder
        }
    }

    private var homeLanguages: [LearnerLanguageSummary] {
        guard let languageManager else { return [] }
        return languageManager.profileModel.allProfiles.map { profile in
            LearnerLanguageSummary(
                id: profile.languageKey,
                name: shortLanguageName(profile.displayName),
                levelName: profile.profile.placementLevel.displayName,
                dailyMinutes: profile.profile.minutesPerDay,
                isActive: profile.languageKey == languageManager.profileModel.activeLanguageKey
            )
        }
    }

    private func selectLanguage(_ id: String) {
        guard let languageManager,
              let profile = languageManager.profileModel.allProfiles.first(where: { $0.languageKey == id }),
              profile.languageKey != languageManager.profileModel.activeLanguageKey
        else { return }
        languageManager.onSwitch(profile)
    }

    private func shortLanguageName(_ displayName: String) -> String {
        LearningAssistantPlanFactory.shortLanguageName(displayName)
    }

    private var learningPlan: LearningAssistantPlan {
        LearningAssistantPlanFactory.makePlan(for: learningContext)
    }

    private var learningContext: LearningAssistantContext {
        if let homeModel,
           case let .ready(summary) = homeModel.state {
            return LearningAssistantPlanFactory.context(
                activeProfile: activeLanguageProfile,
                homeSummary: summary
            )
        }

        return LearningAssistantPlanFactory.context(
            activeProfile: activeLanguageProfile,
            homeSummary: nil
        )
    }

    /// The learner summary the Practice tab uses to compute today's
    /// recommendation and to decide which tiles need enough context to show
    /// (guided lesson, key-language brief). Nil if Home hasn't loaded yet;
    /// PracticeHubView degrades gracefully to the core tiles + free-
    /// conversation Today card in that case.
    private var practiceSummary: LearnerProfileSummary? {
        if let homeModel, case let .ready(summary) = homeModel.state {
            return summary
        }
        return nil
    }

    private var activeLanguageProfile: LanguageProfile? {
        guard let languageManager else { return nil }
        if let activeKey = languageManager.profileModel.activeLanguageKey,
           let active = languageManager.profileModel.allProfiles.first(where: { $0.languageKey == activeKey }) {
            return active
        }
        return languageManager.profileModel.allProfiles.first
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

private struct LearningRouteView: View {
    let content: LearningRouteContent
    let primaryAction: () -> Void
    let rowAction: (LearningRouteRow) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: content.symbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(content.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(content.headline)
                    .font(.title)
                    .fontWeight(.bold)
                Text(content.detail)
                    .foregroundStyle(.secondary)
                Button(action: primaryAction) {
                    Label(content.primaryTitle, systemImage: content.primarySymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(spacing: 10) {
                    ForEach(content.rows) { row in
                        Button {
                            rowAction(row)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: row.symbol)
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 28)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                    Text(row.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding()
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(content.title)
    }
}

#Preview {
    RouteDestinationView(route: .practice)
}
#endif
