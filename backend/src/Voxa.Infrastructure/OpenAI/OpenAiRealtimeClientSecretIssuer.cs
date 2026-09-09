using System.Globalization;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Voxa.Application.Ai;
using Voxa.Application.Realtime;

namespace Voxa.Infrastructure.OpenAI;

public sealed record OpenAiRealtimeOptions(string ApiKey);

public sealed class OpenAiRealtimeClientSecretIssuer(
    HttpClient httpClient,
    OpenAiRealtimeOptions options,
    IModelRouter modelRouter,
    IPromptRegistry promptRegistry,
    ILogger<OpenAiRealtimeClientSecretIssuer> logger) : IRealtimeClientSecretIssuer
{
    public async Task<RealtimeSessionCredential> IssueAsync(
        RealtimeSessionRequest request,
        CancellationToken cancellationToken)
    {
        var route = modelRouter.Resolve(new ModelRouteRequest(
            AiCapability.RealtimeTutorModel,
            AiCallKind.RealtimeSession));
        if (string.IsNullOrWhiteSpace(route.ReasoningEffort))
        {
            logger.LogError(
                "OpenAI realtime route resolved without a reasoning effort. model={Model}",
                route.Model);
            throw new RealtimeSessionIssueException("OpenAI Realtime route did not include reasoning effort.");
        }

        if (string.IsNullOrWhiteSpace(options.ApiKey))
        {
            logger.LogError("OpenAI realtime client secret cannot be issued: OPENAI_API_KEY is empty at runtime.");
            throw new RealtimeSessionIssueException("OpenAI API key is not configured.");
        }

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "v1/realtime/client_secrets")
        {
            Content = JsonContent.Create(new OpenAiRealtimeClientSecretRequest(
                new OpenAiRealtimeSessionRequest(
                    "realtime",
                    route.Model,
                    new OpenAiRealtimeReasoning(route.ReasoningEffort),
                    new[] { "audio" },
                    // create_response: false + interrupt_response: true is the
                    // architectural turn-taking guarantee. Server VAD still
                    // commits the user's audio buffer on end-of-turn, but the
                    // server does not auto-create a response — the client must
                    // explicitly send response.create. Result: the tutor
                    // cannot monologue no matter what the instructions drift to.
                    new OpenAiRealtimeAudio(
                        new OpenAiRealtimeAudioInput(
                            new OpenAiRealtimeAudioFormat("audio/pcm", 24_000),
                            new OpenAiRealtimeTurnDetection(
                                "server_vad",
                                0.85,
                                300,
                                1500,
                                CreateResponse: false,
                                InterruptResponse: true)),
                        new OpenAiRealtimeAudioOutput(
                            new OpenAiRealtimeAudioFormat("audio/pcm", 24_000))),
                    BuildInstructions(request.Settings, promptRegistry, logger))))
        };
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            var truncated = errorBody.Length > 500 ? errorBody[..500] : errorBody;
            // The error body is OpenAI's error JSON (code/message), not a secret;
            // the API key is only ever sent in the request header, never logged.
            logger.LogError(
                "OpenAI realtime client_secret request failed. status={Status} model={Model} keyLength={KeyLength} body={Body}",
                (int)response.StatusCode,
                route.Model,
                options.ApiKey.Length,
                truncated);
            throw new RealtimeSessionIssueException(
                $"OpenAI Realtime client secret request failed with status {(int)response.StatusCode}.");
        }

        var body = await response.Content.ReadFromJsonAsync<OpenAiRealtimeClientSecretResponse>(
            cancellationToken);
        var clientSecret = body?.Value ?? body?.ClientSecret?.Value;
        var expiresAt = body?.ExpiresAt ?? body?.ClientSecret?.ExpiresAt;
        var sessionModel = body?.Session?.Model ?? route.Model;
        if (clientSecret is null || expiresAt is null)
        {
            logger.LogError(
                "OpenAI realtime client_secret response was missing a client secret value. model={Model}",
                route.Model);
            throw new RealtimeSessionIssueException("OpenAI Realtime client secret response was invalid.");
        }

        return new RealtimeSessionCredential(
            request.CorrelationId.Value,
            clientSecret,
            sessionModel,
            route.ReasoningEffort,
            DateTimeOffset.FromUnixTimeSeconds(expiresAt.Value),
            request.Settings);
    }

    /// <summary>
    /// Resolves the correct Realtime tutor prompt for the learner's session
    /// intent (activity), renders it with the caller's variables, and returns
    /// the composed system prompt. Falls back to open-practice for unknown or
    /// empty intents so a client with a stale intent name still gets a valid
    /// session instead of a 503.
    /// </summary>
    private static string BuildInstructions(
        RealtimeSessionSettingsContract settings,
        IPromptRegistry promptRegistry,
        ILogger logger)
    {
        var promptRef = ResolvePromptRef(settings);
        var variables = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["targetLanguage"] = settings.TargetLanguage,
            ["proficiencyBand"] = settings.ProficiencyBand,
            ["focusTitle"] = ResolveFocusTitle(settings, promptRef.Id),
            ["dueReviewCount"] = settings.DueReviewCount is > 0
                ? settings.DueReviewCount.Value.ToString(CultureInfo.InvariantCulture)
                : "",
        };

        try
        {
            var rendered = promptRegistry.Render(promptRef, variables);
            return rendered.System ?? "";
        }
        catch (PromptRegistryException exception)
        {
            logger.LogError(
                exception,
                "Realtime tutor prompt render failed. promptId={PromptId} version={Version}",
                promptRef.Id,
                promptRef.Version);
            throw new RealtimeSessionIssueException(
                $"Realtime tutor prompt '{promptRef.Id}' v{promptRef.Version} could not be rendered.");
        }
    }

    /// <summary>
    /// Maps a client-supplied SessionIntent string to the versioned tutor
    /// prompt that governs that activity. Accepts both new snake_case values
    /// (open_practice, guided_lesson, pronunciation_drill, …) and the legacy
    /// short forms (practice, lesson, review) that older clients still send.
    /// Unknown intents fall back to open-practice.
    /// </summary>
    public static PromptRef ResolvePromptRef(RealtimeSessionSettingsContract settings)
    {
        var intent = settings.SessionIntent?.Trim().ToLowerInvariant() ?? "";
        return intent switch
        {
            "open_practice" or "practice" or "" => new PromptRef("realtime-tutor/open-practice", 1),
            "guided_lesson" or "lesson" => new PromptRef("realtime-tutor/guided-lesson", 1),
            "review" => new PromptRef("realtime-tutor/review", 1),
            "pronunciation_drill" => new PromptRef("realtime-tutor/pronunciation-drill", 1),
            "roleplay" => new PromptRef("realtime-tutor/roleplay", 1),
            "mistakes_replay" => new PromptRef("realtime-tutor/mistakes-replay", 1),
            "vocabulary_drill" => new PromptRef("realtime-tutor/vocabulary-drill", 1),
            "listening_practice" => new PromptRef("realtime-tutor/listening-practice", 1),
            "key_language" => new PromptRef("realtime-tutor/key-language", 1),
            _ => new PromptRef("realtime-tutor/open-practice", 1),
        };
    }

    /// <summary>
    /// Some prompts declare focusTitle as required — if the client hasn't
    /// supplied one (which is normal for "start a lesson" surfaces that only
    /// know the general activity), we supply a prompt-appropriate default so
    /// the registry render doesn't fail on a missing required variable.
    /// </summary>
    private static string ResolveFocusTitle(RealtimeSessionSettingsContract settings, string promptId)
    {
        if (!string.IsNullOrWhiteSpace(settings.FocusTitle))
        {
            return settings.FocusTitle.Trim();
        }
        return promptId switch
        {
            "realtime-tutor/guided-lesson" => "today's learning plan",
            "realtime-tutor/roleplay" => "a natural everyday situation",
            "realtime-tutor/key-language" => "the language coming up next",
            _ => "",
        };
    }
}

