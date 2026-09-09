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
        let credential = try result.get()
        return RealtimeSessionCredential(
            correlationId: credential.correlationId,
            clientSecret: credential.clientSecret,
            model: credential.model,
            reasoningEffort: credential.reasoningEffort,
            expiresAt: credential.expiresAt,
            settings: settings
        )
    }
}

private final class FakeRealtimeSessionCompletionService: RealtimeSessionCompletionService, @unchecked Sendable {
    var error: Error?
    private(set) var completedWith: [(RealtimeSessionCompletion, String)] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func completeSession(_ completion: RealtimeSessionCompletion, accessToken: String) async throws {
        if let error {
            throw error
        }
        completedWith.append((completion, accessToken))
    }
}

private actor CompletionObserver {
    private var recordedCount = 0

    func record() {
        recordedCount += 1
    }

    func count() -> Int {
        recordedCount
    }
}

private actor RecoveryRecorder {
    private var called = false

    func record() {
        called = true
    }

    func wasCalled() -> Bool {
        called
    }
}

private final class FakeRealtimeTransport: RealtimeTransport, @unchecked Sendable {
    var connectResult: Result<Void, Error>
    var transcript: [TranscriptTurn]
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0

    init(connectResult: Result<Void, Error> = .success(()), transcript: [TranscriptTurn] = []) {
        self.connectResult = connectResult
        self.transcript = transcript
    }

    func connect(using credential: RealtimeSessionCredential) async throws {
        connectCount += 1
        try connectResult.get()
    }

    func disconnect() async { disconnectCount += 1 }

    func capturedTranscript() -> [TranscriptTurn] { transcript }
}

private final class FakeDebriefService: DebriefService, @unchecked Sendable {
    var result: Result<SessionDebrief, Error>
    private(set) var calls: [(settings: RealtimeCoachingSettings, transcript: [TranscriptTurn], token: String)] = []

    init(result: Result<SessionDebrief, Error>) {
        self.result = result
    }

