using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

public sealed class LearnerSessionService(ILearnerStateRepository repository) : ILearnerSessionQueries
{
    public async Task<ResumeCheckpointResponse> GetResumeCheckpointAsync(
        ResumeCheckpointQuery query,
        CancellationToken cancellationToken)
    {
        var state = await repository.GetAsync(query.TenantId, query.UserId, cancellationToken);
        if (state is null)
        {
            throw new LearnerStateNotFoundException(query.TenantId, query.UserId);
        }

        return state.ToResumeCheckpoint(query.CorrelationId);
    }

    public Task<LearnerState> SaveLearnerStateAsync(
        LearnerState state,
        LearnerStateVersion? expectedVersion,
        CancellationToken cancellationToken)
    {
        return repository.SaveAsync(state, expectedVersion, cancellationToken);
    }
}

internal static class LearnerStateContractMapping
{
    public static ResumeCheckpointResponse ToResumeCheckpoint(this LearnerState state, CorrelationId correlationId)
    {
        return new ResumeCheckpointResponse(
            correlationId.Value,
            state.Version.Value,
            new LearnerProfileContract(
                state.Profile.TargetLanguage,
                state.Profile.NativeLanguage,
                state.Profile.ProficiencyLevel),
            new ActiveLearningPlanContract(
                state.ActivePlan.PlanId,
                state.ActivePlan.Title,
                state.ActivePlan.KnowledgeUnitIds),
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
                .ToArray());
    }
}
