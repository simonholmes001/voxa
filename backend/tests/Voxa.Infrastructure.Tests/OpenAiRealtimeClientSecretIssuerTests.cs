using System.Net;
using System.Text;
using Voxa.Application.Ai;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.OpenAI;
using Microsoft.Extensions.Logging.Abstractions;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiRealtimeClientSecretIssuerTests
{
    [Fact]
    public async Task IssueAsyncSendsServerApiKeyOnlyInAuthorizationHeader()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "client_secret": {
                "value": "client-secret-123",
                "expires_at": 1787991600
              },
              "session": {
                "model": "gpt-realtime-2.1"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        var credential = await issuer.IssueAsync(CreateRequest(), CancellationToken.None);

        Assert.Equal("client-secret-123", credential.ClientSecret);
        Assert.Equal("Bearer server-api-key", handler.Request?.Headers.Authorization?.ToString());
        Assert.DoesNotContain("server-api-key", handler.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("tenant-default", handler.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("user-a", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"session\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"type\":\"realtime\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("gpt-realtime-2.1", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"instructions\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("spoken language-learning tutor", handler.Body, StringComparison.Ordinal);
        // `session.metadata` (which carried target_language etc.) is not sent:
        // OpenAI's client_secrets endpoint rejects it with HTTP 400.
        Assert.DoesNotContain("metadata", handler.Body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task IssueAsyncAcceptsGaTopLevelClientSecretResponse()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": {
                "type": "realtime",
                "model": "gpt-realtime-2.1"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        var credential = await issuer.IssueAsync(CreateRequest(), CancellationToken.None);

        Assert.Equal("ek_prod_shape_123", credential.ClientSecret);
        Assert.Equal("gpt-realtime-2.1", credential.Model);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1787991600), credential.ExpiresAt);
    }

    [Fact]
    public async Task IssueAsyncMapsUpstreamFailureToRealtimeSessionIssueException()
    {
        var client = new HttpClient(new RecordingHttpMessageHandler("{}", HttpStatusCode.TooManyRequests))
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await Assert.ThrowsAsync<RealtimeSessionIssueException>(() =>
            issuer.IssueAsync(CreateRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task IssueAsyncUsesRouterResolvedRealtimeModelAndReasoningEffort()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "client_secret": {
                "value": "client-secret-123",
                "expires_at": 1787991600
              },
              "session": {
                "model": "gpt-realtime-2.1-mini"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var router = new StubModelRouter(new ModelRoute(
            AiCapability.RealtimeTutorModel,
            "gpt-realtime-2.1-mini",
            "low",
            ModelRouteSource.EnvironmentOverride,
            null));
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            router,
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        var credential = await issuer.IssueAsync(CreateRequest(), CancellationToken.None);

        Assert.Equal("gpt-realtime-2.1-mini", credential.Model);
        Assert.Contains("gpt-realtime-2.1-mini", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"effort\":\"low\"", handler.Body, StringComparison.Ordinal);
        // Regression: OpenAI's v1/realtime/client_secrets rejects an unknown
        // `session.metadata` parameter with HTTP 400, which surfaced as a 503.
        Assert.DoesNotContain("metadata", handler.Body, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(AiCapability.RealtimeTutorModel, router.Requests.Single().Capability);
        Assert.Equal(AiCallKind.RealtimeSession, router.Requests.Single().Kind);
    }

    [Fact]
    public async Task IssueAsyncAddsLessonIntentToRealtimeInstructions()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": {
                "type": "realtime",
                "model": "gpt-realtime-2.1"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(sessionIntent: "lesson", focusTitle: "Survival German"), CancellationToken.None);

        // Lesson intent resolves to the guided-lesson prompt template.
        Assert.Contains("Activity: Guided lesson on", handler.Body, StringComparison.Ordinal);
        Assert.Contains("Survival German", handler.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("metadata", handler.Body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task IssueAsyncGuidedLessonV2IncludesNativeLanguageOpenerAndAntiLoopAndEndOfLesson()
    {
        // Regression: the tutor was looping on "Say your name is X" and
        // never terminating the lesson. Prove that the guided-lesson v2
        // prompt renders the L1 opener with the caller's nativeLanguage,
        // the anti-loop guarantee, and the end-of-lesson closure so the
        // model has the instructions it needs to STOP.
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": {"type": "realtime", "model": "gpt-realtime-2.1"}
            }
            """);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel, "gpt-realtime-2.1", "low",
                ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(
            CreateRequest(
                sessionIntent: "guided_lesson",
                focusTitle: "Greeting people",
                nativeLanguage: "English"),
            CancellationToken.None);

        // Anti-loop rule reaches the model.
        Assert.Contains("Anti-loop guarantee", handler.Body, StringComparison.Ordinal);
        Assert.Contains("MUST NOT repeat the same prompt", handler.Body, StringComparison.Ordinal);
        // End-of-lesson closure reaches the model.
        Assert.Contains("End of lesson", handler.Body, StringComparison.Ordinal);
        Assert.Contains("Session complete", handler.Body, StringComparison.Ordinal);
        // Ongoing bilingual scaffolding reaches the model — L1 is not
        // just an opener/closer, it accompanies every scaffolding move
        // at A1/A2.
        Assert.Contains("Bilingual scaffolding for beginner bands", handler.Body, StringComparison.Ordinal);
        Assert.Contains("L2 model", handler.Body, StringComparison.Ordinal);
        Assert.Contains("L1 gloss", handler.Body, StringComparison.Ordinal);
        Assert.Contains("40", handler.Body, StringComparison.Ordinal); // "40–60% nativeLanguage at A1"
        // L1 opener uses the caller's nativeLanguage.
        Assert.Contains("English", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncGuidedLessonV2FallsBackToEnglishWhenNativeLanguageMissing()
    {
        // A legacy client that doesn't send nativeLanguage still gets a
        // valid render — the L1 scaffolding is degraded (English framing)
        // but the session doesn't fail.
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": {"type": "realtime", "model": "gpt-realtime-2.1"}
            }
            """);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel, "gpt-realtime-2.1", "low",
                ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(
            CreateRequest(sessionIntent: "guided_lesson", focusTitle: "Greetings", nativeLanguage: null),
            CancellationToken.None);

        Assert.Contains("English", handler.Body, StringComparison.Ordinal);
        Assert.Contains("Session complete", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncAddsReviewIntentToRealtimeInstructions()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": {
                "type": "realtime",
                "model": "gpt-realtime-2.1"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(sessionIntent: "review", dueReviewCount: 3), CancellationToken.None);

        // review intent resolves to the review prompt; dueReviewCount is
        // interpolated into the "Number of due items to prioritise" sentence,
        // and the review prompt asks for production before explanation.
        Assert.Contains("Activity: Review", handler.Body, StringComparison.Ordinal);
        Assert.Contains("Number of due items to prioritise: 3", handler.Body, StringComparison.Ordinal);
        Assert.Contains("PRODUCE it first", handler.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("metadata", handler.Body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task IssueAsyncAddsFocusedReviewInstructionsToRealtimeInstructions()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": {
                "type": "realtime",
                "model": "gpt-realtime-2.1"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(sessionIntent: "review", focusTitle: "Pronunciation"), CancellationToken.None);

        // focusTitle "Pronunciation" is interpolated into the review prompt's
        // "Focus for this session" sentence.
        Assert.Contains("Focus for this session: Pronunciation", handler.Body, StringComparison.Ordinal);
        Assert.Contains("Activity: Review", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncSendsServerAuthoritativeTurnDetectionInClientSecretPayload()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": { "type": "realtime", "model": "gpt-realtime-2.1" }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(), CancellationToken.None);

        // Server-authoritative session config — the device must not be the
        // one setting these, otherwise a tampered client could re-enable
        // auto-response and defeat the "no monologue" guarantee.
        Assert.Contains("\"output_modalities\":[\"audio\"]", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"turn_detection\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"type\":\"server_vad\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"create_response\":false", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"interrupt_response\":true", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"audio/pcm\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"rate\":24000", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncIncludesTargetLanguageHandoffCueInInstructions()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": { "type": "realtime", "model": "gpt-realtime-2.1" }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(), CancellationToken.None);

        Assert.Contains("handoff phrase in fr-FR", handler.Body, StringComparison.Ordinal);
        Assert.Contains("stop and wait for the learner", handler.Body, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("pronunciation_drill", "realtime-tutor/pronunciation-drill", 1)]
    [InlineData("roleplay", "realtime-tutor/roleplay", 1)]
    [InlineData("mistakes_replay", "realtime-tutor/mistakes-replay", 1)]
    [InlineData("vocabulary_drill", "realtime-tutor/vocabulary-drill", 1)]
    [InlineData("listening_practice", "realtime-tutor/listening-practice", 1)]
    [InlineData("key_language", "realtime-tutor/key-language", 1)]
    [InlineData("open_practice", "realtime-tutor/open-practice", 1)]
    [InlineData("practice", "realtime-tutor/open-practice", 1)]
    [InlineData("guided_lesson", "realtime-tutor/guided-lesson", 2)]
    [InlineData("something_the_router_does_not_know", "realtime-tutor/open-practice", 1)]
    [InlineData(null, "realtime-tutor/open-practice", 1)]
    public void ResolvePromptRefRoutesEachIntentToItsActivityPromptWithOpenPracticeFallback(
        string? intent,
        string expectedPromptId,
        int expectedVersion)
    {
        var settings = new RealtimeSessionSettingsContract(
            CoachingMode: "tutor",
            ProficiencyBand: "A1-A2",
            TargetLanguage: "fr-FR",
            SessionIntent: intent);

        var promptRef = OpenAiRealtimeClientSecretIssuer.ResolvePromptRef(settings);

        Assert.Equal(expectedPromptId, promptRef.Id);
        Assert.Equal(expectedVersion, promptRef.Version);
    }

    [Fact]
    public async Task IssueAsyncAddsPronunciationDrillIntentToRealtimeInstructions()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": { "type": "realtime", "model": "gpt-realtime-2.1" }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(sessionIntent: "pronunciation_drill"), CancellationToken.None);

        Assert.Contains("Activity: Pronunciation drill", handler.Body, StringComparison.Ordinal);
        // Pronunciation prompt has activity-specific feedback style — targeted
        // articulatory feedback rather than "try again". Confirming the
        // content actually differs from open-practice.
        Assert.Contains("articulatory", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncAddsRoleplayScenarioTitleToRealtimeInstructions()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": { "type": "realtime", "model": "gpt-realtime-2.1" }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(
            CreateRequest(sessionIntent: "roleplay", focusTitle: "Order coffee in Paris"),
            CancellationToken.None);

        Assert.Contains("Scenario roleplay", handler.Body, StringComparison.Ordinal);
        Assert.Contains("Order coffee in Paris", handler.Body, StringComparison.Ordinal);
        // Roleplay prompt explicitly forbids in-scene correction — a
        // regression that surfaced grammar corrections during roleplay
        // would fail this.
        Assert.Contains("NONE inside the scene", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncFallsBackToOpenPracticePromptForUnknownIntent()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "value": "ek_prod_shape_123",
              "expires_at": 1787991600,
              "session": { "type": "realtime", "model": "gpt-realtime-2.1" }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                "low",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await issuer.IssueAsync(CreateRequest(sessionIntent: "totally_made_up_intent"), CancellationToken.None);

        // Unknown intent must NOT throw. It falls back to open-practice, so
        // the body carries the free-conversation activity marker.
        Assert.Contains("Activity: Free conversation practice", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncRejectsRealtimeRouteWithoutReasoningEffort()
    {
        var client = new HttpClient(new RecordingHttpMessageHandler("{}"))
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.RealtimeTutorModel,
                "gpt-realtime-2.1",
                null,
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiRealtimeClientSecretIssuer>.Instance);

        await Assert.ThrowsAsync<RealtimeSessionIssueException>(() =>
            issuer.IssueAsync(CreateRequest(), CancellationToken.None));
    }


    private static RealtimeSessionRequest CreateRequest(
        string? sessionIntent = null,
        string? focusTitle = null,
        int? dueReviewCount = null,
        string? nativeLanguage = "English")
    {
        return new RealtimeSessionRequest(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CorrelationId.Create("corr-123"),
            new RealtimeSessionSettingsContract("tutor", "B1-B2", "fr-FR", sessionIntent, focusTitle, dueReviewCount, nativeLanguage));
    }

    private sealed class RecordingHttpMessageHandler(
        string responseBody,
        HttpStatusCode statusCode = HttpStatusCode.OK) : HttpMessageHandler
    {
        public HttpRequestMessage? Request { get; private set; }

        public string Body { get; private set; } = "";

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Request = request;
            Body = request.Content is null
                ? ""
                : await request.Content.ReadAsStringAsync(cancellationToken);

            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json")
            };
        }
    }

    private sealed class StubModelRouter(ModelRoute route) : IModelRouter
    {
        public List<ModelRouteRequest> Requests { get; } = [];

        public ModelRoute Resolve(ModelRouteRequest request)
        {
            Requests.Add(request);
            return route;
        }
    }
}
