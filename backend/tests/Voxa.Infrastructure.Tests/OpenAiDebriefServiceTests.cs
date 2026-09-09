using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Voxa.Application.Ai;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiDebriefServiceTests
{
    [Fact]
    public async Task GenerateDebriefAsyncRendersDebriefPromptAndParsesStructuredJson()
    {
        // Model returns exactly the structured JSON shape the debrief prompt
        // asks for; the service parses it into a strongly-typed SessionDebrief.
        var handler = new RecordingHttpMessageHandler("""
            {
              "choices": [{
                "message": {
                  "role": "assistant",
                  "content": "{ \"summary\": \"Practiced past tense.\", \"recurringMistakes\": [ { \"pattern\": \"past participle 'eaten'\", \"example\": \"I have ate\", \"severity\": \"medium\" } ], \"usefulPhrases\": [ \"How's it going?\" ], \"pronunciationNotes\": [ \"the 'th' needs more tongue-tip contact\" ], \"recommendedNextDrill\": { \"activityIntent\": \"pronunciation_drill\", \"focusTitle\": \"English th\", \"reason\": \"the 'th' tripped you up twice.\" } }"
                }
              }]
            }
            """);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var service = new OpenAiDebriefService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.AssessmentModel,
                "gpt-5.6-sol",
                "high",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiDebriefService>.Instance);

        var debrief = await service.GenerateDebriefAsync(SampleRequest(), CancellationToken.None);

        Assert.Equal("Practiced past tense.", debrief.Summary);
        Assert.Single(debrief.RecurringMistakes);
        Assert.Equal("past participle 'eaten'", debrief.RecurringMistakes[0].Pattern);
        Assert.Equal("medium", debrief.RecurringMistakes[0].Severity);
        Assert.Single(debrief.UsefulPhrases);
        Assert.Equal("How's it going?", debrief.UsefulPhrases[0]);
        Assert.Single(debrief.PronunciationNotes);
        Assert.Equal("pronunciation_drill", debrief.RecommendedNextDrill.ActivityIntent);
        Assert.Equal("English th", debrief.RecommendedNextDrill.FocusTitle);
        Assert.Contains("th", debrief.RecommendedNextDrill.Reason, StringComparison.OrdinalIgnoreCase);
        Assert.Equal("corr-debrief", debrief.CorrelationId);
    }

    [Fact]
    public async Task GenerateDebriefAsyncEmbedsTheTranscriptAsBulletedLearnerAndTutorTurnsInTheRequest()
    {
        // The prompt template drops {{transcript}} into the user message. We
        // format turns as "N. [role] text" — the request body must show that.
        var handler = new RecordingHttpMessageHandler(EmptyChoicesResponse());
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var service = new OpenAiDebriefService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.AssessmentModel, "gpt-5.6-sol", "high", ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiDebriefService>.Instance);

        try
        {
            await service.GenerateDebriefAsync(
                SampleRequest(transcript:
                [
                    new TranscriptTurn(TranscriptTurn.TutorRole, "How are you today?"),
                    new TranscriptTurn(TranscriptTurn.LearnerRole, "I am good, thanks."),
                ]),
                CancellationToken.None);
        }
        catch (SessionDebriefException)
        {
            // Expected: EmptyChoicesResponse doesn't parse. We're asserting on
            // the request body, not the response happy path.
        }

        // JSON serialization keeps ASCII text intact — no Unicode-escape shifts.
        Assert.Contains("[tutor] How are you today?", handler.Body, StringComparison.Ordinal);
        Assert.Contains("[learner] I am good, thanks.", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GenerateDebriefAsyncSendsBearerTokenOnlyInAuthorizationHeader()
    {
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"{\"summary\":\"ok\",\"recurringMistakes\":[],\"usefulPhrases\":[],\"pronunciationNotes\":[],\"recommendedNextDrill\":{\"activityIntent\":\"open_practice\",\"focusTitle\":\"\",\"reason\":\"\"}}"}}]}
            """);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var service = new OpenAiDebriefService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.AssessmentModel, "gpt-5.6-sol", "high", ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiDebriefService>.Instance);

        await service.GenerateDebriefAsync(SampleRequest(), CancellationToken.None);

        Assert.Equal("Bearer server-api-key", handler.Request?.Headers.Authorization?.ToString());
        Assert.DoesNotContain("server-api-key", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"response_format\":{\"type\":\"json_object\"}", handler.Body, StringComparison.Ordinal);
        Assert.Contains("gpt-5.6-sol", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GenerateDebriefAsyncTolerantOfMissingOrPartialFieldsInModelOutput()
    {
        // If the assessor emits a minimal object (e.g. very short transcript,
        // no recurring mistakes to report), we still return a valid debrief
        // with empty lists and safe fallbacks — no NullReferenceException.
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"{\"summary\":\"Very short session.\"}"}}]}
            """);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var service = new OpenAiDebriefService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.AssessmentModel, "gpt-5.6-sol", "high", ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiDebriefService>.Instance);

        var debrief = await service.GenerateDebriefAsync(SampleRequest(), CancellationToken.None);

        Assert.Equal("Very short session.", debrief.Summary);
        Assert.Empty(debrief.RecurringMistakes);
        Assert.Empty(debrief.UsefulPhrases);
        Assert.Empty(debrief.PronunciationNotes);
        Assert.Equal("open_practice", debrief.RecommendedNextDrill.ActivityIntent);
    }

    [Fact]
    public async Task GenerateDebriefAsyncThrowsSessionDebriefExceptionOnUpstreamFailure()
    {
        var handler = new RecordingHttpMessageHandler("""{"error":"quota"}""", HttpStatusCode.TooManyRequests);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var service = new OpenAiDebriefService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.AssessmentModel, "gpt-5.6-sol", "high", ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiDebriefService>.Instance);

        await Assert.ThrowsAsync<SessionDebriefException>(
            () => service.GenerateDebriefAsync(SampleRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task GenerateDebriefAsyncThrowsSessionDebriefExceptionWhenModelReturnsNonJson()
    {
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"not JSON at all, just words"}}]}
            """);
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        var service = new OpenAiDebriefService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.AssessmentModel, "gpt-5.6-sol", "high", ModelRouteSource.ConfigDefault, null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiDebriefService>.Instance);

        await Assert.ThrowsAsync<SessionDebriefException>(
            () => service.GenerateDebriefAsync(SampleRequest(), CancellationToken.None));
    }

    // MARK: - Helpers

    private static SessionDebriefRequest SampleRequest(IReadOnlyList<TranscriptTurn>? transcript = null)
    {
        return new SessionDebriefRequest(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CorrelationId.Create("corr-debrief"),
            new RealtimeSessionSettingsContract("tutor", "A1-A2", "fr-FR", SessionIntent: "guided_lesson"),
            transcript ?? [new TranscriptTurn(TranscriptTurn.TutorRole, "hi")]);
    }

    private static string EmptyChoicesResponse()
    {
        return """{"choices":[]}""";
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
            Body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json"),
            };
        }
    }

    private sealed class StubModelRouter(ModelRoute route) : IModelRouter
    {
        public ModelRoute Resolve(ModelRouteRequest request) => route;
    }
}
