using Voxa.Application.Realtime;
using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class RealtimeSessionEndpoint(IRealtimeSessionService realtimeSessions)
{
    public async Task<ApiResponse<RealtimeSessionHttpResponse>> PostAsync(
        AppSessionPrincipal? principal,
        RealtimeSessionHttpRequest request,
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
            var command = RealtimeSessionCommand.Create(
                principal.TenantId.Value,
                principal.UserId.Value,
                request.CoachingMode,
                request.ProficiencyBand,
                request.TargetLanguage,
                requestCorrelationId);
            var credential = await realtimeSessions.IssueClientSecretAsync(command, cancellationToken);
            return ApiResponse<RealtimeSessionHttpResponse>.Ok(RealtimeSessionHttpResponse.FromCredential(credential));
        }
        catch (ArgumentException exception)
        {
            return Failure("validation_error", exception.Message, requestCorrelationId, 400, retryable: false);
        }
        catch (RealtimeSessionIssueException)
        {
            return Failure(
                "realtime_session_unavailable",
                "Realtime session credentials could not be issued.",
                requestCorrelationId,
                503,
                retryable: true);
        }
    }

    private static ApiResponse<RealtimeSessionHttpResponse> Failure(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode,
        bool retryable)
    {
        return ApiResponse<RealtimeSessionHttpResponse>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, retryable));
    }
}

public sealed record RealtimeSessionHttpRequest(
    string? CoachingMode,
    string? ProficiencyBand,
    string? TargetLanguage);

public sealed record RealtimeSessionHttpResponse(
    string CorrelationId,
    string ClientSecret,
    string Model,
    string ReasoningEffort,
    DateTimeOffset ExpiresAt,
    RealtimeSessionSettingsContract Settings)
{
    public static RealtimeSessionHttpResponse FromCredential(RealtimeSessionCredential credential)
    {
        return new RealtimeSessionHttpResponse(
            credential.CorrelationId,
            credential.ClientSecret,
            credential.Model,
            credential.ReasoningEffort,
            credential.ExpiresAt,
            credential.Settings);
    }
}
