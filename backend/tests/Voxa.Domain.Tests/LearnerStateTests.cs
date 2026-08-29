using Voxa.Domain.Learners;

namespace Voxa.Domain.Tests;

public sealed class LearnerStateTests
{
    [Fact]
    public void CreateTenantIdRejectsBlankValues()
    {
        Assert.Throws<ArgumentException>(() => TenantId.Create(" "));
    }

    [Fact]
    public void CreateUserIdRejectsBlankValues()
    {
        Assert.Throws<ArgumentException>(() => UserId.Create(""));
    }

    [Fact]
    public void LearnerStateRequiresMatchingProfileScope()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var profile = new LearnerProfile(TenantId.Create("tenant-b"), userId, "fr", "en", "A1");

        Assert.Throws<ArgumentException>(() =>
            LearnerState.Create(
                tenantId,
                userId,
                profile,
                ActiveLearningPlan.Empty,
                LessonCheckpoint.None,
                ReviewQueue.Empty,
                RecentSessionSummaries.Empty));
    }

    [Fact]
    public void NewLearnerStateStartsAtVersionOne()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");

        var state = LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "fr", "en", "A1"),
            new ActiveLearningPlan("plan-1", "Survival French", ["greetings"]),
            new LessonCheckpoint("lesson-1", "unit-1", 3, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            new ReviewQueue([new ReviewQueueItem("bonjour", DateTimeOffset.Parse("2026-08-30T07:00:00Z"), 2)]),
            new RecentSessionSummaries([new SessionSummary("session-1", DateTimeOffset.Parse("2026-08-29T07:00:00Z"), 600, "lesson-1")]));

        Assert.Equal(1, state.Version.Value);
        Assert.Equal("fr", state.Profile.TargetLanguage);
        Assert.Single(state.ReviewQueue.Items);
        Assert.Single(state.RecentSessions.Items);
    }
}
