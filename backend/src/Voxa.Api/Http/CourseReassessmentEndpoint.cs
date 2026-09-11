using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

/// <summary>
/// POST /api/learner/course/reassess — re-mints the learner's course
/// from their current progress + accumulated debrief evidence + an
/// optional free-text reassessment request. Preserves completed
/// lessons (their IDs carry through). Returns the new course as the
/// same shape iOS reads for the Home course arc.
/// </summary>
public sealed class CourseReassessmentEndpoint(ICourseReassessmentService reassessment)
{
    public async Task<ApiResponse<LearnerCourseHttpResponse>> PostAsync(
        AppSessionPrincipal? principal,
        CourseReassessmentHttpRequest? request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        if (principal is null)
        {
            return ApiResponse<LearnerCourseHttpResponse>.Failure(
                401,
                new ApiErrorResponse(
                    "app_session_required",
                    "An authenticated app session is required.",
                    requestCorrelationId.Value,
                    Retryable: false));
        }

        try
        {
            var plan = await reassessment.ReassessAsync(
                new CourseReassessmentCommand(
                    principal.TenantId,
                    principal.UserId,
                    requestCorrelationId,
                    request?.ReassessmentRequest?.Trim()),
                cancellationToken);
            return ApiResponse<LearnerCourseHttpResponse>.Ok(
                LearnerCourseHttpResponse.FromPlan(plan, requestCorrelationId.Value));
        }
        catch (LearnerStateNotFoundException)
        {
            return ApiResponse<LearnerCourseHttpResponse>.Failure(
                404,
                new ApiErrorResponse(
                    "learner_state_not_found",
                    "This learner has no state to reassess. Complete onboarding first.",
                    requestCorrelationId.Value,
                    Retryable: false));
        }
        catch (CourseAuthorException)
        {
            return ApiResponse<LearnerCourseHttpResponse>.Failure(
                503,
                new ApiErrorResponse(
                    "course_reassessment_unavailable",
                    "The course reassessment service is temporarily unavailable.",
                    requestCorrelationId.Value,
                    Retryable: true));
        }
        catch (StaleLearnerStateVersionException)
        {
            // CourseReassessmentService retries under optimistic
            // concurrency but eventually gives up (currently after
            // MaxConcurrencyAttempts). Without an explicit mapping the
            // exhausted-conflict path escaped as an unhandled 500 —
            // clients couldn't tell it was a transient conflict worth
            // retrying. Surface it as a retryable 503 so client-side
            // recovery is deterministic and telemetry can distinguish
            // "temporary conflict" from a real server bug.
            return ApiResponse<LearnerCourseHttpResponse>.Failure(
                503,
                new ApiErrorResponse(
                    "course_reassessment_conflict",
                    "Your course was being updated at the same time. Please try again.",
                    requestCorrelationId.Value,
                    Retryable: true));
        }
    }
}

public sealed record CourseReassessmentHttpRequest(string? ReassessmentRequest);

public sealed record LearnerCourseHttpResponse(
    string CorrelationId,
    string PlanId,
    string Title,
    IReadOnlyList<PlannedLessonDto> Lessons)
{
    public static LearnerCourseHttpResponse FromPlan(ActiveLearningPlan plan, string correlationId)
    {
        return new LearnerCourseHttpResponse(
            correlationId,
            plan.PlanId,
            plan.Title,
            plan.Lessons
                .OrderBy(lesson => lesson.Order)
                .Select(lesson => new PlannedLessonDto(
                    lesson.LessonId,
                    lesson.Title,
                    lesson.LearningObjective,
                    lesson.Order,
                    lesson.EstimatedMinutes,
                    lesson.Status.ToString()))
                .ToArray());
    }
}

public sealed record PlannedLessonDto(
    string LessonId,
    string Title,
    string LearningObjective,
    int Order,
    int EstimatedMinutes,
    string Status);
