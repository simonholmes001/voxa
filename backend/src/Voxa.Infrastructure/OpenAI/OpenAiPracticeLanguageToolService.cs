using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Voxa.Application.Ai;
using Voxa.Application.Practice;

namespace Voxa.Infrastructure.OpenAI;

public sealed class OpenAiPracticeLanguageToolService(
    HttpClient httpClient,
    OpenAiRealtimeOptions options,
    IModelRouter modelRouter,
    ILogger<OpenAiPracticeLanguageToolService> logger) : IPracticeLanguageToolService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<AskAnythingResult> AskAnythingAsync(
        AskAnythingCommand command,
        CancellationToken cancellationToken)
    {
        var payload = await CompleteJsonAsync<AskAnythingPayload>(
            PromptForAskAnything(command),
            command.CorrelationId.Value,
            cancellationToken);

        return new AskAnythingResult(
            payload.Answer ?? string.Empty,
            (payload.Examples ?? Array.Empty<PhraseExamplePayload>())
                .Take(4)
                .Select(example => new PhraseExample(
                    example.Source ?? string.Empty,
                    example.Target ?? string.Empty,
                    example.Note ?? string.Empty))
                .ToArray());
    }

    public async Task<TranslationResult> TranslateAsync(
        TranslationCommand command,
        CancellationToken cancellationToken)
    {
        var payload = await CompleteJsonAsync<TranslationPayload>(
            PromptForTranslation(command),
            command.CorrelationId.Value,
            cancellationToken);

        return new TranslationResult(
            payload.SourceLanguage ?? command.SourceLanguage ?? "auto",
            payload.TargetLanguage ?? command.TargetLanguage,
            payload.TranslatedText ?? string.Empty,
            payload.Notes ?? string.Empty);
    }

    public async Task<ImageTranslationResult> TranslateImageAsync(
        ImageTranslationCommand command,
        CancellationToken cancellationToken)
    {
        var payload = await CompleteJsonAsync<ImageTranslationPayload>(
            PromptForImageTranslation(command),
            command.CorrelationId.Value,
            cancellationToken,
            new OpenAiResponseInputImage(
                "input_image",
                $"data:{command.MimeType};base64,{command.ImageBase64}",
                "auto"));

        return new ImageTranslationResult(
            payload.DetectedText ?? string.Empty,
            payload.SourceLanguage ?? command.SourceLanguage ?? "auto",
            payload.TargetLanguage ?? command.TargetLanguage,
            payload.TranslatedText ?? string.Empty,
            payload.Notes ?? string.Empty);
    }

    public async Task<VocabularyQuizResult> CreateVocabularyQuizAsync(
        VocabularyQuizCommand command,
        CancellationToken cancellationToken)
    {
        var payload = await CompleteJsonAsync<VocabularyQuizPayload>(
            PromptForVocabularyQuiz(command),
            command.CorrelationId.Value,
            cancellationToken);

        return new VocabularyQuizResult(
            (payload.Items ?? Array.Empty<VocabularyQuizItemPayload>())
                .Where(item => item.Choices is { Count: >= 2 })
                .Take(command.Count)
                .Select(item => new VocabularyQuizItem(
                    item.Prompt ?? string.Empty,
                    item.Choices ?? Array.Empty<string>(),
                    Math.Clamp(item.CorrectChoiceIndex ?? 0, 0, (item.Choices?.Count ?? 1) - 1),
                    item.Explanation ?? string.Empty))
                .ToArray());
    }

    private async Task<TPayload> CompleteJsonAsync<TPayload>(
        string prompt,
        string correlationId,
        CancellationToken cancellationToken,
        OpenAiResponseInputImage? image = null)
    {
        if (string.IsNullOrWhiteSpace(options.ApiKey))
        {
            logger.LogError("Practice language tools cannot run: OPENAI_API_KEY is empty at runtime.");
            throw new PracticeLanguageToolException("OpenAI API key is not configured.");
        }

        var route = modelRouter.Resolve(new ModelRouteRequest(
            AiCapability.UtilityModel,
            AiCallKind.Completion));

        var content = new List<object>
        {
            new OpenAiResponseInputText("input_text", prompt),
        };
        if (image is not null)
        {
            content.Add(image);
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, "v1/responses")
        {
            Content = JsonContent.Create(
                new OpenAiResponsesRequest(
                    route.Model,
                    new[]
                    {
                        new OpenAiResponseInputMessage(
                            "message",
                            "user",
                            content),
                    }),
                options: JsonOptions),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);

        HttpResponseMessage response;
        try
        {
            response = await httpClient.SendAsync(request, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            logger.LogError(
                exception,
                "Practice language tool upstream call timed out. model={Model} correlationId={CorrelationId}",
                route.Model,
                correlationId);
            throw new PracticeLanguageToolException("Language tool upstream call timed out.");
        }
        catch (HttpRequestException exception)
        {
            logger.LogError(
                exception,
                "Practice language tool upstream transport failed. model={Model} correlationId={CorrelationId}",
                route.Model,
                correlationId);
            throw new PracticeLanguageToolException("Language tool upstream transport failed.");
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                logger.LogError(
                    "Practice language tool upstream call failed. status={Status} model={Model} correlationId={CorrelationId}",
                    (int)response.StatusCode,
                    route.Model,
                    correlationId);
                throw new PracticeLanguageToolException("Language tool upstream call failed.");
            }

            OpenAiResponsesResponse? responseBody;
            try
            {
                responseBody = await response.Content.ReadFromJsonAsync<OpenAiResponsesResponse>(
                    JsonOptions,
                    cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (OperationCanceledException exception)
            {
                logger.LogError(
                    exception,
                    "Practice language tool upstream response read timed out. model={Model} correlationId={CorrelationId}",
                    route.Model,
                    correlationId);
                throw new PracticeLanguageToolException("Language tool upstream response read timed out.");
            }
            catch (JsonException exception)
            {
                logger.LogError(
                    exception,
                    "Practice language tool upstream response envelope was not valid JSON. model={Model} correlationId={CorrelationId}",
                    route.Model,
                    correlationId);
                throw new PracticeLanguageToolException("Language tool upstream response envelope was not valid JSON.");
            }

            var text = responseBody?.OutputText ?? ExtractOutputText(responseBody);
            if (string.IsNullOrWhiteSpace(text))
            {
                logger.LogError(
                    "Practice language tool upstream call returned no output. model={Model} correlationId={CorrelationId}",
                    route.Model,
                    correlationId);
                throw new PracticeLanguageToolException("Language tool upstream call returned no output.");
            }

            try
            {
                return JsonSerializer.Deserialize<TPayload>(StripJsonFence(text), JsonOptions)
                    ?? throw new PracticeLanguageToolException("Language tool output was empty.");
            }
            catch (JsonException exception)
            {
                logger.LogError(
                    exception,
                    "Practice language tool output was not valid JSON. model={Model} correlationId={CorrelationId}",
                    route.Model,
                    correlationId);
                throw new PracticeLanguageToolException("Language tool output was not valid JSON.");
            }
        }
    }

    private static string StripJsonFence(string text)
    {
        var trimmed = text.Trim();
        if (!trimmed.StartsWith("```", StringComparison.Ordinal))
        {
            return trimmed;
        }

        var firstNewline = trimmed.IndexOf('\n');
        var lastFence = trimmed.LastIndexOf("```", StringComparison.Ordinal);
        if (firstNewline < 0 || lastFence <= firstNewline)
        {
            return trimmed;
        }

        return trimmed[(firstNewline + 1)..lastFence].Trim();
    }

    private static string? ExtractOutputText(OpenAiResponsesResponse? response)
    {
        return response?.Output?
            .SelectMany(item => item.Content ?? Array.Empty<OpenAiResponsesOutputContent>())
            .FirstOrDefault(content => string.Equals(content.Type, "output_text", StringComparison.Ordinal))?
            .Text;
    }

    private static string PromptForAskAnything(AskAnythingCommand command)
    {
        return $$"""
        You are Voxa, a precise language tutor.
        Answer the learner's question about {{command.TargetLanguage}}.
        Native language: {{command.NativeLanguage ?? "not specified"}}.
        Question: {{command.Question}}

        Return only JSON:
        {
          "answer": "short direct answer",
          "examples": [
            { "source": "learner phrase or cue", "target": "natural target-language wording", "note": "brief usage note" }
          ]
        }
        """;
    }

    private static string PromptForTranslation(TranslationCommand command)
    {
        return $$"""
        Translate into {{command.TargetLanguage}}.
        Source language: {{command.SourceLanguage ?? "detect automatically"}}.
        Text: {{command.Text}}

        Return only JSON:
        {
          "sourceLanguage": "detected or supplied source language",
          "targetLanguage": "{{command.TargetLanguage}}",
          "translatedText": "translation",
          "notes": "brief note about tone, register, or ambiguity"
        }
        """;
    }

    private static string PromptForImageTranslation(ImageTranslationCommand command)
    {
        return $$"""
        Read the text in the attached image and translate it into {{command.TargetLanguage}}.
        Source language: {{command.SourceLanguage ?? "detect automatically"}}.
        If there is no readable text, say that clearly.

        Return only JSON:
        {
          "detectedText": "text found in the image",
          "sourceLanguage": "detected or supplied source language",
          "targetLanguage": "{{command.TargetLanguage}}",
          "translatedText": "translation",
          "notes": "brief context or uncertainty note"
        }
        """;
    }

    private static string PromptForVocabularyQuiz(VocabularyQuizCommand command)
    {
        return $$"""
        Create a vocabulary multiple-choice quiz for a learner of {{command.TargetLanguage}}.
        Level: {{command.ProficiencyBand}}.
        Focus: {{command.Focus ?? "useful everyday vocabulary"}}.
        Number of questions: {{command.Count}}.

        Return only JSON:
        {
          "items": [
            {
              "prompt": "question prompt",
              "choices": ["choice A", "choice B", "choice C", "choice D"],
              "correctChoiceIndex": 0,
              "explanation": "brief explanation"
            }
          ]
        }
        """;
    }
}

internal sealed record OpenAiResponsesRequest(
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("input")] IReadOnlyList<OpenAiResponseInputMessage> Input);

