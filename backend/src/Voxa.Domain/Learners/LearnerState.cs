namespace Voxa.Domain.Learners;

public sealed record LearnerState(
    TenantId TenantId,
    UserId UserId,
    LearnerStateVersion Version,
    LearnerProfile Profile,
    ActiveLearningPlan ActivePlan,
    LessonCheckpoint CurrentLesson,
    ReviewQueue ReviewQueue,
    RecentSessionSummaries RecentSessions,
    TutorEvidence TutorEvidence)
{
    public static LearnerState Create(
        TenantId tenantId,
        UserId userId,
        LearnerProfile profile,
        ActiveLearningPlan activePlan,
        LessonCheckpoint currentLesson,
        ReviewQueue reviewQueue,
        RecentSessionSummaries recentSessions,
        TutorEvidence? tutorEvidence = null)
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
            recentSessions,
            tutorEvidence ?? TutorEvidence.Empty);
    }

    public LearnerState WithVersion(LearnerStateVersion version) => this with { Version = version };
}

public sealed record LearnerProfile(
    TenantId TenantId,
    UserId UserId,
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel,
    IReadOnlyList<string> Goals,
    int DailyMinutes);

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

/// <summary>
/// Rolling record of what the post-session debrief pass has surfaced across
/// the learner's recent sessions. Newest first, capped at
/// <see cref="MaxRecentDebriefs"/>. Fed by the /api/realtime/debrief endpoint
/// so the curriculum planner (Phase C2) has evidence to plan against.
/// </summary>
public sealed record TutorEvidence(IReadOnlyList<RecordedDebrief> RecentDebriefs)
{
    /// <summary>
    /// Retention cap for RecentDebriefs. 20 entries covers roughly two weeks
    /// of daily practice; older debriefs roll off the tail so the JSON blob
    /// stays small (~10–30 KB) and reads stay fast.
    /// </summary>
    public const int MaxRecentDebriefs = 20;

    public static TutorEvidence Empty { get; } = new([]);
}

/// <summary>
/// One post-session debrief, persisted to learner state so the planner can
/// aggregate patterns across sessions. Shape mirrors the debrief prompt's
/// output schema plus a server-side correlation id and timestamp.
/// </summary>
public sealed record RecordedDebrief(
    string CorrelationId,
    DateTimeOffset RecordedAt,
    string Summary,
    IReadOnlyList<RecordedMistake> RecurringMistakes,
    IReadOnlyList<string> UsefulPhrases,
    IReadOnlyList<string> PronunciationNotes,
    RecommendedNextDrill RecommendedNextDrill);

public sealed record RecordedMistake(string Pattern, string Example, string Severity);

public sealed record RecommendedNextDrill(string ActivityIntent, string FocusTitle, string Reason);
