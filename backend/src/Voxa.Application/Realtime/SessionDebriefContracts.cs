using Voxa.Domain.Learners;

namespace Voxa.Application.Realtime;

/// <summary>
/// Produces a structured post-session debrief from a completed Talk session's
/// transcript. Runs after the WebSocket closes, non-realtime; the app renders
/// the result as cards on the debrief screen. Phase D later feeds the evidence
/// back into the learner model.
/// </summary>
public interface IDebriefService
{
    Task<SessionDebrief> GenerateDebriefAsync(
        SessionDebriefRequest request,
        CancellationToken cancellationToken);
}

/// <summary>
/// Input to the debrief pass: identity, the coaching settings that governed
/// the session, and the full turn-by-turn transcript.
/// </summary>
public sealed record SessionDebriefRequest(
    TenantId TenantId,
    UserId UserId,
    CorrelationId CorrelationId,
    RealtimeSessionSettingsContract Settings,
    IReadOnlyList<TranscriptTurn> Transcript);

/// <summary>
/// One turn of the transcript. `Role` is "learner" or "tutor"; anything else
/// is treated as unknown and reported to the assessor as-is.
/// </summary>
public sealed record TranscriptTurn(string Role, string Text)
{
    public const string LearnerRole = "learner";
    public const string TutorRole = "tutor";
}

/// <summary>
/// Structured output of the debrief. All list fields are non-null but may be
/// empty for very short transcripts (the assessor is instructed not to
/// invent content just to fill quotas).
/// </summary>
public sealed record SessionDebrief(
    string CorrelationId,
    string Summary,
    IReadOnlyList<DebriefRecurringMistake> RecurringMistakes,
    IReadOnlyList<string> UsefulPhrases,
    IReadOnlyList<string> PronunciationNotes,
    DebriefRecommendedDrill RecommendedNextDrill);

public sealed record DebriefRecurringMistake(
    string Pattern,
    string Example,
    string Severity);

public sealed record DebriefRecommendedDrill(
    string ActivityIntent,
    string FocusTitle,
    string Reason);

/// <summary>
/// Non-fatal exception thrown when the assessor call fails or its output does
/// not match the schema. The API endpoint maps this to a retriable 502/503.
/// </summary>
public sealed class SessionDebriefException(string message) : Exception(message);
