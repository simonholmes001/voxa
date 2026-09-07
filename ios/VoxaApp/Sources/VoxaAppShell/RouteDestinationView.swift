#if canImport(SwiftUI)
import SwiftUI
import VoxaHome
import VoxaProfiles
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
    var languageManager: LanguageManagerContext?
    var onContinueLearning: () -> Void = {}
    var onStartTalk: () -> Void = {}

    var body: some View {
        switch route {
        case .home where homeModel != nil:
            HomeView(
                model: homeModel!,
                talkModel: talkModel,
                languages: homeLanguages,
                onContinueLearning: onContinueLearning,
                onVoicePractice: onStartTalk,
                onSelectLanguage: selectLanguage
            )
        case .talk where talkModel != nil:
            TalkView(model: talkModel!)
        case .learn:
            LearningRouteView(
                title: "Today's lesson",
                symbol: "book.closed",
                headline: "Travel German A1",
                detail: "A short tutor-led session with warm-up, useful phrases, and a voice roleplay.",
                primaryTitle: "Start voice lesson",
                primarySymbol: "mic.fill",
                primaryAction: onStartTalk,
                rows: [
                    LearningRouteRow(title: "Warm up", detail: "Review yesterday's weak words", symbol: "flame"),
                    LearningRouteRow(title: "New language", detail: "Asking for directions at a station", symbol: "map"),
                    LearningRouteRow(title: "Roleplay", detail: "Find your platform and buy a ticket", symbol: "person.wave.2")
                ]
            )
        case .review:
            LearningRouteView(
                title: "Review",
                symbol: "arrow.triangle.2.circlepath",
                headline: "Practice what needs attention",
                detail: "Voxa should turn mistakes, weak words, and pronunciation notes into focused drills.",
                primaryTitle: "Review with tutor",
                primarySymbol: "mic.fill",
                primaryAction: onStartTalk,
                rows: [
                    LearningRouteRow(title: "Recent mistakes", detail: "Grammar and phrase corrections from Talk", symbol: "exclamationmark.bubble"),
                    LearningRouteRow(title: "Words due", detail: "Spaced repetition for unstable vocabulary", symbol: "textformat.abc"),
                    LearningRouteRow(title: "Pronunciation", detail: "Minimal-pair drills for sounds you miss", symbol: "waveform")
                ]
            )
        case .settings where languageManager != nil:
            LanguageManagementView(
                profiles: languageManager!.profileModel.allProfiles,
                activeKey: languageManager!.profileModel.activeLanguageKey,
                makeSettingsModel: languageManager!.makeSettingsModel,
                onSwitch: languageManager!.onSwitch,
                onAddLanguage: languageManager!.onAddLanguage,
                onSaved: { await languageManager!.profileModel.refresh() },
                onSignOut: languageManager!.onSignOut
            )
        case .settings:
            LearningRouteView(
                title: "Settings",
                symbol: "person.crop.circle",
                headline: "Manage your tutor",
                detail: "Language profiles, daily time, goals, and account settings live here.",
                primaryTitle: "Add a language",
                primarySymbol: "plus.circle",
                primaryAction: languageManager?.onAddLanguage ?? {},
                rows: [
                    LearningRouteRow(title: "Languages", detail: "Switch between the languages you are learning", symbol: "globe"),
                    LearningRouteRow(title: "Goals", detail: "Tune what your tutor should optimize for", symbol: "target"),
                    LearningRouteRow(title: "Session style", detail: "Control how much correction and explanation you want", symbol: "slider.horizontal.3")
                ]
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
        displayName.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
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

private struct LearningRouteRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct LearningRouteView: View {
    let title: String
    let symbol: String
    let headline: String
    let detail: String
    let primaryTitle: String
    let primarySymbol: String
    let primaryAction: () -> Void
    let rows: [LearningRouteRow]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(headline)
                    .font(.title)
                    .fontWeight(.bold)
                Text(detail)
                    .foregroundStyle(.secondary)
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(spacing: 10) {
                    ForEach(rows) { row in
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
                        .padding()
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(title)
    }
}

#Preview {
    RouteDestinationView(route: .learn)
}
#endif
