using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

public sealed record ResumeCheckpointQuery(TenantId TenantId, UserId UserId, CorrelationId CorrelationId);

public sealed record ResumeCheckpointResponse(
    string CorrelationId,
    long Version,
    LearnerProfileContract Profile,
    ActiveLearningPlanContract ActivePlan,
    LessonCheckpointContract CurrentLesson,
    IReadOnlyList<ReviewQueueItemContract> ReviewQueue,
    IReadOnlyList<SessionSummaryContract> RecentSessions);

public sealed record LearnerProfileContract(
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel);

public sealed record ActiveLearningPlanContract(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds);

public sealed record LessonCheckpointContract(
    string LessonId,
    string KnowledgeUnitId,
    int StepIndex,
    DateTimeOffset UpdatedAt);

public sealed record ReviewQueueItemContract(
    string KnowledgeUnitId,
    DateTimeOffset DueAt,
    int Priority);

public sealed record SessionSummaryContract(
    string SessionId,
    DateTimeOffset StartedAt,
    int DurationSeconds,
    string? LessonId);
