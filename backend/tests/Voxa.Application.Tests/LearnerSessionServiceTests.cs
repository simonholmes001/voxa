using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class LearnerSessionServiceTests
{
    [Fact]
    public async Task GetResumeCheckpointReturnsVersionedTenantScopedState()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearnerSessionService(repository);

        var checkpoint = await service.GetResumeCheckpointAsync(
            new ResumeCheckpointQuery(tenantId, userId, CorrelationId.Create("corr-123")),
            CancellationToken.None);

        Assert.Equal("corr-123", checkpoint.CorrelationId);
        Assert.Equal(1, checkpoint.Version);
        Assert.Equal("fr", checkpoint.Profile.TargetLanguage);
        Assert.Equal("lesson-1", checkpoint.CurrentLesson.LessonId);
        Assert.Single(checkpoint.ReviewQueue);
        Assert.Single(checkpoint.RecentSessions);
    }

    [Fact]
    public async Task GetResumeCheckpointDoesNotLeakStateAcrossTenants()
    {
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(TenantId.Create("tenant-a"), userId), expectedVersion: null, CancellationToken.None);
        var service = new LearnerSessionService(repository);

        await Assert.ThrowsAsync<LearnerStateNotFoundException>(() =>
            service.GetResumeCheckpointAsync(
                new ResumeCheckpointQuery(TenantId.Create("tenant-b"), userId, CorrelationId.Create("corr-123")),
                CancellationToken.None));
    }

    [Fact]
    public async Task SaveLearnerStateRejectsStaleVersions()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var service = new LearnerSessionService(repository);
        var saved = await service.SaveLearnerStateAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);

        await Assert.ThrowsAsync<StaleLearnerStateVersionException>(() =>
            service.SaveLearnerStateAsync(saved, LearnerStateVersion.Create(0), CancellationToken.None));
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "fr", "en", "A1"),
            new ActiveLearningPlan("plan-1", "Survival French", ["greetings"]),
            new LessonCheckpoint("lesson-1", "unit-1", 3, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            new ReviewQueue([new ReviewQueueItem("bonjour", DateTimeOffset.Parse("2026-08-30T07:00:00Z"), 2)]),
            new RecentSessionSummaries([new SessionSummary("session-1", DateTimeOffset.Parse("2026-08-29T07:00:00Z"), 600, "lesson-1")]));
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        private readonly Dictionary<string, LearnerState> states = new();

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.TryGetValue(Key(tenantId, userId), out var state);
            return Task.FromResult(state);
        }

        public Task<LearnerState> SaveAsync(LearnerState state, LearnerStateVersion? expectedVersion, CancellationToken cancellationToken)
        {
            var key = Key(state.TenantId, state.UserId);
            states.TryGetValue(key, out var current);

            if (current is not null && expectedVersion != current.Version)
            {
                throw new StaleLearnerStateVersionException(state.TenantId, state.UserId, expectedVersion, current.Version);
            }

            var nextVersion = current is null ? LearnerStateVersion.Create(1) : current.Version.Next();
            var saved = state.WithVersion(nextVersion);
            states[key] = saved;
            return Task.FromResult(saved);
        }

        private static string Key(TenantId tenantId, UserId userId) => $"{tenantId.Value}:{userId.Value}";
    }
}
