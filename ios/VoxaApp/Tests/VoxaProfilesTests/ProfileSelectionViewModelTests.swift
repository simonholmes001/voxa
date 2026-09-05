import XCTest
@testable import VoxaProfiles
import VoxaOnboarding

private final class FakeLanguageProfilesService: LanguageProfilesService, @unchecked Sendable {
    var listResult: Result<LanguageProfileList, Error>
    var selectResult: Result<String, Error>
    private(set) var selectedKeys: [String] = []

    init(
        list: Result<LanguageProfileList, Error> = .success(LanguageProfileList(activeLanguageKey: nil, profiles: [])),
        select: Result<String, Error> = .success("")
    ) {
        self.listResult = list
        self.selectResult = select
    }

    func list() async throws -> LanguageProfileList { try listResult.get() }
    func selectActive(languageKey: String) async throws -> String {
        selectedKeys.append(languageKey)
        return try selectResult.get()
    }
}

private func profile(_ key: String, _ display: String, complete: Bool = true, version: Int = 1) -> LanguageProfile {
    LanguageProfile(
        languageKey: key,
        displayName: display,
        isComplete: complete,
        profile: OnboardingProfile(
            targetLanguage: key, nativeLanguage: "en-US", goals: ["travel"],
            minutesPerDay: 15, placementLevel: .a1
        ),
        version: version
    )
}

@MainActor
final class ProfileSelectionViewModelTests: XCTestCase {
    // Scenario: no profiles -> onboarding.
    func testNoProfilesNeedsOnboarding() async {
        let service = FakeLanguageProfilesService(list: .success(LanguageProfileList(activeLanguageKey: nil, profiles: [])))
        let model = ProfileSelectionViewModel(service: service)

        await model.load()

        XCTAssertEqual(model.state, .needsOnboarding)
        XCTAssertNil(model.activeLanguageKey)
    }

    // Scenario: one profile -> open it.
    func testSingleProfileOpensDirectly() async {
        let fr = profile("fr-FR", "French")
        let service = FakeLanguageProfilesService(list: .success(LanguageProfileList(activeLanguageKey: "fr-FR", profiles: [fr])))
        let model = ProfileSelectionViewModel(service: service)

        await model.load()

        XCTAssertEqual(model.state, .single(fr))
        XCTAssertEqual(model.activeLanguageKey, "fr-FR")
    }

    // Scenario: multiple profiles -> choose.
    func testMultipleProfilesLetChoose() async {
        let fr = profile("fr-FR", "French")
        let es = profile("es-ES", "Spanish")
        let service = FakeLanguageProfilesService(list: .success(LanguageProfileList(activeLanguageKey: "fr-FR", profiles: [fr, es])))
        let model = ProfileSelectionViewModel(service: service)

        await model.load()

        XCTAssertEqual(model.state, .multiple(active: "fr-FR", profiles: [fr, es]))
    }

    // Scenario: switching the active language.
    func testSwitchingActiveLanguagePreservesProfiles() async {
        let fr = profile("fr-FR", "French")
        let es = profile("es-ES", "Spanish")
        let service = FakeLanguageProfilesService(
            list: .success(LanguageProfileList(activeLanguageKey: "fr-FR", profiles: [fr, es])),
            select: .success("es-ES")
        )
        let model = ProfileSelectionViewModel(service: service)
        await model.load()

        await model.selectLanguage("es-ES")

        XCTAssertEqual(service.selectedKeys, ["es-ES"])
        XCTAssertEqual(model.activeLanguageKey, "es-ES")
        // Switching must not drop or overwrite any profile.
        XCTAssertEqual(model.state, .multiple(active: "es-ES", profiles: [fr, es]))
    }

    // Scenario: adding another language does not overwrite existing profiles.
    // The list model still exposes every existing profile after a reload that
    // includes a newly created language.
    func testCreatingAnotherLanguageDoesNotOverwriteExisting() async {
        let fr = profile("fr-FR", "French", version: 3)
        let service = FakeLanguageProfilesService(list: .success(LanguageProfileList(activeLanguageKey: "fr-FR", profiles: [fr])))
        let model = ProfileSelectionViewModel(service: service)
        await model.load()
        XCTAssertEqual(model.state, .single(fr))

        // Backend now reports the original French profile (unchanged) plus a new
        // German profile; the original's version/goals are preserved.
        let de = profile("de-DE", "German", complete: false, version: 1)
        service.listResult = .success(LanguageProfileList(activeLanguageKey: "fr-FR", profiles: [fr, de]))
        await model.retry()

        guard case let .multiple(active, profiles) = model.state else {
            return XCTFail("expected multiple, got \(model.state)")
        }
        XCTAssertEqual(active, "fr-FR")
        XCTAssertEqual(profiles.first { $0.languageKey == "fr-FR" }, fr) // unchanged
        XCTAssertEqual(profiles.count, 2)
    }

    func testLoadFailureMapsToFailed() async {
        let service = FakeLanguageProfilesService(list: .failure(LanguageProfilesError.transport))
        let model = ProfileSelectionViewModel(service: service)

        await model.load()

        guard case .failed = model.state else { return XCTFail("expected failed") }
    }
}
