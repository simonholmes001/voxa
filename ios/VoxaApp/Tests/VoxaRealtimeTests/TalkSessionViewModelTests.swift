import XCTest
@testable import VoxaRealtime

private final class FakeMicrophonePermission: MicrophonePermission, @unchecked Sendable {
    var current: MicrophonePermissionStatus
    var requestResult: MicrophonePermissionStatus
    private(set) var requestCount = 0

    init(current: MicrophonePermissionStatus, requestResult: MicrophonePermissionStatus = .granted) {
        self.current = current
        self.requestResult = requestResult
    }

    func currentStatus() -> MicrophonePermissionStatus { current }
    func request() async -> MicrophonePermissionStatus {
        requestCount += 1
        return requestResult
    }
}

private final class FakeRealtimeSessionService: RealtimeSessionService, @unchecked Sendable {
    var result: Result<RealtimeSessionCredential, Error>
    private(set) var createdWith: [(RealtimeCoachingSettings, String)] = []

    init(result: Result<RealtimeSessionCredential, Error>) {
        self.result = result
    }

    func createSession(_ settings: RealtimeCoachingSettings, accessToken: String) async throws -> RealtimeSessionCredential {
        createdWith.append((settings, accessToken))
        return try result.get()
    }
}

private final class FakeRealtimeTransport: RealtimeTransport, @unchecked Sendable {
    var connectResult: Result<Void, Error>
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0

    init(connectResult: Result<Void, Error> = .success(())) {
        self.connectResult = connectResult
    }

    func connect(using credential: RealtimeSessionCredential) async throws {
        connectCount += 1
        try connectResult.get()
    }

    func disconnect() async { disconnectCount += 1 }
}

@MainActor
private final class MutableRealtimeSettings {
    var band: String

    init(band: String) {
        self.band = band
    }
}

@MainActor
final class TalkSessionViewModelTests: XCTestCase {
    private let settings = RealtimeCoachingSettings(proficiencyBand: "B1-B2", targetLanguage: "fr-FR")

    private func credential() -> RealtimeSessionCredential {
        RealtimeSessionCredential(
            clientSecret: "secret",
            model: "gpt-realtime",
            reasoningEffort: "low",
            expiresAt: Date(timeIntervalSinceNow: 60),
            settings: settings
        )
    }

    private func makeModel(
        permission: FakeMicrophonePermission,
        service: FakeRealtimeSessionService,
        transport: FakeRealtimeTransport = FakeRealtimeTransport(),
        token: String? = "access-token"
    ) -> TalkSessionViewModel {
        TalkSessionViewModel(
            settings: settings,
            permission: permission,
            service: service,
            transport: transport,
            accessTokenProvider: { token }
        )
    }

    func testStartsIdle() {
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential()))
        )
        XCTAssertEqual(model.state, .idle)
    }

    func testHappyPathReachesConnected() async {
        let permission = FakeMicrophonePermission(current: .granted)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let transport = FakeRealtimeTransport()
        let model = makeModel(permission: permission, service: service, transport: transport)

        await model.start()

        XCTAssertEqual(model.state, .connected)
        XCTAssertEqual(model.micPermission, .granted)
        XCTAssertEqual(service.createdWith.count, 1)
        XCTAssertEqual(service.createdWith.first?.1, "access-token")
        XCTAssertEqual(transport.connectCount, 1)
    }

    func testRequestsPermissionWhenUndetermined() async {
        let permission = FakeMicrophonePermission(current: .undetermined, requestResult: .granted)
        let model = makeModel(
            permission: permission,
            service: FakeRealtimeSessionService(result: .success(credential()))
        )

        await model.start()

        XCTAssertEqual(permission.requestCount, 1)
        XCTAssertEqual(model.state, .connected)
    }

    func testDeniedPermissionFailsWithoutRequestingSession() async {
        let permission = FakeMicrophonePermission(current: .denied)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = makeModel(permission: permission, service: service)

        await model.start()

        guard case .failed = model.state else { return XCTFail("expected failed") }
        XCTAssertTrue(service.createdWith.isEmpty)
    }

    func testMissingTokenFails() async {
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential())),
            token: nil
        )

        await model.start()

        guard case .failed = model.state else { return XCTFail("expected failed") }
    }

    func testSessionRequestFailureSurfaces() async {
        let service = FakeRealtimeSessionService(result: .failure(RealtimeSessionError.appSessionRequired))
        let model = makeModel(permission: FakeMicrophonePermission(current: .granted), service: service)

        await model.start()

        XCTAssertEqual(model.state, .failed("Your session expired. Please sign in again."))
    }

    func testTransportFailureSurfaces() async {
        let transport = FakeRealtimeTransport(connectResult: .failure(RealtimeTransportError.unavailable("no webrtc")))
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential())),
            transport: transport
        )

        await model.start()

        XCTAssertEqual(model.state, .failed("no webrtc"))
    }

    func testEndDisconnectsAndEnds() async {
        let transport = FakeRealtimeTransport()
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential())),
            transport: transport
        )
        await model.start()

        await model.end()

        XCTAssertEqual(model.state, .ended)
        XCTAssertEqual(transport.disconnectCount, 1)
    }

    func testStartIsNoOpWhileBusy() async {
        // Connected is busy; a second start must not request another session.
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = makeModel(permission: FakeMicrophonePermission(current: .granted), service: service)
        await model.start()

        await model.start()

        XCTAssertEqual(service.createdWith.count, 1)
    }

    func testConfiguredSettingsAreSentToService() async {
        let custom = RealtimeCoachingSettings(coachingMode: "tutor", proficiencyBand: "C1-C2", targetLanguage: "ja-JP")
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = TalkSessionViewModel(
            settings: custom,
            permission: FakeMicrophonePermission(current: .granted),
            service: service,
            accessTokenProvider: { "t" }
        )

        await model.start()

        XCTAssertEqual(service.createdWith.first?.0, custom)
    }

    func testSettingsProviderIsEvaluatedAtStart() async {
        let mutableSettings = MutableRealtimeSettings(band: "A1-A2")
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = TalkSessionViewModel(
            settingsProvider: { RealtimeCoachingSettings(proficiencyBand: mutableSettings.band, targetLanguage: "fr-FR") },
            permission: FakeMicrophonePermission(current: .granted),
            service: service,
            accessTokenProvider: { "t" }
        )
        mutableSettings.band = "B1-B2" // learner state changes before the session starts

        await model.start()

        XCTAssertEqual(service.createdWith.first?.0.proficiencyBand, "B1-B2")
    }

    func testTokenPropagatesIfAvailableDuringPermissionRequest() async {
        // Simulate sign-in occurring while the permission prompt is presented.
        final class TokenBox { var value: String? }
        final class PermissionWithSideEffect: MicrophonePermission, @unchecked Sendable {
            var current: MicrophonePermissionStatus
            var sideEffect: (() -> Void)?
            init(current: MicrophonePermissionStatus, sideEffect: (() -> Void)? = nil) {
                self.current = current
                self.sideEffect = sideEffect
            }
            func currentStatus() -> MicrophonePermissionStatus { current }
            func request() async -> MicrophonePermissionStatus {
                sideEffect?()
                return .granted
            }
        }

        let box = TokenBox()
        box.value = nil

        let permission = PermissionWithSideEffect(current: .undetermined, sideEffect: { box.value = "dynamic-token" })
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = TalkSessionViewModel(
            settings: settings,
            permission: permission,
            service: service,
            accessTokenProvider: { box.value }
        )

        await model.start()

        XCTAssertEqual(service.createdWith.first?.1, "dynamic-token")
    }
}
