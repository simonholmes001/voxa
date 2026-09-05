using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class LanguageProfilesEndpoint(LanguageProfileService profiles)
{
    public Task<ApiResponse<LanguageProfilesResponse>> GetAsync(
        TenantId tenantId,
        UserId userId,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        return GetCoreAsync(tenantId, userId, CorrelationId.Create(correlationId), cancellationToken);
    }

    public async Task<ApiResponse<SelectLanguageProfileResponse>> SelectAsync(
        string? targetLanguage,
        TenantId tenantId,
        UserId userId,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);
        if (string.IsNullOrWhiteSpace(targetLanguage))
        {
            return Failure<SelectLanguageProfileResponse>(
                "validation_error",
                "languageKey is required.",
                requestCorrelationId,
                400);
        }

        try
        {
            return ApiResponse<SelectLanguageProfileResponse>.Ok(await profiles.SelectAsync(
                tenantId,
                userId,
                targetLanguage,
                requestCorrelationId,
                cancellationToken));
        }
        catch (LearnerStateNotFoundException)
        {
            return Failure<SelectLanguageProfileResponse>(
                "language_profile_not_found",
                "The requested language profile does not exist.",
                requestCorrelationId,
                404);
        }
    }

    private async Task<ApiResponse<LanguageProfilesResponse>> GetCoreAsync(
        TenantId tenantId,
        UserId userId,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        return ApiResponse<LanguageProfilesResponse>.Ok(await profiles.ListAsync(
            tenantId,
            userId,
            correlationId,
            cancellationToken));
    }

    private static ApiResponse<T> Failure<T>(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode) =>
        ApiResponse<T>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, false));
}
