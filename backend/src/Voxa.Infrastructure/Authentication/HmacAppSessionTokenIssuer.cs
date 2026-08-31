using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.Authentication;

public interface ISystemClock
{
    DateTimeOffset UtcNow { get; }
}

public sealed class SystemClock : ISystemClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}

public sealed record AppSessionTokenOptions(
    string SigningKey,
    TimeSpan AccessTokenLifetime,
    TimeSpan RefreshTokenLifetime);

public sealed class HmacAppSessionTokenIssuer(
    AppSessionTokenOptions options,
    ISystemClock clock) : IAppSessionTokenIssuer, IAppSessionTokenValidator
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public AppSessionTokenPair IssueTokenPair(
        VerifiedAppSessionSubject subject,
        CorrelationId correlationId)
    {
        var issuedAt = clock.UtcNow;
        var accessExpiresAt = issuedAt.Add(options.AccessTokenLifetime);
        var refreshExpiresAt = issuedAt.Add(options.RefreshTokenLifetime);
        var accessToken = CreateSignedToken(new AppSessionAccessTokenDocument(
            subject.TenantId.Value,
            subject.UserId.Value,
            accessExpiresAt.ToUnixTimeSeconds()));

        return new AppSessionTokenPair(
            correlationId.Value,
            subject.TenantId.Value,
            subject.UserId.Value,
            accessToken,
            CreateRefreshToken(),
            accessExpiresAt,
            refreshExpiresAt);
    }

    public AppSessionPrincipal? ValidateAccessToken(string? accessToken, DateTimeOffset utcNow)
    {
        if (string.IsNullOrWhiteSpace(accessToken))
        {
            return null;
        }

        var parts = accessToken.Split('.', 2);
        if (parts.Length != 2)
        {
            return null;
        }

        try
        {
            var expectedSignatureBytes = Encoding.ASCII.GetBytes(Sign(parts[0]));
            var actualSignatureBytes = Encoding.ASCII.GetBytes(parts[1]);
            if (expectedSignatureBytes.Length != actualSignatureBytes.Length
                || !CryptographicOperations.FixedTimeEquals(expectedSignatureBytes, actualSignatureBytes))
            {
                return null;
            }

            var payloadJson = Encoding.UTF8.GetString(Base64UrlDecode(parts[0]));
            var payload = JsonSerializer.Deserialize<AppSessionAccessTokenDocument>(payloadJson, JsonOptions);
            if (payload is null || payload.ExpiresAtUnixSeconds <= utcNow.ToUnixTimeSeconds())
            {
                return null;
            }

            return new AppSessionPrincipal(
                TenantId.Create(payload.TenantId),
                UserId.Create(payload.UserId));
        }
        catch (ArgumentException)
        {
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    private string CreateSignedToken(AppSessionAccessTokenDocument payload)
    {
        var payloadJson = JsonSerializer.Serialize(payload, JsonOptions);
        var encodedPayload = Base64UrlEncode(Encoding.UTF8.GetBytes(payloadJson));
        return $"{encodedPayload}.{Sign(encodedPayload)}";
    }

    private string Sign(string encodedPayload)
    {
        var key = Encoding.UTF8.GetBytes(options.SigningKey);
        var signature = HMACSHA256.HashData(key, Encoding.ASCII.GetBytes(encodedPayload));
        return Base64UrlEncode(signature);
    }

    private static string CreateRefreshToken()
    {
        Span<byte> bytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(bytes);
        return Base64UrlEncode(bytes);
    }

    private static string Base64UrlEncode(ReadOnlySpan<byte> bytes)
    {
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
        return Convert.FromBase64String(padded);
    }

    private sealed record AppSessionAccessTokenDocument(
        string TenantId,
        string UserId,
        long ExpiresAtUnixSeconds);
}