internal sealed record OpenAiRealtimeClientSecretRequest(
    [property: JsonPropertyName("session")] OpenAiRealtimeSessionRequest Session);

internal sealed record OpenAiRealtimeSessionRequest(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("reasoning")] OpenAiRealtimeReasoning Reasoning,
    [property: JsonPropertyName("output_modalities")] IReadOnlyList<string> OutputModalities,
    [property: JsonPropertyName("audio")] OpenAiRealtimeAudio Audio,
    [property: JsonPropertyName("instructions")] string Instructions);

internal sealed record OpenAiRealtimeReasoning(
    [property: JsonPropertyName("effort")] string Effort);

internal sealed record OpenAiRealtimeAudio(
    [property: JsonPropertyName("input")] OpenAiRealtimeAudioInput Input,
    [property: JsonPropertyName("output")] OpenAiRealtimeAudioOutput Output);

internal sealed record OpenAiRealtimeAudioInput(
    [property: JsonPropertyName("format")] OpenAiRealtimeAudioFormat Format,
    [property: JsonPropertyName("turn_detection")] OpenAiRealtimeTurnDetection TurnDetection);

internal sealed record OpenAiRealtimeAudioOutput(
    [property: JsonPropertyName("format")] OpenAiRealtimeAudioFormat Format);

internal sealed record OpenAiRealtimeAudioFormat(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("rate")] int Rate);

internal sealed record OpenAiRealtimeTurnDetection(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("threshold")] double Threshold,
    [property: JsonPropertyName("prefix_padding_ms")] int PrefixPaddingMs,
    [property: JsonPropertyName("silence_duration_ms")] int SilenceDurationMs,
    [property: JsonPropertyName("create_response")] bool CreateResponse,
    [property: JsonPropertyName("interrupt_response")] bool InterruptResponse);

internal sealed record OpenAiRealtimeClientSecretResponse(
    [property: JsonPropertyName("value")] string? Value,
    [property: JsonPropertyName("expires_at")] long? ExpiresAt,
    [property: JsonPropertyName("client_secret")] OpenAiRealtimeClientSecret? ClientSecret,
    [property: JsonPropertyName("session")] OpenAiRealtimeSession? Session);

internal sealed record OpenAiRealtimeClientSecret(
    [property: JsonPropertyName("value")] string? Value,
    [property: JsonPropertyName("expires_at")] long ExpiresAt);

internal sealed record OpenAiRealtimeSession(
    [property: JsonPropertyName("model")] string? Model);
