using Voxa.Application.Authentication;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;

namespace Voxa.Infrastructure.Tests;

public sealed class HmacAppSessionTokenIssuerTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-08-30T08:00:00Z");

    [Fact]
    public void IssueTokenPairCreatesAccessTokenThatValidatesToTheSameSubject()
    {
        var issuer = new HmacAppSessionTokenIssuer(CreateOptions(), new FixedClock(Now));
        var subject = new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-apple-subject"));

        var pair = issuer.IssueTokenPair(subject, CorrelationId.Create("corr-123"));
        var principal = issuer.ValidateAccessToken(pair.AccessToken, Now.AddMinutes(5));

        Assert.NotNull(principal);
        Assert.Equal("corr-123", pair.CorrelationId);
        Assert.Equal("tenant-default", pair.TenantId);
        Assert.Equal("user-apple-subject", pair.UserId);
        Assert.Equal(subject.TenantId, principal.TenantId);
        Assert.Equal(subject.UserId, principal.UserId);
        Assert.Equal(Now.AddMinutes(15), pair.ExpiresAt);
        Assert.Equal(Now.AddDays(30), pair.RefreshTokenExpiresAt);
    }

    [Fact]
    public void ValidateAccessTokenRejectsExpiredTokens()
    {
        var issuer = new HmacAppSessionTokenIssuer(CreateOptions(), new FixedClock(Now));
        var pair = issuer.IssueTokenPair(
            new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-a")),
            CorrelationId.Create("corr-123"));

        var principal = issuer.ValidateAccessToken(pair.AccessToken, Now.AddMinutes(16));

        Assert.Null(principal);
    }

    [Fact]
    public void ValidateAccessTokenRejectsTamperedTokens()
    {
        var issuer = new HmacAppSessionTokenIssuer(CreateOptions(), new FixedClock(Now));
        var pair = issuer.IssueTokenPair(
            new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-a")),
            CorrelationId.Create("corr-123"));
        var tampered = pair.AccessToken.Replace('a', 'b');

        var principal = issuer.ValidateAccessToken(tampered, Now.AddMinutes(5));

        Assert.Null(principal);
    }

    private static AppSessionTokenOptions CreateOptions()
    {
        return new AppSessionTokenOptions(
            SigningKey: "test-signing-key-that-is-long-enough-for-hmac",
            AccessTokenLifetime: TimeSpan.FromMinutes(15),
            RefreshTokenLifetime: TimeSpan.FromDays(30));
    }

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
