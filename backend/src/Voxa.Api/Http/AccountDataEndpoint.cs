using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class AccountDataEndpoint(IAccountDataService accountData)
{
    public async Task<ApiResponse<AccountDataExport>> ExportAsync(
        AppSessionPrincipal? principal,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);
        if (principal is null)
        {
            return Unauthorized<AccountDataExport>(requestCorrelationId);
        }

        return ApiResponse<AccountDataExport>.Ok(await accountData.ExportAsync(
            principal,
            requestCorrelationId,
            cancellationToken));
    }

    public async Task<ApiResponse<AccountDeletionResult>> DeleteAsync(
        AppSessionPrincipal? principal,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);
        if (principal is null)
        {
            return Unauthorized<AccountDeletionResult>(requestCorrelationId);
        }

        return ApiResponse<AccountDeletionResult>.Ok(await accountData.DeleteAsync(
            principal,
            requestCorrelationId,
            cancellationToken));
    }

    private static ApiResponse<T> Unauthorized<T>(CorrelationId correlationId)
    {
        return ApiResponse<T>.Failure(
            401,
            new ApiErrorResponse(
                "app_session_required",
                "An authenticated app session is required.",
                correlationId.Value,
                false));
    }
}
