using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class LearningSessionCompletionEndpointTests
{
    [Fact]
    public async Task PostRequiresAuthenticatedAppSession()
    {
        var endpoint = new LearningSessionCompletionEndpoint(new StubLearningSessionCompletionService(null));

        var response = await endpoint.PostAsync(
            null,
            new LearningSessionCompletionHttpRequest("session-1", 60),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task PostValidatesSessionId()
    {
        var endpoint = new LearningSessionCompletionEndpoint(new StubLearningSessionCompletionService(null));

        var response = await endpoint.PostAsync(
            Principal(),
            new LearningSessionCompletionHttpRequest("", 60),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
    }

    [Fact]
    public async Task PostReturnsUpdatedResumeCheckpoint()
    {
        var checkpoint = new ResumeCheckpointResponse(
            "corr-123",
            2,
            new LearnerProfileContract("fr-FR", "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlanContract("plan-1", "Beginner Foundations", ["greetings"]),
            new LessonCheckpointContract("lesson-1", "greetings", 2, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            [new ReviewQueueItemContract("greetings", DateTimeOffset.Parse("2026-08-30T07:00:00Z"), 1)],
            [new SessionSummaryContract("session-1", DateTimeOffset.Parse("2026-08-29T07:00:00Z"), 60, "lesson-1")]);
        var service = new StubLearningSessionCompletionService(checkpoint);
        var endpoint = new LearningSessionCompletionEndpoint(service);

        var response = await endpoint.PostAsync(
            Principal(),
            new LearningSessionCompletionHttpRequest("session-1", 60, "lesson"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.Equal("session-1", service.Command?.SessionId);
        Assert.Equal("lesson", service.Command?.SessionIntent);
        Assert.Equal(2, response.Body?.Version);
        Assert.Single(response.Body?.ReviewQueue ?? []);
    }

    [Fact]
    public async Task PostMapsStateVersionConflictToRetryableConflict()
    {
        var endpoint = new LearningSessionCompletionEndpoint(new StaleLearningSessionCompletionService());

        var response = await endpoint.PostAsync(
            Principal(),
            new LearningSessionCompletionHttpRequest("session-1", 60),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(409, response.StatusCode);
        Assert.Equal("learner_state_conflict", response.Error?.Code);
        Assert.True(response.Error?.Retryable);
    }

    private static AppSessionPrincipal Principal()
    {
        return new AppSessionPrincipal(
            TenantId.Create("tenant-a"),
            UserId.Create("user-a"));
    }

    private sealed class StubLearningSessionCompletionService(ResumeCheckpointResponse? checkpoint)
        : ILearningSessionCompletionService
    {
        public CompleteLearningSessionCommand? Command { get; private set; }

        public Task<ResumeCheckpointResponse> CompleteAsync(
            CompleteLearningSessionCommand command,
            CancellationToken cancellationToken)
        {
            Command = command;
            return Task.FromResult(checkpoint ?? throw new LearnerStateNotFoundException(command.TenantId, command.UserId));
        }
    }

    private sealed class StaleLearningSessionCompletionService : ILearningSessionCompletionService
    {
        public Task<ResumeCheckpointResponse> CompleteAsync(
            CompleteLearningSessionCommand command,
            CancellationToken cancellationToken)
        {
            throw new StaleLearnerStateVersionException(
                command.TenantId,
                command.UserId,
                LearnerStateVersion.Create(1),
                LearnerStateVersion.Create(2));
        }
    }
}
