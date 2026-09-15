using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Authentication;

public interface IAccountDataService
{
    Task<AccountDataExport> ExportAsync(
        AppSessionPrincipal principal,
        CorrelationId correlationId,
        CancellationToken cancellationToken);

    Task<AccountDeletionResult> DeleteAsync(
        AppSessionPrincipal principal,
        CorrelationId correlationId,
        CancellationToken cancellationToken);
}

public sealed record AccountDataExport(
    string CorrelationId,
    string TenantId,
    string UserId,
    DateTimeOffset ExportedAt,
    string SchemaVersion,
    IReadOnlyList<AccountLanguageProfileExport> LanguageProfiles);

public sealed record AccountLanguageProfileExport(
    string LanguageKey,
    long Version,
    LearnerProfileContract Profile,
    ActiveLearningPlanExport ActivePlan,
    LessonCheckpointContract CurrentLesson,
    IReadOnlyList<ReviewQueueItemContract> ReviewQueue,
    IReadOnlyList<SessionSummaryContract> RecentSessions,
    IReadOnlyList<AccountDebriefExport> TutorEvidence);

public sealed record ActiveLearningPlanExport(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds,
    IReadOnlyList<PlannedLessonExport> Lessons);

public sealed record PlannedLessonExport(
    string LessonId,
    string Title,
    string LearningObjective,
    int Order,
    int EstimatedMinutes,
    string Status);

public sealed record AccountDebriefExport(
    string CorrelationId,
    DateTimeOffset RecordedAt,
    string Summary,
    IReadOnlyList<AccountMistakeExport> RecurringMistakes,
    IReadOnlyList<string> UsefulPhrases,
    IReadOnlyList<string> PronunciationNotes,
    RecommendedNextDrillExport RecommendedNextDrill);

public sealed record AccountMistakeExport(string Pattern, string Example, string Severity);

public sealed record RecommendedNextDrillExport(string ActivityIntent, string FocusTitle, string Reason);

public sealed record AccountDeletionResult(
    string CorrelationId,
    bool Deleted,
    int DeletedLanguageProfileCount);
