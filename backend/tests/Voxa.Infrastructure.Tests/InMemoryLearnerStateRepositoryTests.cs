using Voxa.Domain.Learners;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Infrastructure.Tests;

public sealed class InMemoryLearnerStateRepositoryTests
{
    [Fact]
    public async Task GetAsyncReturnsOnlyTheRequestedTenantAndUserState()
    {
        var repository = new InMemoryLearnerStateRepository();
        var userId = UserId.Create("user-a");
        await repository.SaveAsync(CreateState(TenantId.Create("tenant-a"), userId), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(TenantId.Create("tenant-b"), userId), null, CancellationToken.None);

        var tenantAState = await repository.GetAsync(TenantId.Create("tenant-a"), userId, CancellationToken.None);

        Assert.NotNull(tenantAState);
        Assert.Equal("tenant-a", tenantAState.TenantId.Value);
    }

    [Fact]
    public async Task SaveAsyncIncrementsVersionWhenExpectedVersionMatches()
    {
        var repository = new InMemoryLearnerStateRepository();
        var state = CreateState(TenantId.Create("tenant-a"), UserId.Create("user-a"));
        var firstSave = await repository.SaveAsync(state, null, CancellationToken.None);

        var secondSave = await repository.SaveAsync(firstSave, firstSave.Version, CancellationToken.None);

        Assert.Equal(2, secondSave.Version.Value);
    }

    [Fact]
    public async Task SaveAsyncRejectsCreateWithUnexpectedVersion()
    {
        var repository = new InMemoryLearnerStateRepository();
        var state = CreateState(TenantId.Create("tenant-a"), UserId.Create("user-a"));

        await Assert.ThrowsAsync<StaleLearnerStateVersionException>(() =>
            repository.SaveAsync(state, LearnerStateVersion.Create(1), CancellationToken.None));
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
}
