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
    IReadOnlyList<string> KnowledgeUnitIds,
    IReadOnlyList<PlannedLesson> Lessons)
{
    /// <summary>
    /// Convenience constructor for legacy callsites that only know a plan
    /// id + title + knowledge-unit ids. The C3 lessons list defaults to
    /// empty; the Home course arc treats an empty list as "no course yet"
    /// and falls back to the pre-C3 title-only rendering.
    /// </summary>
    public ActiveLearningPlan(string PlanId, string Title, IReadOnlyList<string> KnowledgeUnitIds)
        : this(PlanId, Title, KnowledgeUnitIds, Array.Empty<PlannedLesson>()) { }

    public static ActiveLearningPlan Empty { get; } = new("", "", [], []);

    /// <summary>
    /// The single lesson the learner should see as "current" in the Home
    /// course arc. First lesson whose status is <see cref="PlannedLessonStatus.Current"/>;
    /// falls back to the first pending lesson, or null when the course is
    /// empty / fully completed.
    /// </summary>
    public PlannedLesson? CurrentLesson =>
        Lessons.FirstOrDefault(lesson => lesson.Status == PlannedLessonStatus.Current)
            ?? Lessons.FirstOrDefault(lesson => lesson.Status == PlannedLessonStatus.Pending);
}

/// <summary>
/// One lesson in the learner's course arc. Ordered by <see cref="Order"/>,
/// which is dense and stable — a reassessment produces a new list with
/// new ordering; individual lessons don't renumber.
/// </summary>
public sealed record PlannedLesson(
    string LessonId,
    string Title,
    string LearningObjective,
    int Order,
    int EstimatedMinutes,
    PlannedLessonStatus Status);

public enum PlannedLessonStatus
{
    Pending,
    Current,
    Completed,
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