internal sealed record OpenAiResponseInputMessage(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("role")] string Role,
    [property: JsonPropertyName("content")] IReadOnlyList<object> Content);

internal sealed record OpenAiResponseInputText(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("text")] string Text);

internal sealed record OpenAiResponseInputImage(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("image_url")] string ImageUrl,
    [property: JsonPropertyName("detail")] string Detail);

internal sealed record OpenAiResponsesResponse(
    [property: JsonPropertyName("output_text")] string? OutputText,
    [property: JsonPropertyName("output")] IReadOnlyList<OpenAiResponsesOutputItem>? Output);

internal sealed record OpenAiResponsesOutputItem(
    [property: JsonPropertyName("content")] IReadOnlyList<OpenAiResponsesOutputContent>? Content);

internal sealed record OpenAiResponsesOutputContent(
    [property: JsonPropertyName("type")] string? Type,
    [property: JsonPropertyName("text")] string? Text);

internal sealed record AskAnythingPayload(
    string? Answer,
    IReadOnlyList<PhraseExamplePayload>? Examples);

internal sealed record PhraseExamplePayload(
    string? Source,
    string? Target,
    string? Note);

internal sealed record TranslationPayload(
    string? SourceLanguage,
    string? TargetLanguage,
    string? TranslatedText,
    string? Notes);

internal sealed record ImageTranslationPayload(
    string? DetectedText,
    string? SourceLanguage,
    string? TargetLanguage,
    string? TranslatedText,
    string? Notes);

internal sealed record VocabularyQuizPayload(
    IReadOnlyList<VocabularyQuizItemPayload>? Items);

internal sealed record VocabularyQuizItemPayload(
    string? Prompt,
    IReadOnlyList<string>? Choices,
    int? CorrectChoiceIndex,
    string? Explanation);
