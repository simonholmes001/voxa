namespace Voxa.Application.Authentication;

public sealed class AppSessionService(
    IAppleIdentityVerifier appleIdentityVerifier,
    IAppSessionTokenIssuer tokenIssuer,
    IRefreshSessionStore refreshSessions) : IAppSessionService
{
    public async Task<AppSessionTokenPair> SignInWithAppleAsync(
        SignInWithAppleCommand command,
        CancellationToken cancellationToken)
    {
        var identity = await appleIdentityVerifier.VerifyAsync(
            command.IdentityToken,
            command.AuthorizationCode,
            command.Nonce,
            cancellationToken);
        var subject = VerifiedAppSessionSubject.FromAppleIdentity(identity);
        return await IssueAndStoreAsync(subject, command.CorrelationId, cancellationToken);
    }

    public async Task<AppSessionTokenPair> RefreshAsync(
        RefreshAppSessionCommand command,
        CancellationToken cancellationToken)
    {
        var subject = await refreshSessions.GetAsync(command.RefreshToken, cancellationToken);
        if (subject is null)
        {
            throw new AppSessionRefreshException("Refresh token is invalid or expired.");
        }

        await refreshSessions.RevokeAsync(command.RefreshToken, cancellationToken);
        return await IssueAndStoreAsync(subject, command.CorrelationId, cancellationToken);
    }

    public Task RevokeRefreshTokenAsync(
        LogoutAppSessionCommand command,
        CancellationToken cancellationToken)
    {
        return refreshSessions.RevokeAsync(command.RefreshToken, cancellationToken);
    }

    private async Task<AppSessionTokenPair> IssueAndStoreAsync(
        VerifiedAppSessionSubject subject,
        Domain.Learners.CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var tokenPair = tokenIssuer.IssueTokenPair(subject, correlationId);
        await refreshSessions.StoreAsync(
            tokenPair.RefreshToken,
            subject,
            tokenPair.RefreshTokenExpiresAt,
            cancellationToken);
        return tokenPair;
    }
}
