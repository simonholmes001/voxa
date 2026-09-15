using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Voxa.Application.Learners;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Application.Authentication;

public sealed class AccountDataService(
    ILearnerStateRepository learnerStates,
    IRefreshSessionStore refreshSessions,
    IRealtimeSessionAuditLog realtimeAuditLog,
    IRealtimeSessionRateLimiter realtimeRateLimiter,
    ILogger<AccountDataService>? logger = null) : IAccountDataService
{
    private readonly ILogger<AccountDataService> logger = logger ?? NullLogger<AccountDataService>.Instance;

    public async Task<AccountDataExport> ExportAsync(
        AppSessionPrincipal principal,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var states = await learnerStates.ListAsync(
            principal.TenantId,
            principal.UserId,
            cancellationToken);

        return new AccountDataExport(
            correlationId.Value,
            principal.TenantId.Value,
            principal.UserId.Value,
            DateTimeOffset.UtcNow,
            "2026-09-15",
            states.Select(ToExport).ToArray());
    }

    public async Task<AccountDeletionResult> DeleteAsync(
        AppSessionPrincipal principal,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var states = await learnerStates.ListAsync(
            principal.TenantId,
            principal.UserId,
            cancellationToken);

        try
        {
            await refreshSessions.RevokeAllAsync(
                new VerifiedAppSessionSubject(principal.TenantId, principal.UserId),
                cancellationToken);
            await realtimeAuditLog.DeleteForSubjectAsync(principal.TenantId, principal.UserId, cancellationToken);
            await realtimeRateLimiter.DeleteForSubjectAsync(principal.TenantId, principal.UserId, cancellationToken);
            await learnerStates.DeleteAsync(principal.TenantId, principal.UserId, cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            logger.LogError(
                exception,
                "Account deletion cleanup failed. correlationId={CorrelationId}",
                correlationId.Value);
            throw;
        }

        return new AccountDeletionResult(
            correlationId.Value,
            Deleted: true,
            DeletedLanguageProfileCount: states.Count);
    }

    private static AccountLanguageProfileExport ToExport(LearnerState state)
    {
        return new AccountLanguageProfileExport(
            state.Profile.TargetLanguage,
            state.Version.Value,
            new LearnerProfileContract(
                state.Profile.TargetLanguage,
                state.Profile.NativeLanguage,
                state.Profile.ProficiencyLevel,
                state.Profile.Goals,
                state.Profile.DailyMinutes),
            new ActiveLearningPlanExport(
                state.ActivePlan.PlanId,
                state.ActivePlan.Title,
                state.ActivePlan.KnowledgeUnitIds,
                state.ActivePlan.Lessons
                    .Select(lesson => new PlannedLessonExport(
                        lesson.LessonId,
                        lesson.Title,
                        lesson.LearningObjective,
                        lesson.Order,
                        lesson.EstimatedMinutes,
                        lesson.Status.ToString()))
                    .ToArray()),
            new LessonCheckpointContract(
                state.CurrentLesson.LessonId,
                state.CurrentLesson.KnowledgeUnitId,
                state.CurrentLesson.StepIndex,
                state.CurrentLesson.UpdatedAt),
            state.ReviewQueue.Items
                .Select(item => new ReviewQueueItemContract(item.KnowledgeUnitId, item.DueAt, item.Priority))
                .ToArray(),
            state.RecentSessions.Items
                .Select(item => new SessionSummaryContract(item.SessionId, item.StartedAt, item.DurationSeconds, item.LessonId))
                .ToArray(),
            state.TutorEvidence.RecentDebriefs
                .Select(debrief => new AccountDebriefExport(
                    debrief.CorrelationId,
                    debrief.RecordedAt,
                    debrief.Summary,
                    debrief.RecurringMistakes
                        .Select(mistake => new AccountMistakeExport(mistake.Pattern, mistake.Example, mistake.Severity))
                        .ToArray(),
                    debrief.UsefulPhrases,
                    debrief.PronunciationNotes,
                    new RecommendedNextDrillExport(
                        debrief.RecommendedNextDrill.ActivityIntent,
                        debrief.RecommendedNextDrill.FocusTitle,
                        debrief.RecommendedNextDrill.Reason)))
                .ToArray());
    }
}
