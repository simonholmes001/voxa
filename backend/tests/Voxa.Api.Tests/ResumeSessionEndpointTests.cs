using Voxa.Api.Http;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class ResumeSessionEndpointTests
{
    [Fact]
    public async Task GetReturnsBadRequestForInvalidTenant()
    {
        var endpoint = new ResumeSessionEndpoint(new StubLearnerSessionQueries(null));

        var response = await endpoint.GetAsync("", "user-a", "corr-123", CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
        Assert.Equal("corr-123", response.Error?.CorrelationId);
    }

    [Fact]
    public async Task GetReturnsNotFoundWhenNoCheckpointExists()
    {
        var endpoint = new ResumeSessionEndpoint(new StubLearnerSessionQueries(null));

        var response = await endpoint.GetAsync("tenant-a", "user-a", "corr-123", CancellationToken.None);

        Assert.Equal(404, response.StatusCode);
        Assert.Equal("resume_checkpoint_not_found", response.Error?.Code);
    }

    [Fact]
    public async Task GetReturnsResumeCheckpointWithoutProviderDetails()
    {
        var checkpoint = new ResumeCheckpointResponse(
            "corr-123",
            2,
            new LearnerProfileContract("fr", "en", "A1", ["travel"], 15),
            new ActiveLearningPlanContract("plan-1", "Survival French", ["greetings"]),
            new LessonCheckpointContract("lesson-1", "unit-1", 3, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            [new ReviewQueueItemContract("bonjour", DateTimeOffset.Parse("2026-08-30T07:00:00Z"), 2)],
            [new SessionSummaryContract("session-1", DateTimeOffset.Parse("2026-08-29T07:00:00Z"), 600, "lesson-1")]);
        var endpoint = new ResumeSessionEndpoint(new StubLearnerSessionQueries(checkpoint));

        var response = await endpoint.GetAsync("tenant-a", "user-a", "corr-123", CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.NotNull(response.Body);
        Assert.Equal("lesson-1", response.Body.CurrentLesson.LessonId);
        Assert.DoesNotContain("OpenAI", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Azure", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    private sealed class StubLearnerSessionQueries(ResumeCheckpointResponse? checkpoint) : ILearnerSessionQueries
    {
        public Task<ResumeCheckpointResponse> GetResumeCheckpointAsync(ResumeCheckpointQuery query, CancellationToken cancellationToken)
        {
            if (checkpoint is null)
            {
                throw new LearnerStateNotFoundException(query.TenantId, query.UserId);
            }

            return Task.FromResult(checkpoint);
        }
    }
}
