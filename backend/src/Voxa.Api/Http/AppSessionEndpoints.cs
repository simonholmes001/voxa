using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class SignInWithAppleEndpoint(IAppSessionService appSessions)
{
    public async Task<ApiResponse<AppSessionHttpResponse>> PostAsync(
        SignInWithAppleHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        try
        {
            var command = SignInWithAppleCommand.Create(
                request.IdentityToken,
                request.AuthorizationCode,
                request.Nonce,
                requestCorrelationId);
            var tokenPair = await appSessions.SignInWithAppleAsync(command, cancellationToken);
            return ApiResponse<AppSessionHttpResponse>.Ok(AppSessionHttpResponse.FromTokenPair(tokenPair));
        }
        catch (ArgumentException exception)
        {
            return Failure<AppSessionHttpResponse>("validation_error", exception.Message, requestCorrelationId, 400, retryable: false);
        }
        catch (AppleIdentityVerificationException)
        {
            return Failure<AppSessionHttpResponse>(
                "apple_identity_invalid",
                "Apple identity could not be verified.",
                requestCorrelationId,
                401,
                retryable: false);
        }
    }

    private static ApiResponse<T> Failure<T>(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode,
        bool retryable)
    {
        return ApiResponse<T>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, retryable));
    }
}

public sealed class RefreshAppSessionEndpoint(IAppSessionService appSessions)
{
    public async Task<ApiResponse<AppSessionHttpResponse>> PostAsync(
        RefreshAppSessionHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        try
        {
            var tokenPair = await appSessions.RefreshAsync(
                RefreshAppSessionCommand.Create(request.RefreshToken, requestCorrelationId),
                cancellationToken);
            return ApiResponse<AppSessionHttpResponse>.Ok(AppSessionHttpResponse.FromTokenPair(tokenPair));
        }
        catch (ArgumentException exception)
        {
            return Failure<AppSessionHttpResponse>("validation_error", exception.Message, requestCorrelationId, 400, retryable: false);
        }
        catch (AppSessionRefreshException)
        {
            return Failure<AppSessionHttpResponse>(
                "session_refresh_invalid",
                "Refresh token is invalid or expired.",
                requestCorrelationId,
                401,
                retryable: false);
        }
    }

    private static ApiResponse<T> Failure<T>(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode,
        bool retryable)
    {
        return ApiResponse<T>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, retryable));
    }
}

public sealed class LogoutAppSessionEndpoint(IAppSessionService appSessions)
{
    public async Task<ApiResponse<LogoutAppSessionHttpResponse>> PostAsync(
        LogoutAppSessionHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        try
        {
            await appSessions.RevokeRefreshTokenAsync(
                LogoutAppSessionCommand.Create(request.RefreshToken, requestCorrelationId),
                cancellationToken);
            return ApiResponse<LogoutAppSessionHttpResponse>.Ok(new LogoutAppSessionHttpResponse(requestCorrelationId.Value, true));
        }
        catch (ArgumentException exception)
        {
            return ApiResponse<LogoutAppSessionHttpResponse>.Failure(
                400,
                new ApiErrorResponse("validation_error", exception.Message, requestCorrelationId.Value, false));
        }
    }
}

public sealed record SignInWithAppleHttpRequest(
    string? IdentityToken,
    string? AuthorizationCode,
    string? Nonce);

public sealed record RefreshAppSessionHttpRequest(string? RefreshToken);

public sealed record LogoutAppSessionHttpRequest(string? RefreshToken);

public sealed record AppSessionHttpResponse(
    string CorrelationId,
    string TenantId,
    string UserId,
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    DateTimeOffset RefreshTokenExpiresAt)
{
    public static AppSessionHttpResponse FromTokenPair(AppSessionTokenPair tokenPair)
    {
        return new AppSessionHttpResponse(
            tokenPair.CorrelationId,
            tokenPair.TenantId,
            tokenPair.UserId,
            tokenPair.AccessToken,
            tokenPair.RefreshToken,
            tokenPair.ExpiresAt,
            tokenPair.RefreshTokenExpiresAt);
    }
}

public sealed record LogoutAppSessionHttpResponse(
    string CorrelationId,
    bool Revoked);
