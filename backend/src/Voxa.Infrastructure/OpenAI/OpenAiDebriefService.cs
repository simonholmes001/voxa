using System.Globalization;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Voxa.Application.Ai;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.OpenAI;

/// <summary>
/// IDebriefService backed by the OpenAI Chat Completions API. Resolves the
/// `realtime-tutor/debrief.v1` prompt through the registry, renders it with the
/// session's target language / band / activity + a transcript, calls the
/// AssessmentModel with `response_format: json_object`, and parses the returned
/// structured JSON into a SessionDebrief.
/// </summary>
public sealed class OpenAiDebriefService(
    HttpClient httpClient,
    OpenAiRealtimeOptions options,
    IModelRouter modelRouter,
    IPromptRegistry promptRegistry,
    ILogger<OpenAiDebriefService> logger) : IDebriefService
{
    private static readonly PromptRef DebriefPromptRef = new("realtime-tutor/debrief", 1);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<SessionDebrief> GenerateDebriefAsync(
        SessionDebriefRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.ApiKey))
        {
            logger.LogError("Debrief cannot run: OPENAI_API_KEY is empty at runtime.");
            throw new SessionDebriefException("OpenAI API key is not configured.");
        }

        var route = modelRouter.Resolve(new ModelRouteRequest(
            AiCapability.AssessmentModel,
            AiCallKind.Completion));

        var variables = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["targetLanguage"] = request.Settings.TargetLanguage,
            ["proficiencyBand"] = request.Settings.ProficiencyBand,
            ["sessionActivity"] = request.Settings.SessionIntent ?? "open_practice",
            ["transcript"] = FormatTranscript(request.Transcript),
        };

        RenderedPrompt rendered;
        try
        {
            rendered = promptRegistry.Render(DebriefPromptRef, variables);
        }
        catch (PromptRegistryException exception)
        {
            logger.LogError(
                exception,
                "Debrief prompt render failed. promptId={PromptId} version={Version}",
                DebriefPromptRef.Id,
                DebriefPromptRef.Version);
            throw new SessionDebriefException(
                $"Debrief prompt '{DebriefPromptRef.Id}' v{DebriefPromptRef.Version} could not be rendered.");
        }

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "v1/chat/completions")
        {
            Content = JsonContent.Create(new OpenAiChatCompletionRequest(
                route.Model,
                new[]
                {
                    new OpenAiChatMessage("system", rendered.System ?? string.Empty),
                    new OpenAiChatMessage("user", rendered.User ?? string.Empty),
                },
                new OpenAiChatResponseFormat("json_object")),
                options: JsonOptions),
        };
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);
            var truncated = errorBody.Length > 500 ? errorBody[..500] : errorBody;
            logger.LogError(
                "Debrief upstream call failed. status={Status} model={Model} body={Body}",
                (int)response.StatusCode,
                route.Model,
                truncated);
            throw new SessionDebriefException(
                $"Debrief upstream call failed with status {(int)response.StatusCode}.");
        }

        var body = await response.Content.ReadFromJsonAsync<OpenAiChatCompletionResponse>(
            JsonOptions,
            cancellationToken);
        var text = body?.Choices?.FirstOrDefault()?.Message?.Content;
        if (string.IsNullOrWhiteSpace(text))
        {
            logger.LogError("Debrief upstream call returned no content. model={Model}", route.Model);
            throw new SessionDebriefException("Debrief upstream call returned no content.");
        }

        DebriefPayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<DebriefPayload>(text, JsonOptions);
        }
        catch (JsonException exception)
        {
            logger.LogError(
                exception,
                "Debrief output was not valid JSON. model={Model} body={Body}",
                route.Model,
                text.Length > 500 ? text[..500] : text);
            throw new SessionDebriefException("Debrief output was not valid JSON.");
        }

        if (payload is null)
        {
            throw new SessionDebriefException("Debrief output was empty.");
        }

        return payload.ToDebrief(request.CorrelationId);
    }

    private static string FormatTranscript(IReadOnlyList<TranscriptTurn> transcript)
    {
        if (transcript.Count == 0)
        {
            return "(no turns captured)";
        }

        var builder = new StringBuilder(transcript.Count * 64);
        for (var index = 0; index < transcript.Count; index++)
        {
            var turn = transcript[index];
            var role = string.Equals(turn.Role, TranscriptTurn.LearnerRole, StringComparison.OrdinalIgnoreCase)
                ? "learner"
                : string.Equals(turn.Role, TranscriptTurn.TutorRole, StringComparison.OrdinalIgnoreCase)
                    ? "tutor"
                    : turn.Role;
            builder.Append((index + 1).ToString(CultureInfo.InvariantCulture));
            builder.Append(". [");
            builder.Append(role);
            builder.Append("] ");
            builder.AppendLine(turn.Text.Trim());
        }
        return builder.ToString();
    }
}

// MARK: - Wire types

internal sealed record OpenAiChatCompletionRequest(
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("messages")] IReadOnlyList<OpenAiChatMessage> Messages,
    [property: JsonPropertyName("response_format")] OpenAiChatResponseFormat ResponseFormat);

internal sealed record OpenAiChatMessage(
    [property: JsonPropertyName("role")] string Role,
    [property: JsonPropertyName("content")] string Content);

internal sealed record OpenAiChatResponseFormat(
    [property: JsonPropertyName("type")] string Type);

internal sealed record OpenAiChatCompletionResponse(
    [property: JsonPropertyName("choices")] IReadOnlyList<OpenAiChatChoice>? Choices);

internal sealed record OpenAiChatChoice(
    [property: JsonPropertyName("message")] OpenAiChatMessage? Message);

// Structured debrief JSON we ask the model to emit.
internal sealed record DebriefPayload(
    string? Summary,
    IReadOnlyList<RecurringMistakePayload>? RecurringMistakes,
    IReadOnlyList<string>? UsefulPhrases,
    IReadOnlyList<string>? PronunciationNotes,
    RecommendedDrillPayload? RecommendedNextDrill)
{
    public SessionDebrief ToDebrief(CorrelationId correlationId)
    {
        return new SessionDebrief(
            correlationId.Value,
            Summary ?? string.Empty,
            (RecurringMistakes ?? Array.Empty<RecurringMistakePayload>())
                .Select(payload => new DebriefRecurringMistake(
                    payload.Pattern ?? string.Empty,
                    payload.Example ?? string.Empty,
                    payload.Severity ?? "low"))
                .ToArray(),
            UsefulPhrases ?? Array.Empty<string>(),
            PronunciationNotes ?? Array.Empty<string>(),
            new DebriefRecommendedDrill(
                RecommendedNextDrill?.ActivityIntent ?? "open_practice",
                RecommendedNextDrill?.FocusTitle ?? string.Empty,
                RecommendedNextDrill?.Reason ?? string.Empty));
    }
}

internal sealed record RecurringMistakePayload(string? Pattern, string? Example, string? Severity);

internal sealed record RecommendedDrillPayload(string? ActivityIntent, string? FocusTitle, string? Reason);
