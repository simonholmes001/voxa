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
            fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
            "authorization-code",
            "nonce-123",
            CancellationToken.None);

        Assert.Equal("tenant-default", identity.TenantId);
        Assert.Equal("apple-user-123", identity.UserId);
        Assert.Equal("authorization-code", fixture.Handler.TokenRequestCode);
        Assert.Equal("authorization_code", fixture.Handler.TokenRequestGrantType);
        Assert.Equal("com.voxa.ios", fixture.Handler.TokenRequestClientId);
        Assert.False(string.IsNullOrWhiteSpace(fixture.Handler.TokenRequestClientSecret));
    }

    [Fact]
    public async Task VerifyAcceptsNativeAppleHashedNonceClaim()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();

        var identity = await verifier.VerifyAsync(
            fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "raw-nonce-123"),
            "authorization-code",
            "raw-nonce-123",
            CancellationToken.None);

        Assert.Equal("apple-user-123", identity.UserId);
    }

    [Fact]
    public async Task VerifyRejectsWrongAudience()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "wrong-client", rawNonce: "nonce-123"),
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
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "authorization-code",
                "different-nonce",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsTamperedSignature()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();
        var token = fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123");

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.ReplaceSignature(token),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsMissingAuthorizationCode()
    {
        using var fixture = AppleJwtFixture.Create();
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsAuthorizationCodeRejectedByApple()
    {
        using var fixture = AppleJwtFixture.Create(tokenStatusCode: HttpStatusCode.BadRequest);
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsTokenEndpointIdentityTokenWithTamperedSignature()
    {
        using var fixture = AppleJwtFixture.Create();
        fixture.Handler.TokenResponseJson = JsonSerializer.Serialize(new
        {
            id_token = fixture.ReplaceSignature(fixture.CreateToken(audience: "com.voxa.ios", nonce: "unused"))
        });
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsTokenEndpointIdentityTokenWithMalformedSignature()
    {
        using var fixture = AppleJwtFixture.Create();
        fixture.Handler.TokenResponseJson = JsonSerializer.Serialize(new
        {
            id_token = fixture.ReplaceSignature(fixture.CreateToken(audience: "com.voxa.ios", nonce: "unused"), "not-base64!")
        });
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsTokenEndpointIdentityTokenWithWrongAudience()
    {
        using var fixture = AppleJwtFixture.Create();
        fixture.Handler.TokenResponseJson = JsonSerializer.Serialize(new
        {
            id_token = fixture.CreateToken(audience: "wrong-client", nonce: "unused")
        });
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyRejectsTokenEndpointIdentityTokenWithExpiredToken()
    {
        using var fixture = AppleJwtFixture.Create();
        fixture.Handler.TokenResponseJson = JsonSerializer.Serialize(new
        {
            id_token = fixture.CreateToken(
                audience: "com.voxa.ios",
                nonce: "unused",
                expiresAt: DateTimeOffset.Parse("2026-08-30T08:59:59Z"))
        });
        var verifier = fixture.CreateVerifier();

        await Assert.ThrowsAsync<AppleIdentityVerificationException>(() =>
            verifier.VerifyAsync(
                fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
                "authorization-code",
                "nonce-123",
                CancellationToken.None));
    }

    [Fact]
    public async Task VerifyAcceptsIndentedApplePrivateKeyPemFromSecretPasting()
    {
        using var fixture = AppleJwtFixture.Create();
        var indentedPem = string.Join(
            "\n",
            fixture.ExportClientSecretPrivateKeyPem()
                .Split('\n')
                .Where(line => line.Length > 0)
                .Select(line => $"  {line}  "));
        var verifier = fixture.CreateVerifier(indentedPem);

        var identity = await verifier.VerifyAsync(
            fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
            "authorization-code",
            "nonce-123",
            CancellationToken.None);

        Assert.Equal("apple-user-123", identity.UserId);
        Assert.False(string.IsNullOrWhiteSpace(fixture.Handler.TokenRequestClientSecret));
    }

    [Fact]
    public async Task VerifyAcceptsEscapedAndQuotedApplePrivateKeyPemFromDeploymentPipeline()
    {
        using var fixture = AppleJwtFixture.Create();
        var escapedPem = "\"" + fixture.ExportClientSecretPrivateKeyPem()
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal) + "\"";
        var verifier = fixture.CreateVerifier(escapedPem);

        var identity = await verifier.VerifyAsync(
            fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
            "authorization-code",
            "nonce-123",
            CancellationToken.None);

        Assert.Equal("apple-user-123", identity.UserId);
        Assert.False(string.IsNullOrWhiteSpace(fixture.Handler.TokenRequestClientSecret));
    }

    [Fact]
    public async Task VerifyAcceptsFlattenedApplePrivateKeyPemFromSecretTransport()
    {
        using var fixture = AppleJwtFixture.Create();
        var flattenedPem = fixture.ExportClientSecretPrivateKeyPem()
            .Replace("\r", "", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal);
        var verifier = fixture.CreateVerifier(flattenedPem);

        var identity = await verifier.VerifyAsync(
            fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
            "authorization-code",
            "nonce-123",
            CancellationToken.None);

        Assert.Equal("apple-user-123", identity.UserId);
        Assert.False(string.IsNullOrWhiteSpace(fixture.Handler.TokenRequestClientSecret));
    }

    [Fact]
    public async Task VerifyAcceptsPemWithNonStandardBoundaryWhitespace()
    {
        using var fixture = AppleJwtFixture.Create();
        var pem = fixture.ExportClientSecretPrivateKeyPem();
        var body = pem
            .Replace("-----BEGIN PRIVATE KEY-----", "", StringComparison.Ordinal)
            .Replace("-----END PRIVATE KEY-----", "", StringComparison.Ordinal)
            .Replace("\r", "", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal)
            .Trim();
        var copiedPem = $"\uFEFF ------BEGIN PRIVATE KEY------ {body} ------END PRIVATE KEY------ ";
        var verifier = fixture.CreateVerifier(copiedPem);

        var identity = await verifier.VerifyAsync(
            fixture.CreateTokenWithRawNonce(audience: "com.voxa.ios", rawNonce: "nonce-123"),
            "authorization-code",
            "nonce-123",
            CancellationToken.None);

        Assert.Equal("apple-user-123", identity.UserId);
        Assert.False(string.IsNullOrWhiteSpace(fixture.Handler.TokenRequestClientSecret));
    }

    private sealed class AppleJwtFixture : IDisposable
    {
        private const string KeyId = "apple-key-1";
        private readonly RSA rsa;
        private readonly RSAParameters publicKey;
        private readonly ECDsa clientSecretKey;

        private AppleJwtFixture(RSA rsa, ECDsa clientSecretKey, RecordingAppleHandler handler)
        {
            this.rsa = rsa;
            this.clientSecretKey = clientSecretKey;
            publicKey = rsa.ExportParameters(false);
            Handler = handler;
        }

        public RecordingAppleHandler Handler { get; }

        public static AppleJwtFixture Create(HttpStatusCode tokenStatusCode = HttpStatusCode.OK)
        {
            var rsa = RSA.Create(2048);
            var clientSecretKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var fixture = new AppleJwtFixture(
                rsa,
                clientSecretKey,
                new RecordingAppleHandler(tokenStatusCode));
            fixture.Handler.JwksJson = fixture.CreateJwks();
            fixture.Handler.TokenResponseJson = JsonSerializer.Serialize(new
            {
                id_token = fixture.CreateToken(audience: "com.voxa.ios", nonce: "nonce-123")
            });
            return fixture;
        }

        public AppleJwksIdentityVerifier CreateVerifier(string? privateKeyPem = null)
        {
            return new AppleJwksIdentityVerifier(
                new HttpClient(Handler),
                new AppleJwksIdentityVerifierOptions(
                    "com.voxa.ios",
                    "tenant-default",
                    new Uri("https://appleid.apple.com/auth/keys"),
                    new Uri("https://appleid.apple.com/auth/token"),
                    "2PA85SU4UQ",
                    "APPLEKEYID1",
                    privateKeyPem ?? ExportClientSecretPrivateKeyPem()),
                new FixedClock(DateTimeOffset.Parse("2026-08-30T09:00:00Z")));
        }

        private string CreateJwks()
        {
            return JsonSerializer.Serialize(new
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
        }

        public string CreateToken(
            string audience,
            string nonce,
            DateTimeOffset? expiresAt = null,
            string subject = "apple-user-123")
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
                sub = subject,
                nonce,
                exp = (expiresAt ?? DateTimeOffset.Parse("2026-08-30T09:15:00Z")).ToUnixTimeSeconds().ToString(),
                iat = DateTimeOffset.Parse("2026-08-30T08:55:00Z").ToUnixTimeSeconds().ToString()
            }));
            var signingInput = $"{header}.{payload}";
            var signature = rsa.SignData(
                Encoding.UTF8.GetBytes(signingInput),
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1);

            return $"{signingInput}.{Base64UrlEncode(signature)}";
        }

        public string CreateTokenWithRawNonce(string audience, string rawNonce)
        {
            return CreateToken(audience, Sha256Hex(rawNonce));
        }

        public string ReplaceSignature(string token)
        {
            return ReplaceSignature(token, Base64UrlEncode(new byte[256]));
        }

        public string ReplaceSignature(string token, string signature)
        {
            var parts = token.Split('.');
            return $"{parts[0]}.{parts[1]}.{signature}";
        }

        public void Dispose()
        {
            rsa.Dispose();
            clientSecretKey.Dispose();
        }

        public string ExportClientSecretPrivateKeyPem()
        {
            return clientSecretKey.ExportPkcs8PrivateKeyPem();
        }

        private static string Base64UrlEncode(byte[] bytes)
        {
            return Convert.ToBase64String(bytes)
                .TrimEnd('=')
                .Replace('+', '-')
                .Replace('/', '_');
        }

        private static string Sha256Hex(string value)
        {
            return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
        }
    }

    private sealed class RecordingAppleHandler(HttpStatusCode tokenStatusCode) : HttpMessageHandler
    {
        public string JwksJson { get; set; } = "";

        public string TokenResponseJson { get; set; } = "{}";

        public string? TokenRequestClientId { get; private set; }

        public string? TokenRequestClientSecret { get; private set; }

        public string? TokenRequestCode { get; private set; }

        public string? TokenRequestGrantType { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            if (request.RequestUri?.AbsolutePath == "/auth/token")
            {
                return HandleTokenRequestAsync(request, cancellationToken);
            }

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(JwksJson, Encoding.UTF8, "application/json")
            });
        }

        private async Task<HttpResponseMessage> HandleTokenRequestAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            var form = await request.Content!.ReadAsStringAsync(cancellationToken);
            var values = form.Split('&', StringSplitOptions.RemoveEmptyEntries)
                .Select(part => part.Split('=', 2))
                .ToDictionary(
                    part => Uri.UnescapeDataString(part[0]),
                    part => Uri.UnescapeDataString(part[1].Replace("+", " ")),
                    StringComparer.Ordinal);

            TokenRequestClientId = values.GetValueOrDefault("client_id");
            TokenRequestClientSecret = values.GetValueOrDefault("client_secret");
            TokenRequestCode = values.GetValueOrDefault("code");
            TokenRequestGrantType = values.GetValueOrDefault("grant_type");

            return new HttpResponseMessage(tokenStatusCode)
            {
                Content = new StringContent(TokenResponseJson, Encoding.UTF8, "application/json")
            };
        }
    }

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
