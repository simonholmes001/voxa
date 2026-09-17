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
    public const int MaximumLanguageLength = 64;
    public const int MaximumFocusTitleLength = 120;
    public const int MaximumVoiceInstructionsLength = 400;
    private static readonly HashSet<string> SupportedCoachingModes = new(StringComparer.OrdinalIgnoreCase)
    {
        "tutor"
    };

    private static readonly HashSet<string> SupportedProficiencyBands = new(StringComparer.OrdinalIgnoreCase)
    {
        "A1",
        "A2",
        "B1",
        "B2",
        "C1",
        "C2",
        "A1-A2",
        "B1-B2",
        "C1-C2",
    };

    private static readonly HashSet<string> SupportedTargetLanguages = new(StringComparer.OrdinalIgnoreCase)
    {
        "de-DE",
        "en-US",
        "es-ES",
        "fr-FR",
        "el-GR",
        "it-IT",
        "ja-JP",
        "pt-PT",
        "sco",
        "sco-GB",
        "zh-CN",
        "English",
        "French",
        "German",
        "Greek",
        "Doric",
        "Italian",
        "Japanese",
        "Mandarin",
        "Portuguese",
        "Spanish",
    };

    private static readonly HashSet<string> SupportedSessionIntents = new(StringComparer.OrdinalIgnoreCase)
    {
        "open_practice",
        "practice",
        "guided_lesson",
        "lesson",
        "review",
        "pronunciation_drill",
        "roleplay",
        "mistakes_replay",
        "vocabulary_drill",
        "listening_practice",
        "key_language",
        "voice_preview",
    };

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
            RequireAllowed(coachingMode, nameof(coachingMode), SupportedCoachingModes),
            RequireAllowed(proficiencyBand, nameof(proficiencyBand), SupportedProficiencyBands),
            RequireAllowed(targetLanguage, nameof(targetLanguage), SupportedTargetLanguages),
            OptionalLanguage(nativeLanguage, nameof(nativeLanguage)),
            OptionalAllowed(sessionIntent, nameof(sessionIntent), SupportedSessionIntents),
            OptionalFreeText(focusTitle, nameof(focusTitle), MaximumFocusTitleLength),
            dueReviewCount,
            NormalizeVoice(voice),
            NormalizeVoiceSpeed(voiceSpeed),
            OptionalVoiceInstructions(voiceInstructions),
            correlationId);
    }

    private static string Required(string? value, string name, int maxLength)
    {
        var trimmed = string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException($"{name} is required.", name)
            : value.Trim();
        if (trimmed.Length > maxLength)
        {
            throw new ArgumentException($"{name} must be {maxLength} characters or fewer.", name);
        }

        if (ContainsPromptControlSequence(trimmed))
        {
            throw new ArgumentException($"{name} contains unsupported instruction-like content.", name);
        }

        return trimmed;
    }

    private static string RequireAllowed(
        string? value,
        string name,
        HashSet<string> supportedValues)
    {
        var trimmed = Required(value, name, MaximumLanguageLength);
        return supportedValues.Contains(trimmed)
            ? trimmed
            : throw new ArgumentException($"{name} is not supported.", name);
    }

    private static string? OptionalAllowed(
        string? value,
        string name,
        HashSet<string> supportedValues)
    {
        var trimmed = OptionalFreeText(value, name, MaximumLanguageLength);
        if (trimmed is null)
        {
            return null;
        }

        return supportedValues.Contains(trimmed)
            ? trimmed
            : throw new ArgumentException($"{name} is not supported.", name);
    }

    private static string? OptionalLanguage(string? value, string name)
    {
        var trimmed = OptionalFreeText(value, name, MaximumLanguageLength);
        if (trimmed is null)
        {
            return null;
        }

        if (!trimmed.All(character =>
                char.IsLetter(character)
                || char.IsWhiteSpace(character)
                || character is '-' or '\'' or '(' or ')'))
        {
            throw new ArgumentException($"{name} contains unsupported characters.", name);
        }

        return trimmed;
    }

    private static string? OptionalFreeText(string? value, string name, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        if (trimmed.Length > maxLength)
        {
            throw new ArgumentException($"{name} must be {maxLength} characters or fewer.", name);
        }

        if (ContainsPromptControlSequence(trimmed))
        {
            throw new ArgumentException($"{name} contains unsupported instruction-like content.", name);
        }

        return trimmed;
    }

    private static string NormalizeVoice(string? value)
    {
        var voice = OptionalFreeText(value, "voice", MaximumLanguageLength)?.ToLowerInvariant() ?? DefaultVoice;
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
        return OptionalFreeText(value, "voiceInstructions", MaximumVoiceInstructionsLength);
    }

    private static bool ContainsPromptControlSequence(string value)
    {
        return value.Contains("{{", StringComparison.Ordinal)
            || value.Contains("}}", StringComparison.Ordinal)
            || value.Contains("<|", StringComparison.Ordinal)
            || value.Contains("|>", StringComparison.Ordinal)
            || value.Contains("```", StringComparison.Ordinal)
            || value.Contains("system:", StringComparison.OrdinalIgnoreCase)
            || value.Contains("assistant:", StringComparison.OrdinalIgnoreCase)
            || value.Contains("developer:", StringComparison.OrdinalIgnoreCase);
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

public sealed class RealtimeSessionIssueException(
    string message,
    string code = "realtime_session_unavailable",
    int statusCode = 503,
    bool retryable = true) : Exception(message)
{
    public string Code { get; } = code;

    public int StatusCode { get; } = statusCode;

    public bool Retryable { get; } = retryable;
}

public sealed class RealtimeSessionRateLimitException(
    string message,
    string code = "realtime_session_rate_limited") : Exception(message)
{
    public string Code { get; } = code;
}
