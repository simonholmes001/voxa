using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class DevResetEndpoint(
    ILearnerStateRepository learnerStates,
    bool enabled)
{
    public async Task<ApiResponse<DevResetResponse>> DeleteAsync(
        AppSessionPrincipal? principal,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var resolvedCorrelationId = CorrelationId.Create(correlationId);

        if (!enabled)
        {
            return ApiResponse<DevResetResponse>.Failure(
                404,
                new ApiErrorResponse(
                    "dev_reset_unavailable",
                    "Developer reset is not enabled for this environment.",
                    resolvedCorrelationId.Value,
                    false));
        }

        if (principal is null)
        {
            return ApiResponse<DevResetResponse>.Failure(
                401,
                new ApiErrorResponse(
                    "app_session_required",
                    "An authenticated app session is required.",
                    resolvedCorrelationId.Value,
                    false));
        }

        await learnerStates.DeleteAsync(principal.TenantId, principal.UserId, cancellationToken);

        return ApiResponse<DevResetResponse>.Ok(new DevResetResponse(
            resolvedCorrelationId.Value,
            true));
    }
}

public sealed record DevResetResponse(
    string CorrelationId,
    bool Deleted);
