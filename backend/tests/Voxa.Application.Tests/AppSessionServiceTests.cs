using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class AppSessionServiceTests
{
    [Fact]
    public async Task SignInWithAppleVerifiesIdentityAndStoresRefreshSession()
    {
        var apple = new StubAppleIdentityVerifier();
        var tokens = new StubAppSessionTokenIssuer();
        var store = new RecordingRefreshSessionStore();
        var service = new AppSessionService(apple, tokens, store);

        var tokenPair = await service.SignInWithAppleAsync(
            SignInWithAppleCommand.Create("identity-token", "authorization-code", "nonce-123", CorrelationId.Create("corr-123")),
            CancellationToken.None);

        Assert.Equal("identity-token", apple.VerifiedIdentityToken);
        Assert.Equal("authorization-code", apple.VerifiedAuthorizationCode);
        Assert.Equal("nonce-123", apple.VerifiedNonce);
        Assert.Equal("access-user-subject-1", tokenPair.AccessToken);
        Assert.Equal("refresh-user-subject-1", tokenPair.RefreshToken);
        Assert.True(store.Contains("refresh-user-subject-1"));
        Assert.Equal(DateTimeOffset.Parse("2026-09-28T08:15:00Z"), store.ExpiresAt("refresh-user-subject-1"));
    }

    [Fact]
    public async Task SignInWithAppleRejectsInvalidIdentity()
    {
        var apple = new StubAppleIdentityVerifier { Reject = true };
        var service = new AppSessionService(apple, new StubAppSessionTokenIssuer(), new RecordingRefreshSessionStore());

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            service.SignInWithAppleAsync(
                SignInWithAppleCommand.Create("bad-token", "authorization-code", "nonce-123", CorrelationId.Create("corr-123")),
                CancellationToken.None));
    }

    [Fact]
    public async Task RefreshRotatesRefreshTokenAndRevokesPreviousToken()
    {
        var apple = new StubAppleIdentityVerifier();
        var tokens = new StubAppSessionTokenIssuer();
        var store = new RecordingRefreshSessionStore();
        var service = new AppSessionService(apple, tokens, store);
        var original = await service.SignInWithAppleAsync(
            SignInWithAppleCommand.Create("identity-token", "authorization-code", "nonce-123", CorrelationId.Create("corr-123")),
            CancellationToken.None);

        var refreshed = await service.RefreshAsync(
            RefreshAppSessionCommand.Create(original.RefreshToken, CorrelationId.Create("corr-456")),
            CancellationToken.None);

        Assert.Equal("corr-456", refreshed.CorrelationId);
        Assert.Equal("access-user-subject-2", refreshed.AccessToken);
        Assert.Equal("refresh-user-subject-2", refreshed.RefreshToken);
        Assert.False(store.Contains(original.RefreshToken));
        Assert.True(store.Contains(refreshed.RefreshToken));
    }

    [Fact]
    public async Task RefreshRejectsUnknownRefreshToken()
    {
        var service = new AppSessionService(
            new StubAppleIdentityVerifier(),
            new StubAppSessionTokenIssuer(),
            new RecordingRefreshSessionStore());

        await Assert.ThrowsAsync<AppSessionRefreshException>(() =>
            service.RefreshAsync(
                RefreshAppSessionCommand.Create("missing-token", CorrelationId.Create("corr-456")),
                CancellationToken.None));
    }

    [Fact]
    public async Task RevokeRefreshTokenRemovesStoredSession()
    {
        var service = new AppSessionService(
            new StubAppleIdentityVerifier(),
            new StubAppSessionTokenIssuer(),
            new RecordingRefreshSessionStore());
        var original = await service.SignInWithAppleAsync(
            SignInWithAppleCommand.Create("identity-token", "authorization-code", "nonce-123", CorrelationId.Create("corr-123")),
            CancellationToken.None);

        await service.RevokeRefreshTokenAsync(
            LogoutAppSessionCommand.Create(original.RefreshToken, CorrelationId.Create("corr-789")),
            CancellationToken.None);

        await Assert.ThrowsAsync<AppSessionRefreshException>(() =>
            service.RefreshAsync(
                RefreshAppSessionCommand.Create(original.RefreshToken, CorrelationId.Create("corr-456")),
                CancellationToken.None));
    }

    private sealed class StubAppleIdentityVerifier : IAppleIdentityVerifier
    {
        public bool Reject { get; init; }

        public string? VerifiedIdentityToken { get; private set; }

        public string? VerifiedAuthorizationCode { get; private set; }

        public string? VerifiedNonce { get; private set; }

        public Task<VerifiedAppleIdentity> VerifyAsync(
            string identityToken,
            string authorizationCode,
            string nonce,
            CancellationToken cancellationToken)
        {
            if (Reject)
            {
                throw new AppleIdentityVerificationException("Invalid Apple identity.");
            }

            VerifiedIdentityToken = identityToken;
            VerifiedAuthorizationCode = authorizationCode;
            VerifiedNonce = nonce;
            return Task.FromResult(new VerifiedAppleIdentity("tenant-default", "user-subject"));
        }
    }

    private sealed class StubAppSessionTokenIssuer : IAppSessionTokenIssuer
    {
        private int issueCount;

        public AppSessionTokenPair IssueTokenPair(
            VerifiedAppSessionSubject subject,
            CorrelationId correlationId)
        {
            issueCount += 1;
            return new AppSessionTokenPair(
                correlationId.Value,
                subject.TenantId.Value,
                subject.UserId.Value,
                $"access-{subject.UserId.Value}-{issueCount}",
                $"refresh-{subject.UserId.Value}-{issueCount}",
                DateTimeOffset.Parse("2026-08-29T08:15:00Z").AddHours(issueCount),
                DateTimeOffset.Parse("2026-09-28T08:15:00Z").AddHours(issueCount - 1));
        }
    }

    private sealed class RecordingRefreshSessionStore : IRefreshSessionStore
    {
        private readonly Dictionary<string, (VerifiedAppSessionSubject Subject, DateTimeOffset ExpiresAt)> sessions = new();

        public Task StoreAsync(
            string refreshToken,
            VerifiedAppSessionSubject subject,
            DateTimeOffset expiresAt,
            CancellationToken cancellationToken)
        {
            sessions[refreshToken] = (subject, expiresAt);
            return Task.CompletedTask;
        }

        public Task<VerifiedAppSessionSubject?> GetAsync(string refreshToken, CancellationToken cancellationToken)
        {
            return Task.FromResult(
                sessions.TryGetValue(refreshToken, out var session)
                    ? session.Subject
                    : null);
        }

        public Task RevokeAsync(string refreshToken, CancellationToken cancellationToken)
        {
            sessions.Remove(refreshToken);
            return Task.CompletedTask;
        }

        public bool Contains(string refreshToken) => sessions.ContainsKey(refreshToken);

        public DateTimeOffset? ExpiresAt(string refreshToken)
        {
            return sessions.TryGetValue(refreshToken, out var session)
                ? session.ExpiresAt
                : null;
        }
    }
}