    func generateDebrief(
        settings: RealtimeCoachingSettings,
        transcript: [TranscriptTurn],
        accessToken: String
    ) async throws -> SessionDebrief {
        calls.append((settings, transcript, accessToken))
        return try result.get()
    }
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
            correlationId: "corr-1",
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
        completionService: FakeRealtimeSessionCompletionService? = nil,
        transport: FakeRealtimeTransport = FakeRealtimeTransport(),
        debriefService: any DebriefService = NotConfiguredDebriefService(),
        token: String? = "access-token",
        onSessionCompleted: @escaping @MainActor @Sendable () async -> Void = {},
        nowProvider: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) -> TalkSessionViewModel {
        TalkSessionViewModel(
            settings: settings,
            permission: permission,
            service: service,
            completionService: completionService,
            transport: transport,
            debriefService: debriefService,
            accessTokenProvider: { token },
            onSessionCompleted: onSessionCompleted,
            nowProvider: nowProvider
        )
    }

    private func sampleDebrief() -> SessionDebrief {
        SessionDebrief(
            correlationId: "corr-debrief",
            summary: "You practised past tense.",
            recurringMistakes: [
                DebriefRecurringMistake(pattern: "past participle", example: "I have ate", severity: .medium),
            ],
            usefulPhrases: ["How's it going?"],
            pronunciationNotes: [],
            recommendedNextDrill: DebriefRecommendedDrill(
                activityIntent: "pronunciation_drill",
                focusTitle: "English th",
                reason: "the 'th' tripped you up twice."))
    }

    func testStartsIdle() {
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential()))
        )
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.pendingIntent, .openPractice)
    }

    func testPrepareUpdatesPendingIntent() {
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential()))
        )

        model.prepare(.lesson(title: "Survival German"))

        XCTAssertEqual(model.pendingIntent, .lesson(title: "Survival German"))
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

    func testUnauthorizedSessionTriggersAuthenticationRecovery() async {
        let recovery = RecoveryRecorder()
        let model = TalkSessionViewModel(
            settings: settings,
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .failure(RealtimeSessionError.appSessionRequired)),
            accessTokenProvider: { "valid-token" },
            onAuthenticationRequired: { await recovery.record() }
        )

        await model.start()

        XCTAssertEqual(model.state, .failed("Your session expired. Please sign in again."))
        let recoveryWasCalled = await recovery.wasCalled()
        XCTAssertTrue(recoveryWasCalled)
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

    func testTransportConnectionFailedIncludesReason() async {
        let transport = FakeRealtimeTransport(connectResult: .failure(RealtimeTransportError.connectionFailed("ICE failed")))
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential())),
            transport: transport
        )

        await model.start()

        XCTAssertEqual(model.state, .failed("We couldn't connect to your tutor: ICE failed"))
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

    func testEndRecordsCompletedSessionWhenConnected() async {
        var now = Date(timeIntervalSince1970: 1_000)
        let completionService = FakeRealtimeSessionCompletionService()
        let completionObserver = CompletionObserver()
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential())),
            completionService: completionService,
            token: "access-token",
            onSessionCompleted: { await completionObserver.record() },
            nowProvider: { now }
        )
        model.prepare(.lesson(title: "Survival German"))

        await model.start()
        now = Date(timeIntervalSince1970: 1_420)
        await model.end()

        XCTAssertEqual(completionService.completedWith.count, 1)
        XCTAssertEqual(completionService.completedWith.first?.0.sessionId, "corr-1")
        XCTAssertEqual(completionService.completedWith.first?.0.durationSeconds, 420)
        XCTAssertEqual(completionService.completedWith.first?.0.sessionIntent, "guided_lesson")
        XCTAssertEqual(completionService.completedWith.first?.1, "access-token")
        let completedCount = await completionObserver.count()
        XCTAssertEqual(completedCount, 1)
    }

    func testEndDoesNotNotifyCompletionWhenCompletionWriteBackFails() async {
        let completionService = FakeRealtimeSessionCompletionService(error: RealtimeSessionError.transport)
        let completionObserver = CompletionObserver()
        let model = makeModel(
            permission: FakeMicrophonePermission(current: .granted),
            service: FakeRealtimeSessionService(result: .success(credential())),
            completionService: completionService,
            onSessionCompleted: { await completionObserver.record() }
        )

        await model.start()
        await model.end()

        let completedCount = await completionObserver.count()
        XCTAssertEqual(completedCount, 0)
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

        XCTAssertEqual(service.createdWith.first?.0.coachingMode, custom.coachingMode)
        XCTAssertEqual(service.createdWith.first?.0.proficiencyBand, custom.proficiencyBand)
        XCTAssertEqual(service.createdWith.first?.0.targetLanguage, custom.targetLanguage)
        XCTAssertEqual(service.createdWith.first?.0.sessionIntent, "open_practice")
    }

    func testPreparedLessonIntentIsSentToService() async {
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = TalkSessionViewModel(
            settings: settings,
            permission: FakeMicrophonePermission(current: .granted),
            service: service,
            accessTokenProvider: { "t" }
        )
        model.prepare(.lesson(title: "Survival German"))

        await model.start()

        XCTAssertEqual(service.createdWith.first?.0.sessionIntent, "guided_lesson")
        XCTAssertEqual(service.createdWith.first?.0.focusTitle, "Survival German")
    }

    func testPreparedFocusedReviewIntentIsSentToService() async {
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let model = TalkSessionViewModel(
            settings: settings,
            permission: FakeMicrophonePermission(current: .granted),
            service: service,
            accessTokenProvider: { "t" }
        )
        model.prepare(.review(dueCount: 2, focusTitle: "Pronunciation"))

        await model.start()

        XCTAssertEqual(service.createdWith.first?.0.sessionIntent, "review")
        XCTAssertEqual(service.createdWith.first?.0.focusTitle, "Pronunciation")
        XCTAssertEqual(service.createdWith.first?.0.dueReviewCount, 2)
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

    // MARK: - Debrief

    func testEndTriggersDebriefWhenTranscriptCapturedAtLeastOneTurn() async {
        let permission = FakeMicrophonePermission(current: .granted)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let transcript = [
            TranscriptTurn(role: TranscriptTurn.tutorRole, text: "Bonjour."),
            TranscriptTurn(role: TranscriptTurn.learnerRole, text: "Salut !"),
        ]
        let transport = FakeRealtimeTransport(transcript: transcript)
        let expected = sampleDebrief()
        let debriefService = FakeDebriefService(result: .success(expected))
        let model = makeModel(
            permission: permission,
            service: service,
            transport: transport,
            debriefService: debriefService)

        await model.start()
        XCTAssertEqual(model.state, .connected)

        await model.end()

        XCTAssertEqual(model.state, .ended)
        XCTAssertEqual(model.debriefState, .ready(expected))
        XCTAssertEqual(debriefService.calls.count, 1)
        XCTAssertEqual(debriefService.calls[0].transcript, transcript)
        // The credential's settings (post-intent) are what get forwarded to
        // the debrief service — the pendingIntent .openPractice was applied
        // by start(), so the recorded sessionIntent is "open_practice".
        XCTAssertEqual(debriefService.calls[0].settings, settings.applying(.openPractice))
        XCTAssertEqual(debriefService.calls[0].token, "access-token")
    }

    func testEndSkipsDebriefWhenNoTranscriptWasCaptured() async {
        let permission = FakeMicrophonePermission(current: .granted)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        // Empty transcript — the fake defaults to []; nothing to debrief.
        let transport = FakeRealtimeTransport(transcript: [])
        let debriefService = FakeDebriefService(result: .success(sampleDebrief()))
        let model = makeModel(
            permission: permission,
            service: service,
            transport: transport,
            debriefService: debriefService)

        await model.start()
        await model.end()

        XCTAssertEqual(model.state, .ended)
        XCTAssertEqual(model.debriefState, .idle)
        XCTAssertTrue(debriefService.calls.isEmpty)
    }

    func testDebriefFailureSurfacesReadableMessageAndDoesNotBlockNextSession() async {
        let permission = FakeMicrophonePermission(current: .granted)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let transport = FakeRealtimeTransport(transcript: [
            TranscriptTurn(role: TranscriptTurn.tutorRole, text: "Hi."),
        ])
        let debriefService = FakeDebriefService(result: .failure(DebriefServiceError.transport))
        let model = makeModel(
            permission: permission,
            service: service,
            transport: transport,
            debriefService: debriefService)

        await model.start()
        await model.end()

        if case let .failed(message) = model.debriefState {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected debriefState .failed, got \(model.debriefState)")
        }
        // Session teardown is not blocked by debrief failure.
        XCTAssertEqual(model.state, .ended)
    }

    func testPrepareClearsStaleDebriefWhenLearnerStartsANewSession() async {
        let permission = FakeMicrophonePermission(current: .granted)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let transport = FakeRealtimeTransport(transcript: [
            TranscriptTurn(role: TranscriptTurn.tutorRole, text: "Hi."),
        ])
        let debriefService = FakeDebriefService(result: .success(sampleDebrief()))
        let model = makeModel(
            permission: permission,
            service: service,
            transport: transport,
            debriefService: debriefService)

        await model.start()
        await model.end()
        if case .ready = model.debriefState { /* good */ } else {
            XCTFail("expected ready debrief before prepare")
        }

        model.prepare(.pronunciationDrill())

        XCTAssertEqual(model.debriefState, .idle)
        XCTAssertEqual(model.pendingIntent, .pronunciationDrill())
    }

    func testAcknowledgeDebriefResetsStateToIdle() async {
        let permission = FakeMicrophonePermission(current: .granted)
        let service = FakeRealtimeSessionService(result: .success(credential()))
        let transport = FakeRealtimeTransport(transcript: [
            TranscriptTurn(role: TranscriptTurn.tutorRole, text: "Hi."),
        ])
        let debriefService = FakeDebriefService(result: .success(sampleDebrief()))
        let model = makeModel(
            permission: permission,
            service: service,
            transport: transport,
            debriefService: debriefService)

        await model.start()
        await model.end()
        model.acknowledgeDebrief()

        XCTAssertEqual(model.debriefState, .idle)
    }
}
