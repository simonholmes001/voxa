using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class LearnerPlanEndpointTests
{
    [Fact]
    public async Task GetAsyncReturns401WhenNoPrincipalIsAttachedToTheRequest()
    {
        var endpoint = new LearnerPlanEndpoint(new FakeLearnerPlanService(_ => throw new NotSupportedException()));

        var response = await endpoint.GetAsync(
            principal: null,
            correlationId: "corr-1",
            cancellationToken: CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task GetAsyncReturns503WhenPlannerFails()
    {
        var endpoint = new LearnerPlanEndpoint(
            new FakeLearnerPlanService(_ => throw new LearnerPlanException("upstream")));

        var response = await endpoint.GetAsync(
            principal: SamplePrincipal(),
            correlationId: "corr-2",
            cancellationToken: CancellationToken.None);

        Assert.Equal(503, response.StatusCode);
        Assert.Equal("learner_plan_unavailable", response.Error?.Code);
        Assert.True(response.Error?.Retryable);
    }

    [Fact]
    public async Task GetAsyncMapsLearnerPlanIntoHttpResponse()
    {
        var endpoint = new LearnerPlanEndpoint(new FakeLearnerPlanService(corr =>
            new LearnerPlan(
                corr.Value,
                new RecommendedSession(
                    "pronunciation_drill",
                    "French u vowel",
                    "you missed the u in *tu* twice last session."),
                ["past-tense forms", "front rounded vowels"])));

        var response = await endpoint.GetAsync(
            principal: SamplePrincipal(),
            correlationId: "corr-3",
            cancellationToken: CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        var body = response.Body!;
        Assert.Equal("corr-3", body.CorrelationId);
        Assert.Equal("pronunciation_drill", body.RecommendedSession.ActivityIntent);
        Assert.Equal("French u vowel", body.RecommendedSession.FocusTitle);
        Assert.Contains("*tu*", body.RecommendedSession.Reason);
        Assert.Equal(2, body.FocusAreas.Count);
    }

    private static AppSessionPrincipal SamplePrincipal()
    {
        return new AppSessionPrincipal(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"));
    }

    private sealed class FakeLearnerPlanService(Func<CorrelationId, LearnerPlan> handler) : ILearnerPlanService
    {
        public Task<LearnerPlan> GetTodayPlanAsync(
            TenantId tenantId,
            UserId userId,
            CorrelationId correlationId,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(handler(correlationId));
        }
    }
}
