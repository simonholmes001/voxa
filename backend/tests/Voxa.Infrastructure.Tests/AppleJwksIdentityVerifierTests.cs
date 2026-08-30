using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Voxa.Application.Authentication;
using Voxa.Infrastructure.Authentication;

namespace Voxa.Infrastructure.Tests;

public sealed class AppleJwksIdentityVerifierTests
{
    [Fact]
    public async Task VerifyAcceptsAppleJwtSignedByMatchingJwksKey()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();

        var identity = await verifier.VerifyAsync(
            fixture.CreateToken(audience: "com.voxa.ios", nonce: "nonce-123"),
            "authorization-code",
            "nonce-123",
            CancellationToken.None);

        Assert.Equal("tenant-default", identity.TenantId);
        Assert.Equal("apple-user-123", identity.UserId);
    }

    [Fact]
    public async Task VerifyRejectsWrongAudience()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateToken(audience: "wrong-client", nonce: "nonce-123"),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsWrongNonce()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateToken(audience: "com.voxa.ios", nonce: "nonce-123"),
                "authorization-code",
                "different-nonce",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsTamperedSignature()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();
        var token = fixture.CreateToken(audience: "com.voxa.ios", nonce: "nonce-123");

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                $"{token[..^1]}x",
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    private sealed class AppleJwtFixture : IDisposable
    {
        private const string KeyId = "apple-key-1";
        private readonly RSA rsa;
        private readonly RSAParameters publicKey;

        private AppleJwtFixture(RSA rsa)
        {
            this.rsa = rsa;
            publicKey = rsa.ExportParameters(false);
        }

        public static AppleJwtFixture Create()
        {
            return new AppleJwtFixture(RSA.Create(2048));
        }

        public AppleJwksIdentityVerifier CreateVerifier()
        {
            var jwks = JsonSerializer.Serialize(new
            {
                keys = new[]
                {
                    new
                    {
                        kty = "RSA",
                        kid = KeyId,
                        use = "sig",
                        alg = "RS256",
                        n = Base64UrlEncode(publicKey.Modulus!),
                        e = Base64UrlEncode(publicKey.Exponent!)
                    }
                }
            });

            return new AppleJwksIdentityVerifier(
                new HttpClient(new StaticJsonHandler(jwks)),
                new AppleJwksIdentityVerifierOptions(
                    "com.voxa.ios",
                    "tenant-default",
                    new Uri("https://appleid.apple.com/auth/keys")),
                new FixedClock(DateTimeOffset.Parse("2026-08-30T09:00:00Z")));
        }

        public string CreateToken(string audience, string nonce)
        {
            var header = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
            {
                alg = "RS256",
                kid = KeyId,
                typ = "JWT"
            }));
            var payload = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
            {
                iss = "https://appleid.apple.com",
                aud = audience,
                sub = "apple-user-123",
                nonce,
                exp = DateTimeOffset.Parse("2026-08-30T09:15:00Z").ToUnixTimeSeconds().ToString(),
                iat = DateTimeOffset.Parse("2026-08-30T08:55:00Z").ToUnixTimeSeconds().ToString()
            }));
            var signingInput = $"{header}.{payload}";
            var signature = rsa.SignData(
                Encoding.UTF8.GetBytes(signingInput),
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1);

            return $"{signingInput}.{Base64UrlEncode(signature)}";
        }

        public void Dispose()
        {
            rsa.Dispose();
        }

        private static string Base64UrlEncode(byte[] bytes)
        {
            return Convert.ToBase64String(bytes)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }
    }

    private sealed class StaticJsonHandler(string json) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
