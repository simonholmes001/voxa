using Voxa.Application.Learners;
using Voxa.Application.Onboarding;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class OnboardingServiceTests
{
    [Fact]
    public async Task SubmitAsyncReturnsSavedVersionWhenUpdatingExistingLearner()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var existing = await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new OnboardingService(repository);

        var response = await service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A2",
                ["travel", "conversation"],
                20,
                CorrelationId.Create("corr-123")),
            CancellationToken.None);

        Assert.Equal(existing.Version.Next().Value, response.Version);
        Assert.Equal("Spanish", response.Profile.TargetLanguage);
        Assert.Equal(["travel", "conversation"], response.Profile.Goals);
        Assert.Equal(20, response.Profile.DailyMinutes);
    }

    [Fact]
    public async Task SubmitAsyncRejectsAStaleClientVersion()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new OnboardingService(repository);

        await Assert.ThrowsAsync<StaleLearnerStateVersionException>(() => service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A2",
                ["travel"],
                20,
                CorrelationId.Create("corr-stale"),
                LearnerStateVersion.Create(0)),
            CancellationToken.None));
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "French", "English", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-a1", "Beginner Foundations", ["greetings"]),
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
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

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.Remove(Key(tenantId, userId));
            return Task.CompletedTask;
        }

        private static string Key(TenantId tenantId, UserId userId) => $"{tenantId.Value}:{userId.Value}";
    }
}
