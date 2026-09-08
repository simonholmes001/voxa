using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class LearningSessionCompletionEndpoint(ILearningSessionCompletionService sessions)
{
    public async Task<ApiResponse<ResumeCheckpointResponse>> PostAsync(
        AppSessionPrincipal? principal,
        LearningSessionCompletionHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);
        if (principal is null)
        {
            return Failure(
                "app_session_required",
                "An authenticated app session is required.",
                requestCorrelationId,
                401,
                retryable: false);
        }

        try
        {
            var command = CompleteLearningSessionCommand.Create(
                principal.TenantId.Value,
                principal.UserId.Value,
                request.SessionId,
                request.LessonId,
                request.KnowledgeUnitId,
                request.DurationSeconds,
                request.SessionIntent,
                requestCorrelationId.Value);
            var checkpoint = await sessions.CompleteAsync(command, cancellationToken);
            return ApiResponse<ResumeCheckpointResponse>.Ok(checkpoint);
        }
        catch (ArgumentException exception)
        {
            return Failure("validation_error", exception.Message, requestCorrelationId, 400, retryable: false);
        }
        catch (LearnerStateNotFoundException)
        {
            return Failure("learner_state_not_found", "Learner state was not found.", requestCorrelationId, 404, retryable: false);
        }
        catch (StaleLearnerStateVersionException)
        {
            return Failure(
                "learner_state_conflict",
                "Learner state changed while the session was being completed. Please retry.",
                requestCorrelationId,
                409,
                retryable: true);
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

public sealed record LearningSessionCompletionHttpRequest(
    string? SessionId,
    int? DurationSeconds,
    string? SessionIntent = null,
    string? LessonId = null,
    string? KnowledgeUnitId = null);
