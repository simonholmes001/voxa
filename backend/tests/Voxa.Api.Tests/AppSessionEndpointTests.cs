using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class AppSessionEndpointTests
{
    [Fact]
    public async Task SignInWithAppleReturnsAppSessionWithoutProviderTokenDetails()
    {
        var endpoint = new SignInWithAppleEndpoint(new StubAppSessionService());

        var response = await endpoint.PostAsync(
            new SignInWithAppleHttpRequest("apple-id-token", "authorization-code", "nonce-123"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.NotNull(response.Body);
        Assert.Equal("corr-123", response.Body.CorrelationId);
        Assert.Equal("app-access-token", response.Body.AccessToken);
        Assert.Equal("app-refresh-token", response.Body.RefreshToken);
        Assert.Equal(DateTimeOffset.Parse("2026-09-28T08:15:00Z"), response.Body.RefreshTokenExpiresAt);
        Assert.DoesNotContain("apple-id-token", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("authorization-code", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("nonce-123", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task SignInWithAppleReturnsUnauthorizedWhenIdentityCannotBeVerified()
    {
        var endpoint = new SignInWithAppleEndpoint(new StubAppSessionService { RejectAppleIdentity = true });

        var response = await endpoint.PostAsync(
            new SignInWithAppleHttpRequest("bad-token", "authorization-code", "nonce-123"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("apple_identity_invalid", response.Error?.Code);
        Assert.Equal("corr-123", response.Error?.CorrelationId);
    }

    [Fact]
    public async Task RefreshReturnsNewTokenPairForValidRefreshToken()
    {
        var endpoint = new RefreshAppSessionEndpoint(new StubAppSessionService());

        var response = await endpoint.PostAsync(
            new RefreshAppSessionHttpRequest("app-refresh-token"),
            "corr-456",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.NotNull(response.Body);
        Assert.Equal("app-access-token-refreshed", response.Body.AccessToken);
        Assert.Equal("app-refresh-token-rotated", response.Body.RefreshToken);
    }

    [Fact]
    public async Task LogoutRevokesRefreshToken()
    {
        var service = new StubAppSessionService();
        var endpoint = new LogoutAppSessionEndpoint(service);

        var response = await endpoint.PostAsync(
            new LogoutAppSessionHttpRequest("app-refresh-token"),
            "corr-789",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.True(response.Body?.Revoked);
        Assert.Equal("app-refresh-token", service.RevokedRefreshToken);
    }

    private sealed class StubAppSessionService : IAppSessionService
    {
        public bool RejectAppleIdentity { get; init; }

        public string? RevokedRefreshToken { get; private set; }

        public Task<AppSessionTokenPair> SignInWithAppleAsync(
            SignInWithAppleCommand command,
            CancellationToken cancellationToken)
        {
            if (RejectAppleIdentity)
            {
                throw new AppleIdentityVerificationException("Apple identity could not be verified.");
            }

            return Task.FromResult(new AppSessionTokenPair(
                "corr-123",
                "tenant-default",
                "user-apple-subject",
                "app-access-token",
                "app-refresh-token",
                DateTimeOffset.Parse("2026-08-29T08:15:00Z"),
                DateTimeOffset.Parse("2026-09-28T08:15:00Z")));
        }

        public Task<AppSessionTokenPair> RefreshAsync(
            RefreshAppSessionCommand command,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new AppSessionTokenPair(
                command.CorrelationId.Value,
                "tenant-default",
                "user-apple-subject",
                "app-access-token-refreshed",
                "app-refresh-token-rotated",
                DateTimeOffset.Parse("2026-08-29T09:15:00Z"),
                DateTimeOffset.Parse("2026-09-28T09:15:00Z")));
        }

        public Task RevokeRefreshTokenAsync(
            LogoutAppSessionCommand command,
            CancellationToken cancellationToken)
        {
            RevokedRefreshToken = command.RefreshToken;
            return Task.CompletedTask;
        }
    }
}
