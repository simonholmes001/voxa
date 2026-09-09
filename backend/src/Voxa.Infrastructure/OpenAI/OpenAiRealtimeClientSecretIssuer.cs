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
                    BuildInstructions(request.Settings))))
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

    private static string BuildInstructions(RealtimeSessionSettingsContract settings)
    {
        var baseInstructions = string.Join(
            " ",
            "You are Voxa, a spoken language-learning tutor.",
            $"Target language: {settings.TargetLanguage}.",
            $"Learner level: {settings.ProficiencyBand}.",
            "Keep replies short enough for a voice conversation.",
            "Coach through natural conversation, ask one question at a time, and correct gently after the learner answers.",
            // Pedagogical handoff protocol. Also doubles as a natural,
            // teachable phrase — polite yielding is real target-language skill.
            $"End every substantive turn with a short, natural handoff phrase in {settings.TargetLanguage} (for example \"À toi\" in French, \"Tu turno\" in Spanish, \"Du bist dran\" in German, or the equivalent in your target language). After the handoff, stop and wait for the learner to reply.");

        return settings.SessionIntent?.ToLowerInvariant() switch
        {
            "lesson" => string.Join(
                " ",
                baseInstructions,
                $"Run an assistant-led lesson focused on {TextOrDefault(settings.FocusTitle, "today's learning plan")}.",
                "Structure the session as warm-up, key phrases, short roleplay, correction, and retry."),
            "review" => string.Join(
                " ",
                baseInstructions,
                string.IsNullOrWhiteSpace(settings.FocusTitle)
                    ? "Focus the review on recent tutor evidence."
                    : $"Focus the review on {settings.FocusTitle.Trim()}.",
                settings.DueReviewCount is > 0
                    ? $"Prioritize the {settings.DueReviewCount.Value} review items currently due."
                    : "Run a review conversation using recent mistakes, weak words, and pronunciation targets.",
                "Ask the learner to produce language before explaining."),
            _ => string.Join(
                " ",
                baseInstructions,
                "Run open speaking practice adapted to the learner's goal and current level.")
        };
    }

    private static string TextOrDefault(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
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
