using Voxa.Domain.Learners;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Infrastructure.Tests;

public sealed class TableLearnerStateRepositoryTests
{
    [Fact]
    public async Task GetAsyncReturnsOnlyTheRequestedTenantAndUserState()
    {
        var table = new InMemoryLearnerStateTable();
        var repository = new TableLearnerStateRepository(table);
        var userId = UserId.Create("user-a");

        await repository.SaveAsync(CreateState(TenantId.Create("tenant-a"), userId), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(TenantId.Create("tenant-b"), userId), null, CancellationToken.None);

        var tenantAState = await repository.GetAsync(TenantId.Create("tenant-a"), userId, CancellationToken.None);

        Assert.NotNull(tenantAState);
        Assert.Equal("tenant-a", tenantAState.TenantId.Value);
    }

    [Fact]
    public async Task SaveAsyncPersistsAJsonRoundTripForCrossDeviceResume()
    {
        var table = new InMemoryLearnerStateTable();
        var repository = new TableLearnerStateRepository(table);
        var state = CreateState(TenantId.Create("tenant-a"), UserId.Create("user-a"));

        var saved = await repository.SaveAsync(state, null, CancellationToken.None);
        var loaded = await repository.GetAsync(state.TenantId, state.UserId, CancellationToken.None);

        Assert.NotNull(loaded);
        Assert.Equal(1, saved.Version.Value);
        Assert.Equal(saved.TenantId, loaded.TenantId);
        Assert.Equal(saved.UserId, loaded.UserId);
        Assert.Equal(saved.Version, loaded.Version);
        Assert.Equal(saved.Profile.TargetLanguage, loaded.Profile.TargetLanguage);
        Assert.Equal(saved.Profile.NativeLanguage, loaded.Profile.NativeLanguage);
        Assert.Equal(saved.Profile.ProficiencyLevel, loaded.Profile.ProficiencyLevel);
        Assert.Equal(saved.Profile.Goals, loaded.Profile.Goals);
        Assert.Equal(saved.Profile.DailyMinutes, loaded.Profile.DailyMinutes);
        Assert.Equal(saved.ActivePlan.PlanId, loaded.ActivePlan.PlanId);
        Assert.Equal(saved.ActivePlan.KnowledgeUnitIds, loaded.ActivePlan.KnowledgeUnitIds);
        Assert.Equal(saved.CurrentLesson, loaded.CurrentLesson);
        Assert.Equal(saved.ReviewQueue.Items, loaded.ReviewQueue.Items);
        Assert.Equal(saved.RecentSessions.Items, loaded.RecentSessions.Items);
    }

    [Fact]
    public async Task GetAsyncDefaultsMissingProfileFieldsFromLegacyDocuments()
    {
        var table = new InMemoryLearnerStateTable();
        var repository = new TableLearnerStateRepository(table);
        await table.UpsertAsync(
            new LearnerStateTableEntity(
                "tenant-a",
                "user-a",
                "etag-1",
                4,
                """
                {
                  "tenantId": "tenant-a",
                  "userId": "user-a",
                  "version": 4,
                  "profile": {
                    "targetLanguage": "fr",
                    "nativeLanguage": "en",
                    "proficiencyLevel": "A1"
                  },
                  "activePlan": {
                    "planId": "plan-1",
                    "title": "Survival French",
                    "knowledgeUnitIds": ["greetings"]
                  },
                  "currentLesson": {
                    "lessonId": "",
                    "knowledgeUnitId": "",
                    "stepIndex": 0,
                    "updatedAt": "1970-01-01T00:00:00+00:00"
                  },
                  "reviewQueue": [],
                  "recentSessions": []
                }
                """),
            expectedETag: null,
            CancellationToken.None);

        var loaded = await repository.GetAsync(TenantId.Create("tenant-a"), UserId.Create("user-a"), CancellationToken.None);

        Assert.NotNull(loaded);
        Assert.Empty(loaded.Profile.Goals);
        Assert.Equal(15, loaded.Profile.DailyMinutes);
        Assert.Equal(4, loaded.Version.Value);
    }

    [Fact]
    public async Task SaveAsyncRejectsStaleVersions()
    {
        var table = new InMemoryLearnerStateTable();
        var repository = new TableLearnerStateRepository(table);
        var state = CreateState(TenantId.Create("tenant-a"), UserId.Create("user-a"));
        var saved = await repository.SaveAsync(state, null, CancellationToken.None);

        await Assert.ThrowsAsync<StaleLearnerStateVersionException>(() =>
            repository.SaveAsync(saved, LearnerStateVersion.Create(0), CancellationToken.None));
    }

    [Fact]
    public async Task DeleteAsyncRemovesOnlyTheRequestedTenantAndUserState()
    {
        var table = new InMemoryLearnerStateTable();
        var repository = new TableLearnerStateRepository(table);
        var userId = UserId.Create("user-a");
        await repository.SaveAsync(CreateState(TenantId.Create("tenant-a"), userId), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(TenantId.Create("tenant-b"), userId), null, CancellationToken.None);

        await repository.DeleteAsync(TenantId.Create("tenant-a"), userId, CancellationToken.None);

        Assert.Null(await repository.GetAsync(TenantId.Create("tenant-a"), userId, CancellationToken.None));
        Assert.NotNull(await repository.GetAsync(TenantId.Create("tenant-b"), userId, CancellationToken.None));
    }

    [Fact]
    public async Task ListAsyncIgnoresActiveLanguageMarkersForOtherUsers()
    {
        var table = new InMemoryLearnerStateTable();
        var repository = new TableLearnerStateRepository(table);
        var tenant = TenantId.Create("tenant-a");
        var user = UserId.Create("user-a");
        var otherUser = UserId.Create("user-b");

        await repository.SaveAsync(CreateState(tenant, user), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(tenant, otherUser), null, CancellationToken.None);
        await repository.SetActiveLanguageAsync(tenant, otherUser, "fr", CancellationToken.None);

        var profiles = await repository.ListAsync(tenant, user, CancellationToken.None);

        Assert.Single(profiles);
        Assert.Equal("fr", profiles[0].Profile.TargetLanguage);
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "fr", "en", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-1", "Survival French", ["greetings"]),
            new LessonCheckpoint("lesson-1", "unit-1", 3, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            new ReviewQueue([new ReviewQueueItem("bonjour", DateTimeOffset.Parse("2026-08-30T07:00:00Z"), 2)]),
            new RecentSessionSummaries([new SessionSummary("session-1", DateTimeOffset.Parse("2026-08-29T07:00:00Z"), 600, "lesson-1")]));
    }
}
