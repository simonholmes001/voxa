using System.Globalization;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Voxa.Application.Authentication;

namespace Voxa.Infrastructure.Authentication;

public sealed record AppleJwksIdentityVerifierOptions(
    string ClientId,
    string TenantId,
    Uri JwksUri,
    Uri TokenUri,
    string TeamId,
    string KeyId,
    string PrivateKeyPem);

public sealed class AppleJwksIdentityVerifier(
    HttpClient httpClient,
    AppleJwksIdentityVerifierOptions options,
    ISystemClock clock) : IAppleIdentityVerifier
{
    private const string AppleIssuer = "https://appleid.apple.com";

    public async Task<VerifiedAppleIdentity> VerifyAsync(
        string identityToken,
        string authorizationCode,
        string nonce,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.ClientId))
        {
            throw new AppleIdentityVerificationException("APPLE_CLIENT_ID is required.");
        }

        if (string.IsNullOrWhiteSpace(authorizationCode))
        {
            throw new AppleIdentityVerificationException("Apple authorization code is required.");
        }

        var parts = identityToken.Split('.');
        if (parts.Length != 3)
        {
            throw new AppleIdentityVerificationException("Apple identity token is malformed.");
        }

        var header = ReadJson(parts[0]);
        var payload = ReadJson(parts[1]);
        var algorithm = RequiredString(header, "alg");
        var keyId = RequiredString(header, "kid");

        if (!string.Equals(algorithm, "RS256", StringComparison.Ordinal))
        {
            throw new AppleIdentityVerificationException("Apple identity token uses an unsupported signing algorithm.");
        }

        ValidateClaims(payload, nonce);
        var key = await FindSigningKeyAsync(keyId, cancellationToken);
        var signedBytes = Encoding.UTF8.GetBytes($"{parts[0]}.{parts[1]}");
        var signature = Base64UrlDecode(parts[2]);

        using var rsa = RSA.Create();
        rsa.ImportParameters(key);

        if (!rsa.VerifyData(signedBytes, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
        {
            throw new AppleIdentityVerificationException("Apple identity token signature is invalid.");
        }

        var subject = RequiredString(payload, "sub");
        await ValidateAuthorizationCodeAsync(authorizationCode, subject, cancellationToken);

        return new VerifiedAppleIdentity(options.TenantId, subject);
    }

    private async Task ValidateAuthorizationCodeAsync(
        string authorizationCode,
        string expectedSubject,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.TeamId)
            || string.IsNullOrWhiteSpace(options.KeyId)
            || string.IsNullOrWhiteSpace(options.PrivateKeyPem))
        {
            throw new AppleIdentityVerificationException(
                "APPLE_TEAM_ID, APPLE_KEY_ID, and APPLE_PRIVATE_KEY are required.");
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, options.TokenUri)
        {
            Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = options.ClientId,
                ["client_secret"] = CreateClientSecret(),
                ["code"] = authorizationCode,
                ["grant_type"] = "authorization_code"
            })
        };

        using var response = await httpClient.SendAsync(request, cancellationToken)
            .ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new AppleIdentityVerificationException("Apple authorization code validation failed.");
        }

        var body = await response.Content.ReadFromJsonAsync<AppleTokenResponse>(
            cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(body?.IdToken))
        {
            throw new AppleIdentityVerificationException("Apple authorization code response did not include an identity token.");
        }

        var exchangedPayload = ReadJwtPayload(body.IdToken);
        if (!string.Equals(RequiredString(exchangedPayload, "sub"), expectedSubject, StringComparison.Ordinal))
        {
            throw new AppleIdentityVerificationException("Apple authorization code identity does not match the supplied identity token.");
        }
    }

    private string CreateClientSecret()
    {
        var now = clock.UtcNow;
        var header = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
        {
            alg = "ES256",
            kid = options.KeyId
        }));
        var payload = Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
        {
            iss = options.TeamId,
            iat = now.ToUnixTimeSeconds(),
            exp = now.AddMinutes(30).ToUnixTimeSeconds(),
            aud = AppleIssuer,
            sub = options.ClientId
        }));
        var signingInput = $"{header}.{payload}";

        using var ecdsa = ECDsa.Create();
        ecdsa.ImportFromPem(NormalizePem(options.PrivateKeyPem));
        var signature = ecdsa.SignData(
            Encoding.ASCII.GetBytes(signingInput),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation);

        return $"{signingInput}.{Base64UrlEncode(signature)}";
    }

    private void ValidateClaims(JsonElement payload, string nonce)
    {
        if (!string.Equals(RequiredString(payload, "iss"), AppleIssuer, StringComparison.Ordinal))
        {
            throw new AppleIdentityVerificationException("Apple identity token issuer is invalid.");
        }

        if (!string.Equals(RequiredString(payload, "aud"), options.ClientId, StringComparison.Ordinal))
        {
            throw new AppleIdentityVerificationException("Apple identity token audience is invalid.");
        }

        if (!string.Equals(RequiredString(payload, "nonce"), nonce, StringComparison.Ordinal))
        {
            throw new AppleIdentityVerificationException("Apple identity token nonce is invalid.");
        }

        var expiresAt = DateTimeOffset.FromUnixTimeSeconds(RequiredUnixTime(payload, "exp"));
        if (expiresAt <= clock.UtcNow)
        {
            throw new AppleIdentityVerificationException("Apple identity token has expired.");
        }

        _ = RequiredString(payload, "sub");
    }

    private async Task<RSAParameters> FindSigningKeyAsync(string keyId, CancellationToken cancellationToken)
    {
        var jwks = await httpClient.GetFromJsonAsync<JsonElement>(options.JwksUri, cancellationToken)
            .ConfigureAwait(false);

        if (!jwks.TryGetProperty("keys", out var keys) || keys.ValueKind != JsonValueKind.Array)
        {
            throw new AppleIdentityVerificationException("Apple JWKS response is invalid.");
        }

        foreach (var key in keys.EnumerateArray())
        {
            if (!string.Equals(RequiredString(key, "kid"), keyId, StringComparison.Ordinal))
            {
                continue;
            }

            if (!string.Equals(RequiredString(key, "kty"), "RSA", StringComparison.Ordinal))
            {
                continue;
            }

            return new RSAParameters
            {
                Modulus = Base64UrlDecode(RequiredString(key, "n")),
                Exponent = Base64UrlDecode(RequiredString(key, "e"))
            };
        }

        throw new AppleIdentityVerificationException("Apple signing key was not found.");
    }

    private static JsonElement ReadJson(string base64Url)
    {
        try
        {
            using var document = JsonDocument.Parse(Base64UrlDecode(base64Url));
            return document.RootElement.Clone();
        }
        catch (JsonException exception)
        {
            throw new AppleIdentityVerificationException($"Apple identity token JSON is invalid: {exception.Message}");
        }
        catch (FormatException exception)
        {
            throw new AppleIdentityVerificationException($"Apple identity token encoding is invalid: {exception.Message}");
        }
    }

    private static JsonElement ReadJwtPayload(string jwt)
    {
        var parts = jwt.Split('.');
        if (parts.Length != 3)
        {
            throw new AppleIdentityVerificationException("Apple token endpoint identity token is malformed.");
        }

        return ReadJson(parts[1]);
    }

    private static string RequiredString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.String)
        {
            throw new AppleIdentityVerificationException($"Apple identity token is missing {propertyName}.");
        }

        var result = value.GetString();
        if (string.IsNullOrWhiteSpace(result))
        {
            throw new AppleIdentityVerificationException($"Apple identity token is missing {propertyName}.");
        }

        return result;
    }

    private static long RequiredUnixTime(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
        {
            throw new AppleIdentityVerificationException($"Apple identity token is missing {propertyName}.");
        }

        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var numericSeconds))
        {
            return numericSeconds;
        }

        if (value.ValueKind != JsonValueKind.String
            || !long.TryParse(value.GetString(), NumberStyles.None, CultureInfo.InvariantCulture, out var seconds))
        {
            throw new AppleIdentityVerificationException($"Apple identity token {propertyName} is invalid.");
        }

        return seconds;
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
        return Convert.FromBase64String(padded);
    }

    private static string Base64UrlEncode(ReadOnlySpan<byte> bytes)
    {
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static string NormalizePem(string pem)
    {
        return pem.Replace("\\n", "\n", StringComparison.Ordinal);
    }

    private sealed record AppleTokenResponse(
        [property: JsonPropertyName("id_token")] string? IdToken);
}
