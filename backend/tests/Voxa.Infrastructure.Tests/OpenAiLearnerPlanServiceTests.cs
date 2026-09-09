using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Voxa.Application.Ai;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiLearnerPlanServiceTests
{
    private static readonly TenantId Tenant = TenantId.Create("tenant-a");
    private static readonly UserId User = UserId.Create("user-a");

    [Fact]
    public async Task GetTodayPlanAsyncReturnsSafeFallbackWhenLearnerHasNoState()
    {
        // No learner state (never onboarded) → return a safe open-practice
        // plan instead of throwing. Home Today card still shows something.
        var repository = new FakeRepository();
        var service = MakeService(repository, ChoicesResponseBody());

        var plan = await service.GetTodayPlanAsync(Tenant, User, CorrelationId.Create("corr-1"), CancellationToken.None);

        Assert.Equal("open_practice", plan.RecommendedSession.ActivityIntent);
        Assert.Empty(plan.FocusAreas);
        Assert.Equal("corr-1", plan.CorrelationId);
    }

    [Fact]
    public async Task GetTodayPlanAsyncRendersPromptWithLearnerContextAndParsesStructuredJson()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithDebriefs([
            new RecordedDebrief(
                "d1",
                DateTimeOffset.Parse("2026-09-08T10:00:00Z"),
                "You practised past tense.",
                [new RecordedMistake("past participle", "I have ate", "medium")],
                ["How's it going?"],
                [],
                new RecommendedNextDrill("mistakes_replay", "past participle", "you missed it twice.")),
        ]));
        var handler = new RecordingHttpMessageHandler("""
            {
              "choices": [{
                "message": {
                  "role": "assistant",
                  "content": "{ \"recommendedSession\": { \"activityIntent\": \"mistakes_replay\", \"focusTitle\": \"past participles\", \"reason\": \"you missed the past participle in your last session — let's fix it.\" }, \"focusAreas\": [\"past participle of aller\", \"regular -er verbs\"] }"
                }
              }]
            }
            """);
        var service = MakeService(repository, handler);

        var plan = await service.GetTodayPlanAsync(Tenant, User, CorrelationId.Create("corr-p"), CancellationToken.None);

        Assert.Equal("mistakes_replay", plan.RecommendedSession.ActivityIntent);
        Assert.Equal("past participles", plan.RecommendedSession.FocusTitle);
        Assert.Contains("past participle", plan.RecommendedSession.Reason);
        Assert.Equal(2, plan.FocusAreas.Count);
        Assert.Equal("corr-p", plan.CorrelationId);

        // The prompt embedded the debrief evidence so the model can ground
        // its recommendation.
        Assert.Contains("You practised past tense.", handler.Body, StringComparison.Ordinal);
        Assert.Contains("past participle", handler.Body, StringComparison.Ordinal);
        Assert.Contains("fr-FR", handler.Body, StringComparison.Ordinal);
        Assert.Contains("A1-A2", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GetTodayPlanAsyncSendsBearerTokenOnlyInAuthorizationHeaderAndRequestsJsonObject()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithDebriefs([]));
        var handler = new RecordingHttpMessageHandler(ChoicesResponseBody());
        var service = MakeService(repository, handler);

        await service.GetTodayPlanAsync(Tenant, User, CorrelationId.Create("corr-h"), CancellationToken.None);

        Assert.Equal("Bearer server-api-key", handler.Request?.Headers.Authorization?.ToString());
        Assert.DoesNotContain("server-api-key", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"response_format\":{\"type\":\"json_object\"}", handler.Body, StringComparison.Ordinal);
        Assert.Contains("gpt-5.6-sol", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task GetTodayPlanAsyncTolerantOfMinimalModelOutputAndSuppliesSafeDefaults()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithDebriefs([]));
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"{}"}}]}
            """);
        var service = MakeService(repository, handler);

        var plan = await service.GetTodayPlanAsync(Tenant, User, CorrelationId.Create("corr-min"), CancellationToken.None);

        Assert.Equal("open_practice", plan.RecommendedSession.ActivityIntent);
        Assert.Equal(string.Empty, plan.RecommendedSession.FocusTitle);
        Assert.Equal(string.Empty, plan.RecommendedSession.Reason);
        Assert.Empty(plan.FocusAreas);
    }

    [Fact]
    public async Task GetTodayPlanAsyncThrowsLearnerPlanExceptionOnUpstreamFailure()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithDebriefs([]));
        var handler = new RecordingHttpMessageHandler("""{"error":"quota"}""", HttpStatusCode.TooManyRequests);
        var service = MakeService(repository, handler);

        await Assert.ThrowsAsync<LearnerPlanException>(() =>
            service.GetTodayPlanAsync(Tenant, User, CorrelationId.Create("corr-fail"), CancellationToken.None));
    }

    [Fact]
    public async Task GetTodayPlanAsyncThrowsLearnerPlanExceptionWhenModelReturnsNonJson()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithDebriefs([]));
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"not JSON, just words"}}]}
            """);
        var service = MakeService(repository, handler);

        await Assert.ThrowsAsync<LearnerPlanException>(() =>
            service.GetTodayPlanAsync(Tenant, User, CorrelationId.Create("corr-nj"), CancellationToken.None));
    }

    // MARK: - Helpers

    private static string ChoicesResponseBody()
    {
        return """
            {"choices":[{"message":{"role":"assistant","content":"{\"recommendedSession\":{\"activityIntent\":\"open_practice\",\"focusTitle\":\"\",\"reason\":\"\"},\"focusAreas\":[]}"}}]}
            """;
    }

    private static OpenAiLearnerPlanService MakeService(FakeRepository repository, string responseBody)
    {
        return MakeService(repository, new RecordingHttpMessageHandler(responseBody));
    }

    private static OpenAiLearnerPlanService MakeService(FakeRepository repository, RecordingHttpMessageHandler handler)
    {
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        return new OpenAiLearnerPlanService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.CurriculumModel,
                "gpt-5.6-sol",
                "high",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            repository,
            NullLogger<OpenAiLearnerPlanService>.Instance);
    }

    private static LearnerState StateWithDebriefs(IReadOnlyList<RecordedDebrief> debriefs)
    {
        return LearnerState.Create(
            Tenant,
            User,
            new LearnerProfile(Tenant, User, "fr-FR", "en-US", "A1-A2", ["travel"], 15),
            ActiveLearningPlan.Empty,
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty,
            new TutorEvidence(debriefs));
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

    private sealed class FakeRepository : ILearnerStateRepository
    {
        private readonly Dictionary<(string, string), LearnerState> store = new();

        public void Seed(LearnerState state)
        {
            store[(state.TenantId.Value, state.UserId.Value)] = state;
        }

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            store.TryGetValue((tenantId.Value, userId.Value), out var state);
            return Task.FromResult<LearnerState?>(state);
        }

        public Task<LearnerState> SaveAsync(LearnerState state, LearnerStateVersion? expectedVersion, CancellationToken cancellationToken)
            => throw new NotSupportedException();

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
            => throw new NotSupportedException();
    }
}
