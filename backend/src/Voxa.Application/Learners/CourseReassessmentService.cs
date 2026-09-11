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
        for (var attempt = 0; attempt < MaxConcurrencyAttempts; attempt++)
        {
            var state = await repository.GetAsync(command.TenantId, command.UserId, cancellationToken)
                ?? throw new LearnerStateNotFoundException(command.TenantId, command.UserId);

            var completedLessonIds = state.ActivePlan.Lessons
                .Where(lesson => lesson.Status == PlannedLessonStatus.Completed)
                .Select(lesson => lesson.LessonId)
                .ToArray();

            var newPlan = await courseAuthor.AuthorCourseAsync(
                new CourseAuthorRequest(
                    command.TenantId,
                    command.UserId,
                    command.CorrelationId,
                    state.Profile,
                    ExistingCourse: state.ActivePlan,
                    CompletedLessonIds: completedLessonIds,
                    RecentDebriefs: state.TutorEvidence.RecentDebriefs,
                    ReassessmentRequest: command.ReassessmentRequest),
                cancellationToken);

            var updated = state with { ActivePlan = newPlan };

            try
            {
                var saved = await repository.SaveAsync(updated, state.Version, cancellationToken);
                return saved.ActivePlan;
            }
            catch (StaleLearnerStateVersionException)
            {
                if (attempt == MaxConcurrencyAttempts - 1)
                {
                    throw;
                }
                // Re-read + re-mint on the fresher state.
            }
        }

        throw new InvalidOperationException("Course reassessment did not produce a result.");
    }
}
