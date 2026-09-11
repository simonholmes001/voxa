using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

/// <summary>
/// GET /api/learner/plan — returns today's plan for the authenticated
/// learner, generated from their accumulated evidence via the
/// CurriculumModel. iOS Home + Practice Today card consumes this to show
/// a recommendation like "Continue past tense — you missed *aller* in
/// the last two sessions" instead of the rule-based fallback that C1 and
/// earlier shipped with.
/// </summary>
public sealed class LearnerPlanEndpoint(ILearnerPlanService learnerPlan)
{
    public async Task<ApiResponse<LearnerPlanHttpResponse>> GetAsync(
        AppSessionPrincipal? principal,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        if (principal is null)
        {
            return ApiResponse<LearnerPlanHttpResponse>.Failure(
                401,
                new ApiErrorResponse(
                    "app_session_required",
                    "An authenticated app session is required.",
                    requestCorrelationId.Value,
                    Retryable: false));
        }

        try
        {
            var plan = await learnerPlan.GetTodayPlanAsync(
                principal.TenantId,
                principal.UserId,
                requestCorrelationId,
                cancellationToken);
            return ApiResponse<LearnerPlanHttpResponse>.Ok(
                LearnerPlanHttpResponse.FromPlan(plan));
        }
        catch (LearnerPlanException)
        {
            return ApiResponse<LearnerPlanHttpResponse>.Failure(
                503,
                new ApiErrorResponse(
                    "learner_plan_unavailable",
                    "Learner plan could not be generated.",
                    requestCorrelationId.Value,
                    Retryable: true));
        }
    }
}

public sealed record LearnerPlanHttpResponse(
    string CorrelationId,
    RecommendedSessionDto RecommendedSession,
    IReadOnlyList<string> FocusAreas)
{
    public static LearnerPlanHttpResponse FromPlan(LearnerPlan plan)
    {
        return new LearnerPlanHttpResponse(
            plan.CorrelationId,
            new RecommendedSessionDto(
                plan.RecommendedSession.ActivityIntent,
                plan.RecommendedSession.FocusTitle,
                plan.RecommendedSession.Reason),
            plan.FocusAreas);
    }
}

public sealed record RecommendedSessionDto(
    string ActivityIntent,
    string FocusTitle,
    string Reason);
