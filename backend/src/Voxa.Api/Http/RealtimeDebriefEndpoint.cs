using Microsoft.Extensions.Logging;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

/// <summary>
/// POST /api/realtime/debrief — generates a structured post-session debrief
/// from the completed Talk session's transcript. Non-realtime; calls the
/// AssessmentModel with the `realtime-tutor/debrief.v1` prompt. Persists the
/// debrief to durable learner state after generating it so Phase C2's
/// curriculum planner has accumulated evidence to plan against; persistence
/// failure is non-fatal — the client still gets the debrief.
/// </summary>
public sealed class RealtimeDebriefEndpoint(
    IDebriefService debriefService,
    ILearnerEvidenceService learnerEvidence,
    ILogger<RealtimeDebriefEndpoint> logger)
{
    public async Task<ApiResponse<SessionDebriefHttpResponse>> PostAsync(
        AppSessionPrincipal? principal,
        SessionDebriefHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        if (principal is null)
        {
            return Failure(
                "app_session_required",
                "An authenticated app session is required.",
                requestCorrelationId,
                401,
                retryable: false);
        }

        RealtimeSessionSettingsContract settings;
        List<TranscriptTurn> transcript;
        try
        {
            settings = new RealtimeSessionSettingsContract(
                Required(request.CoachingMode, nameof(request.CoachingMode)),
                Required(request.ProficiencyBand, nameof(request.ProficiencyBand)),
                Required(request.TargetLanguage, nameof(request.TargetLanguage)),
                SessionIntent: Optional(request.SessionIntent),
                FocusTitle: Optional(request.FocusTitle),
                DueReviewCount: request.DueReviewCount);

            transcript = (request.Transcript ?? [])
                .Where(turn => !string.IsNullOrWhiteSpace(turn.Text))
                .Select(turn => new TranscriptTurn(
                    string.IsNullOrWhiteSpace(turn.Role) ? "unknown" : turn.Role!.Trim(),
                    turn.Text!.Trim()))
                .ToList();
        }
        catch (ArgumentException exception)
        {
            return Failure("validation_error", exception.Message, requestCorrelationId, 400, retryable: false);
        }

        SessionDebrief debrief;
        try
        {
            debrief = await debriefService.GenerateDebriefAsync(
                new SessionDebriefRequest(
                    principal.TenantId,
                    principal.UserId,
                    requestCorrelationId,
                    settings,
                    transcript),
                cancellationToken);
        }
        catch (SessionDebriefException)
        {
            return Failure(
                "debrief_unavailable",
                "Session debrief could not be generated.",
                requestCorrelationId,
                503,
                retryable: true);
        }

        // Persist to learner state so C2's planner has accumulated evidence.
        // Persistence failure is non-fatal — the client still gets the debrief.
        try
        {
            await learnerEvidence.RecordDebriefAsync(
                principal.TenantId,
                principal.UserId,
                debrief,
                cancellationToken);
        }
        catch (Exception exception)
        {
            logger.LogWarning(
                exception,
                "Debrief persistence failed but debrief was returned. correlationId={CorrelationId} tenantId={TenantId} userId={UserId}",
                requestCorrelationId.Value,
                principal.TenantId.Value,
                principal.UserId.Value);
        }

        return ApiResponse<SessionDebriefHttpResponse>.Ok(
            SessionDebriefHttpResponse.FromDebrief(debrief));
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

    private static ApiResponse<SessionDebriefHttpResponse> Failure(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode,
        bool retryable)
    {
        return ApiResponse<SessionDebriefHttpResponse>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, retryable));
    }
}

public sealed record SessionDebriefHttpRequest(
    string? CoachingMode,
    string? ProficiencyBand,
    string? TargetLanguage,
    string? SessionIntent = null,
    string? FocusTitle = null,
    int? DueReviewCount = null,
    IReadOnlyList<TranscriptTurnDto>? Transcript = null);

public sealed record TranscriptTurnDto(string? Role, string? Text);

public sealed record SessionDebriefHttpResponse(
    string CorrelationId,
    string Summary,
    IReadOnlyList<DebriefRecurringMistakeDto> RecurringMistakes,
    IReadOnlyList<string> UsefulPhrases,
    IReadOnlyList<string> PronunciationNotes,
    DebriefRecommendedDrillDto RecommendedNextDrill)
{
    public static SessionDebriefHttpResponse FromDebrief(SessionDebrief debrief)
    {
        return new SessionDebriefHttpResponse(
            debrief.CorrelationId,
            debrief.Summary,
            debrief.RecurringMistakes
                .Select(m => new DebriefRecurringMistakeDto(m.Pattern, m.Example, m.Severity))
                .ToArray(),
            debrief.UsefulPhrases,
            debrief.PronunciationNotes,
            new DebriefRecommendedDrillDto(
                debrief.RecommendedNextDrill.ActivityIntent,
                debrief.RecommendedNextDrill.FocusTitle,
                debrief.RecommendedNextDrill.Reason));
    }
}

public sealed record DebriefRecurringMistakeDto(string Pattern, string Example, string Severity);

public sealed record DebriefRecommendedDrillDto(string ActivityIntent, string FocusTitle, string Reason);
