using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class ResumeSessionEndpoint(ILearnerSessionQueries learnerSessions)
{
    public async Task<ApiResponse<ResumeCheckpointResponse>> GetAsync(
        string? tenantId,
        string? userId,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        try
        {
            var query = new ResumeCheckpointQuery(
                TenantId.Create(tenantId ?? ""),
                UserId.Create(userId ?? ""),
                requestCorrelationId);
            var checkpoint = await learnerSessions.GetResumeCheckpointAsync(query, cancellationToken);
            return ApiResponse<ResumeCheckpointResponse>.Ok(checkpoint);
        }
        catch (ArgumentException exception)
        {
            return Failure("validation_error", exception.Message, requestCorrelationId, 400, retryable: false);
        }
        catch (LearnerStateNotFoundException)
        {
            return Failure(
                "resume_checkpoint_not_found",
                "No resume checkpoint exists for the current learner.",
                requestCorrelationId,
                404,
                retryable: false);
        }
    }

    private static ApiResponse<ResumeCheckpointResponse> Failure(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode,
        bool retryable)
    {
        return ApiResponse<ResumeCheckpointResponse>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, retryable));
    }
}
