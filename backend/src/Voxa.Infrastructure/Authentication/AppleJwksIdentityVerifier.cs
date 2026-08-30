using System.Globalization;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Voxa.Application.Authentication;

namespace Voxa.Infrastructure.Authentication;

public sealed record AppleJwksIdentityVerifierOptions(
    string ClientId,
    string TenantId,
    Uri JwksUri);

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

        return new VerifiedAppleIdentity(options.TenantId, RequiredString(payload, "sub"));
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
}
