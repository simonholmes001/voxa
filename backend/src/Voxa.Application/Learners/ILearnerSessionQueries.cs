namespace Voxa.Application.Learners;

public interface ILearnerSessionQueries
{
    Task<ResumeCheckpointResponse> GetResumeCheckpointAsync(
        ResumeCheckpointQuery query,
        CancellationToken cancellationToken);
}
