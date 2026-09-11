using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

/// <summary>
/// GET /api/learner/course — returns the current course arc for the
/// authenticated learner. iOS Home consumes this to render the "Your
/// German course: lesson 4 of 27" hero row + scrollable lesson list.
/// </summary>
public sealed class LearnerCourseEndpoint(ILearnerStateRepository repository)
{
    public async Task<ApiResponse<LearnerCourseHttpResponse>> GetAsync(
        AppSessionPrincipal? principal,
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

        var state = await repository.GetAsync(principal.TenantId, principal.UserId, cancellationToken);
        if (state is null)
        {
            return ApiResponse<LearnerCourseHttpResponse>.Failure(
                404,
                new ApiErrorResponse(
                    "learner_state_not_found",
                    "This learner has no state. Complete onboarding first.",
                    requestCorrelationId.Value,
                    Retryable: false));
        }

        return ApiResponse<LearnerCourseHttpResponse>.Ok(
            LearnerCourseHttpResponse.FromPlan(state.ActivePlan, requestCorrelationId.Value));
    }
}
