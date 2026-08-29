namespace Voxa.Domain.Learners;

public sealed record LearnerState(
    TenantId TenantId,
    UserId UserId,
    LearnerStateVersion Version,
    LearnerProfile Profile,
    ActiveLearningPlan ActivePlan,
    LessonCheckpoint CurrentLesson,
    ReviewQueue ReviewQueue,
    RecentSessionSummaries RecentSessions)
{
    public static LearnerState Create(
        TenantId tenantId,
        UserId userId,
        LearnerProfile profile,
        ActiveLearningPlan activePlan,
        LessonCheckpoint currentLesson,
        ReviewQueue reviewQueue,
        RecentSessionSummaries recentSessions)
    {
        if (profile.TenantId != tenantId || profile.UserId != userId)
        {
            throw new ArgumentException("Learner profile scope must match the learner state scope.", nameof(profile));
        }

        return new LearnerState(
            tenantId,
            userId,
            LearnerStateVersion.Create(1),
            profile,
            activePlan,
            currentLesson,
            reviewQueue,
            recentSessions);
    }

    public LearnerState WithVersion(LearnerStateVersion version) => this with { Version = version };
}

public sealed record LearnerProfile(
    TenantId TenantId,
    UserId UserId,
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel);

public sealed record ActiveLearningPlan(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds)
{
    public static ActiveLearningPlan Empty { get; } = new("", "", []);
}

public sealed record LessonCheckpoint(
    string LessonId,
    string KnowledgeUnitId,
    int StepIndex,
    DateTimeOffset UpdatedAt)
{
    public static LessonCheckpoint None { get; } = new("", "", 0, DateTimeOffset.UnixEpoch);
}

public sealed record ReviewQueue(IReadOnlyList<ReviewQueueItem> Items)
{
    public static ReviewQueue Empty { get; } = new([]);
}

public sealed record ReviewQueueItem(
    string KnowledgeUnitId,
    DateTimeOffset DueAt,
    int Priority);

public sealed record RecentSessionSummaries(IReadOnlyList<SessionSummary> Items)
{
    public static RecentSessionSummaries Empty { get; } = new([]);
}

public sealed record SessionSummary(
    string SessionId,
    DateTimeOffset StartedAt,
    int DurationSeconds,
    string? LessonId);
