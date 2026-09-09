using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

/// <summary>
/// Reads the learner's accumulated evidence (active plan, current lesson,
/// due reviews, recent debriefs) and returns today's plan via the
/// CurriculumModel. Consumed by iOS Home + Practice Today card.
/// </summary>
public interface ILearnerPlanService
{
    Task<LearnerPlan> GetTodayPlanAsync(
        TenantId tenantId,
        UserId userId,
        CorrelationId correlationId,
        CancellationToken cancellationToken);
}

public sealed record LearnerPlan(
    string CorrelationId,
    RecommendedSession RecommendedSession,
    IReadOnlyList<string> FocusAreas);

public sealed record RecommendedSession(
    string ActivityIntent,
    string FocusTitle,
    string Reason);

/// <summary>
/// Non-fatal exception thrown when the planner can't produce a plan
/// (upstream call failed, response didn't parse, or the model is
/// unavailable). The endpoint maps this to a retriable 503.
/// </summary>
public sealed class LearnerPlanException(string message) : Exception(message);
