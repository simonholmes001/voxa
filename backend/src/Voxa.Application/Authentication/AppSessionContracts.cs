using Voxa.Domain.Learners;

namespace Voxa.Application.Authentication;

public interface IAppSessionService
{
    Task<AppSessionTokenPair> SignInWithAppleAsync(
        SignInWithAppleCommand command,
        CancellationToken cancellationToken);

    Task<AppSessionTokenPair> RefreshAsync(
        RefreshAppSessionCommand command,
        CancellationToken cancellationToken);

    Task RevokeRefreshTokenAsync(
        LogoutAppSessionCommand command,
        CancellationToken cancellationToken);
}

public interface IAppleIdentityVerifier
{
    Task<VerifiedAppleIdentity> VerifyAsync(
        string identityToken,
        string authorizationCode,
        string nonce,
        CancellationToken cancellationToken);
}

public interface IAppSessionTokenIssuer
{
    AppSessionTokenPair IssueTokenPair(
        VerifiedAppSessionSubject subject,
        CorrelationId correlationId);
}

public interface IAppSessionTokenValidator
{
    AppSessionPrincipal? ValidateAccessToken(string? accessToken, DateTimeOffset utcNow);
}

public interface IRefreshSessionStore
{
    Task StoreAsync(
        string refreshToken,
        VerifiedAppSessionSubject subject,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken);

    Task<VerifiedAppSessionSubject?> GetAsync(
        string refreshToken,
        CancellationToken cancellationToken);

    Task RevokeAsync(
        string refreshToken,
        CancellationToken cancellationToken);
}

public sealed record SignInWithAppleCommand(
    string IdentityToken,
    string AuthorizationCode,
    string Nonce,
    CorrelationId CorrelationId)
{
    public static SignInWithAppleCommand Create(
        string? identityToken,
        string? authorizationCode,
        string? nonce,
        CorrelationId correlationId)
    {
        return new SignInWithAppleCommand(
            Required(identityToken, nameof(identityToken)),
            Required(authorizationCode, nameof(authorizationCode)),
            Required(nonce, nameof(nonce)),
            correlationId);
    }

    private static string Required(string? value, string name)
    {
        return string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException($"{name} is required.", name)
            : value.Trim();
    }
}

public sealed record RefreshAppSessionCommand(
    string RefreshToken,
    CorrelationId CorrelationId)
{
    public static RefreshAppSessionCommand Create(string? refreshToken, CorrelationId correlationId)
    {
        return new RefreshAppSessionCommand(
            string.IsNullOrWhiteSpace(refreshToken)
                ? throw new ArgumentException("refreshToken is required.", nameof(refreshToken))
                : refreshToken.Trim(),
            correlationId);
    }
}

public sealed record LogoutAppSessionCommand(
    string RefreshToken,
    CorrelationId CorrelationId)
{
    public static LogoutAppSessionCommand Create(string? refreshToken, CorrelationId correlationId)
    {
        return new LogoutAppSessionCommand(
            string.IsNullOrWhiteSpace(refreshToken)
                ? throw new ArgumentException("refreshToken is required.", nameof(refreshToken))
                : refreshToken.Trim(),
            correlationId);
    }
}

public sealed record AppSessionTokenPair(
    string CorrelationId,
    string TenantId,
    string UserId,
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    DateTimeOffset RefreshTokenExpiresAt);

public sealed record AppSessionPrincipal(TenantId TenantId, UserId UserId);

public sealed record VerifiedAppleIdentity(
    string TenantId,
    string UserId);

public sealed record VerifiedAppSessionSubject(
    TenantId TenantId,
    UserId UserId)
{
    public static VerifiedAppSessionSubject FromAppleIdentity(VerifiedAppleIdentity identity)
    {
        return new VerifiedAppSessionSubject(
            TenantId.Create(identity.TenantId),
            UserId.Create(identity.UserId));
    }
}

public sealed class AppleIdentityVerificationException(string message) : Exception(message);

public sealed class AppSessionRefreshException(string message) : Exception(message);
