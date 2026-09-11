using Voxa.Domain.Learners;

namespace Voxa.Application.Realtime;

public interface IRealtimeSessionService
{
    Task<RealtimeSessionCredential> IssueClientSecretAsync(
        RealtimeSessionCommand command,
        CancellationToken cancellationToken);
}

public interface IRealtimeClientSecretIssuer
{
    Task<RealtimeSessionCredential> IssueAsync(
        RealtimeSessionRequest request,
        CancellationToken cancellationToken);
}

public interface IRealtimeSessionRateLimiter
{
    Task EnsureAllowedAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken);
}

public interface IRealtimeSessionAuditLog
{
    Task RecordAsync(
        RealtimeSessionAuditEvent auditEvent,
        CancellationToken cancellationToken);
}

public sealed record RealtimeSessionCommand(
    TenantId TenantId,
    UserId UserId,
    string CoachingMode,
    string ProficiencyBand,
    string TargetLanguage,
    string? NativeLanguage,
    string? SessionIntent,
    string? FocusTitle,
    int? DueReviewCount,
    CorrelationId CorrelationId)
{
    public static RealtimeSessionCommand Create(
        string? tenantId,
        string? userId,
        string? coachingMode,
        string? proficiencyBand,
        string? targetLanguage,
        CorrelationId correlationId)
    {
        return Create(
            tenantId,
            userId,
            coachingMode,
            proficiencyBand,
            targetLanguage,
            nativeLanguage: null,
            sessionIntent: null,
            focusTitle: null,
            dueReviewCount: null,
            correlationId);
    }

    public static RealtimeSessionCommand Create(
        string? tenantId,
        string? userId,
        string? coachingMode,
        string? proficiencyBand,
        string? targetLanguage,
        string? nativeLanguage,
        string? sessionIntent,
        string? focusTitle,
        int? dueReviewCount,
        CorrelationId correlationId)
    {
        return new RealtimeSessionCommand(
            TenantId.Create(tenantId ?? ""),
            UserId.Create(userId ?? ""),
            Required(coachingMode, nameof(coachingMode)),
            Required(proficiencyBand, nameof(proficiencyBand)),
            Required(targetLanguage, nameof(targetLanguage)),
            Optional(nativeLanguage),
            Optional(sessionIntent),
            Optional(focusTitle),
            dueReviewCount,
            correlationId);
    }

    private static string Required(string? value, string name)
    {
        return string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException($"{name} is required.", name)
            : value.Trim();
    }

    private static string? Optional(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}

public sealed record RealtimeSessionCredential(
    string CorrelationId,
    string ClientSecret,
    string Model,
    string ReasoningEffort,
    DateTimeOffset ExpiresAt,
    RealtimeSessionSettingsContract Settings);

public sealed record RealtimeSessionRequest(
    TenantId TenantId,
    UserId UserId,
    CorrelationId CorrelationId,
    RealtimeSessionSettingsContract Settings);

public sealed record RealtimeSessionAuditEvent(
    string CorrelationId,
    string TenantId,
    string UserId,
    string Outcome,
    string CoachingMode,
    string TargetLanguage);

public sealed record RealtimeSessionSettingsContract(
    string CoachingMode,
    string ProficiencyBand,
    string TargetLanguage,
    string? SessionIntent = null,
    string? FocusTitle = null,
    int? DueReviewCount = null,
    string? NativeLanguage = null);

public sealed class RealtimeSessionIssueException(string message) : Exception(message);

public sealed class RealtimeSessionRateLimitException(string message) : Exception(message);
