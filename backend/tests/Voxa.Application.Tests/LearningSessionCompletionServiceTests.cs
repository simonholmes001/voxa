using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class LearningSessionCompletionServiceTests
{
    [Fact]
    public async Task CompleteAsyncRecordsRecentSessionAndQueuesCurrentLessonReview()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-123",
                lessonId: null,
                knowledgeUnitId: null,
                durationSeconds: 540,
                sessionIntent: "lesson",
                correlationId: "corr-complete"),
            CancellationToken.None);

        Assert.Equal("corr-complete", checkpoint.CorrelationId);
        Assert.Equal(2, checkpoint.Version);
        Assert.Equal("lesson-1", checkpoint.CurrentLesson.LessonId);
        Assert.Equal(2, checkpoint.CurrentLesson.StepIndex);
        Assert.Equal("greetings", checkpoint.ReviewQueue.First().KnowledgeUnitId);
        Assert.Equal(1, checkpoint.ReviewQueue.First().Priority);
        Assert.Equal("session-123", checkpoint.RecentSessions.First().SessionId);
        Assert.Equal(540, checkpoint.RecentSessions.First().DurationSeconds);
        Assert.Equal("lesson-1", checkpoint.RecentSessions.First().LessonId);
    }

    [Fact]
    public async Task CompleteAsyncIsIdempotentForSameSessionId()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var command = CompleteLearningSessionCommand.Create(
            tenantId.Value,
            userId.Value,
            "session-123",
            lessonId: "lesson-1",
            knowledgeUnitId: "greetings",
            durationSeconds: 300,
            sessionIntent: "lesson",
            correlationId: "corr-complete");

        await service.CompleteAsync(command, CancellationToken.None);
        var checkpoint = await service.CompleteAsync(command, CancellationToken.None);

        Assert.Equal(2, checkpoint.Version);
        Assert.Equal(2, checkpoint.CurrentLesson.StepIndex);
        Assert.Single(checkpoint.RecentSessions);
        Assert.Single(checkpoint.ReviewQueue);
    }

    [Fact]
    public async Task CompleteAsyncRequiresExistingLearnerState()
    {
        var service = new LearningSessionCompletionService(new RecordingLearnerStateRepository());

        await Assert.ThrowsAsync<LearnerStateNotFoundException>(() =>
            service.CompleteAsync(
                CompleteLearningSessionCommand.Create(
                    "tenant-a",
                    "user-a",
                    "session-123",
                    lessonId: null,
                    knowledgeUnitId: null,
                    durationSeconds: 60,
                    sessionIntent: "practice",
                    correlationId: "corr-complete"),
                CancellationToken.None));
    }

    [Fact]
    public async Task CompleteAsyncReturnsRecordedSessionWhenSaveBecomesStale()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository
        {
            RecordSessionOnNextStaleSave = "session-123"
        };
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-123",
                lessonId: "lesson-1",
                knowledgeUnitId: "greetings",
                durationSeconds: 300,
                sessionIntent: "lesson",
                correlationId: "corr-complete"),
            CancellationToken.None);

        Assert.Equal(2, checkpoint.Version);
        Assert.Single(checkpoint.RecentSessions);
        Assert.Equal("session-123", checkpoint.RecentSessions.First().SessionId);
    }

    [Fact]
    public async Task CompleteAsyncDoesNotReplaceCurrentLessonForReviewFocus()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "review-123",
                lessonId: "different-lesson",
                knowledgeUnitId: "different-unit",
                durationSeconds: 120,
                sessionIntent: "review",
                correlationId: "corr-review"),
            CancellationToken.None);

        Assert.Equal("lesson-1", checkpoint.CurrentLesson.LessonId);
        Assert.Equal("greetings", checkpoint.CurrentLesson.KnowledgeUnitId);
        Assert.Equal(1, checkpoint.CurrentLesson.StepIndex);
        Assert.Equal("different-unit", checkpoint.ReviewQueue.First().KnowledgeUnitId);
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "fr-FR", "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-1", "Beginner Foundations", ["greetings"]),
            new LessonCheckpoint("lesson-1", "greetings", 1, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        private readonly Dictionary<string, LearnerState> states = new();

        public string? RecordSessionOnNextStaleSave { get; init; }

        private bool hasRecordedSessionOnStaleSave;

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.TryGetValue(Key(tenantId, userId), out var state);
            return Task.FromResult(state);
        }

        public Task<LearnerState> SaveAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            var key = Key(state.TenantId, state.UserId);
            states.TryGetValue(key, out var current);
            if (current is not null && RecordSessionOnNextStaleSave is not null && !hasRecordedSessionOnStaleSave)
            {
                hasRecordedSessionOnStaleSave = true;
                var concurrentState = current with
                {
                    RecentSessions = new RecentSessionSummaries(
                    [new SessionSummary(RecordSessionOnNextStaleSave, DateTimeOffset.UtcNow, 300, "lesson-1")])
                };
                states[key] = concurrentState.WithVersion(current.Version.Next());
                throw new StaleLearnerStateVersionException(
                    state.TenantId,
                    state.UserId,
                    expectedVersion,
                    states[key].Version);
            }
            if (current is not null && expectedVersion != current.Version)
            {
                throw new StaleLearnerStateVersionException(state.TenantId, state.UserId, expectedVersion, current.Version);
            }

            var saved = state.WithVersion(current?.Version.Next() ?? LearnerStateVersion.Create(1));
            states[key] = saved;
            return Task.FromResult(saved);
        }

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.Remove(Key(tenantId, userId));
            return Task.CompletedTask;
        }

        private static string Key(TenantId tenantId, UserId userId) => $"{tenantId.Value}:{userId.Value}";
    }
}
