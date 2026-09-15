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

    Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken);
}

public interface IRealtimeSessionAuditLog
{
    Task RecordAsync(
        RealtimeSessionAuditEvent auditEvent,
        CancellationToken cancellationToken);

    Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
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
    string? Voice,
    double? VoiceSpeed,
    string? VoiceInstructions,
    CorrelationId CorrelationId)
{
    public const double MinimumVoiceSpeed = 0.25;
    public const double MaximumVoiceSpeed = 1.5;
    public const string DefaultVoice = "marin";
    private static readonly HashSet<string> SupportedVoices = new(StringComparer.Ordinal)
    {
        "alloy",
        "ash",
        "ballad",
        "coral",
        "echo",
        "sage",
        "shimmer",
        "verse",
        "marin",
        "cedar",
    };

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
            voice: null,
            voiceSpeed: null,
            voiceInstructions: null,
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
        string? voice,
        double? voiceSpeed,
        string? voiceInstructions,
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
            NormalizeVoice(voice),
            NormalizeVoiceSpeed(voiceSpeed),
            OptionalVoiceInstructions(voiceInstructions),
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

    private static string NormalizeVoice(string? value)
    {
        var voice = Optional(value)?.ToLowerInvariant() ?? DefaultVoice;
        return SupportedVoices.Contains(voice)
            ? voice
            : throw new ArgumentException($"{nameof(voice)} is not supported.", nameof(voice));
    }

    private static double NormalizeVoiceSpeed(double? value)
    {
        return Math.Clamp(value ?? 1.0, MinimumVoiceSpeed, MaximumVoiceSpeed);
    }

    private static string? OptionalVoiceInstructions(string? value)
    {
        var trimmed = Optional(value);
        return trimmed is null ? null : trimmed[..Math.Min(trimmed.Length, 400)];
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
    string? NativeLanguage = null,
    string Voice = RealtimeSessionCommand.DefaultVoice,
    double VoiceSpeed = 1.0,
    string? VoiceInstructions = null);

public sealed class RealtimeSessionIssueException(string message) : Exception(message);

public sealed class RealtimeSessionRateLimitException(string message) : Exception(message);
