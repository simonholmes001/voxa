using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

/// <summary>
/// Runs a course re-mint on the learner's state, preserving progress
/// on completed lessons and writing the new plan back with
/// optimistic-concurrency retry. Explicit-request path for the "Reassess
/// my course" affordance; also invoked when accumulated debrief evidence
/// suggests the course no longer fits (Home surfaces a banner asking
/// the learner to confirm — never a silent reshape).
/// </summary>
public interface ICourseReassessmentService
{
    Task<ActiveLearningPlan> ReassessAsync(
        CourseReassessmentCommand command,
        CancellationToken cancellationToken);
}

public sealed record CourseReassessmentCommand(
    TenantId TenantId,
    UserId UserId,
    CorrelationId CorrelationId,
    string? ReassessmentRequest);

public sealed class CourseReassessmentService(
    ILearnerStateRepository repository,
    ICourseAuthorService courseAuthor) : ICourseReassessmentService
{
    private const int MaxConcurrencyAttempts = 3;

    public async Task<ActiveLearningPlan> ReassessAsync(
        CourseReassessmentCommand command,
        CancellationToken cancellationToken)
    {
        // 1. Read state once and mint ONCE, outside the retry loop.
        //    The OpenAI author call is expensive, non-idempotent, and
        //    externally billed — running it on each optimistic-concurrency
        //    conflict multiplied cost and could silently swap one accepted
        //    plan for a different one, changing completed/current mapping
        //    between attempts. See docs/decisions/reassessment-retry.md.
        var initialState = await repository.GetAsync(command.TenantId, command.UserId, cancellationToken)
            ?? throw new LearnerStateNotFoundException(command.TenantId, command.UserId);

        var mintedPlan = await courseAuthor.AuthorCourseAsync(
            new CourseAuthorRequest(
                command.TenantId,
                command.UserId,
                command.CorrelationId,
                initialState.Profile,
                ExistingCourse: initialState.ActivePlan,
                CompletedLessonIds: ExtractCompletedLessonIds(initialState.ActivePlan),
                RecentDebriefs: initialState.TutorEvidence.RecentDebriefs,
                ReassessmentRequest: command.ReassessmentRequest),
            cancellationToken);

        // 2. Save with optimistic-concurrency retry. On a stale-version
        //    conflict we RE-READ the fresher state and REMAP the minted
        //    plan's lesson statuses against the fresh CompletedLessonIds
        //    — a purely local operation — rather than re-authoring. This
        //    means the model output the learner sees is deterministic:
        //    whichever plan the first successful mint produced is what
        //    lands, regardless of contention.
        var stateForSave = initialState;
        var planForSave = mintedPlan;
        for (var attempt = 0; attempt < MaxConcurrencyAttempts; attempt++)
        {
            try
            {
                var updated = stateForSave with { ActivePlan = planForSave };
                var saved = await repository.SaveAsync(updated, stateForSave.Version, cancellationToken);
                return saved.ActivePlan;
            }
            catch (StaleLearnerStateVersionException)
            {
                if (attempt == MaxConcurrencyAttempts - 1)
                {
                    throw;
                }
                stateForSave = await repository.GetAsync(command.TenantId, command.UserId, cancellationToken)
                    ?? throw new LearnerStateNotFoundException(command.TenantId, command.UserId);
                var freshCompletedIds = ExtractCompletedLessonIds(stateForSave.ActivePlan);
                planForSave = ApplyCompletionStatuses(mintedPlan, freshCompletedIds);
            }
        }

        throw new InvalidOperationException("Course reassessment did not produce a result.");
    }

    private static IReadOnlyList<string> ExtractCompletedLessonIds(ActiveLearningPlan plan)
    {
        return plan.Lessons
            .Where(lesson => lesson.Status == PlannedLessonStatus.Completed)
            .Select(lesson => lesson.LessonId)
            .ToArray();
    }

    /// <summary>
    /// Reapplies completion/current/pending status to the minted plan's
    /// lessons from a fresh set of completed lesson ids. Structural
    /// content (titles, objectives, order, ids) is preserved verbatim.
    /// Used only on the retry path so a concurrent completion between
    /// mint and save is reflected in the persisted plan without re-
    /// authoring.
    /// </summary>
    private static ActiveLearningPlan ApplyCompletionStatuses(
        ActiveLearningPlan mintedPlan,
        IReadOnlyCollection<string> completedLessonIds)
    {
        var completed = new HashSet<string>(completedLessonIds, StringComparer.OrdinalIgnoreCase);
        var currentAssigned = false;
        var lessons = mintedPlan.Lessons
            .OrderBy(lesson => lesson.Order)
            .Select(lesson =>
            {
                PlannedLessonStatus status;
                if (completed.Contains(lesson.LessonId))
                {
                    status = PlannedLessonStatus.Completed;
                }
                else if (!currentAssigned)
                {
                    status = PlannedLessonStatus.Current;
                    currentAssigned = true;
                }
                else
                {
                    status = PlannedLessonStatus.Pending;
                }
                return lesson with { Status = status };
            })
            .ToArray();
        return mintedPlan with { Lessons = lessons };
    }
}
