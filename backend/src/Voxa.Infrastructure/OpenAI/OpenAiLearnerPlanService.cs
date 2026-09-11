using System.Globalization;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Voxa.Application.Ai;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.OpenAI;

/// <summary>
/// ILearnerPlanService backed by OpenAI Chat Completions. Reads the
/// learner's persistent state, renders the `curriculum-planner/today-plan`
/// prompt with the accumulated evidence, calls the CurriculumModel with
/// `response_format: json_object`, and returns a typed LearnerPlan.
/// Missing learner state (never onboarded) or an empty evidence set both
/// resolve to a safe open-practice plan instead of throwing.
/// </summary>
public sealed class OpenAiLearnerPlanService(
    HttpClient httpClient,
    OpenAiRealtimeOptions options,
    IModelRouter modelRouter,
    IPromptRegistry promptRegistry,
    ILearnerStateRepository repository,
    ILogger<OpenAiLearnerPlanService> logger) : ILearnerPlanService
{
    private static readonly PromptRef PlanPromptRef = new("curriculum-planner/today-plan", 1);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<LearnerPlan> GetTodayPlanAsync(
        TenantId tenantId,
        UserId userId,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var state = await repository.GetAsync(tenantId, userId, cancellationToken);
        if (state is null)
        {
            // Learner has no persistent state yet — safe fallback so the
            // Home Today card still shows something meaningful.
            return SafeOpenPracticeFallback(correlationId.Value, "let's start with open practice so I can hear how you speak.");
        }

        if (string.IsNullOrWhiteSpace(options.ApiKey))
        {
            logger.LogError("Learner plan cannot run: OPENAI_API_KEY is empty at runtime.");
            throw new LearnerPlanException("OpenAI API key is not configured.");
        }

        var route = modelRouter.Resolve(new ModelRouteRequest(
            AiCapability.CurriculumModel,
            AiCallKind.Completion));

        var variables = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["targetLanguage"] = state.Profile.TargetLanguage,
            ["proficiencyBand"] = state.Profile.ProficiencyLevel,
            ["activePlanTitle"] = string.IsNullOrWhiteSpace(state.ActivePlan.Title) ? "none" : state.ActivePlan.Title,
            ["currentLessonTitle"] = string.IsNullOrWhiteSpace(state.CurrentLesson.LessonId) ? "none" : state.CurrentLesson.LessonId,
            ["dueReviewCount"] = state.ReviewQueue.Items.Count.ToString(CultureInfo.InvariantCulture),
            ["recentDebriefs"] = FormatDebriefs(state.TutorEvidence.RecentDebriefs),
        };

        RenderedPrompt rendered;
        try
        {
            rendered = promptRegistry.Render(PlanPromptRef, variables);
        }
        catch (PromptRegistryException exception)
        {
            logger.LogError(
                exception,
                "Learner plan prompt render failed. promptId={PromptId} version={Version}",
                PlanPromptRef.Id,
                PlanPromptRef.Version);
            throw new LearnerPlanException(
                $"Learner plan prompt '{PlanPromptRef.Id}' v{PlanPromptRef.Version} could not be rendered.");
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
                "Learner plan upstream call failed. status={Status} model={Model} body={Body}",
                (int)response.StatusCode,
                route.Model,
                truncated);
            throw new LearnerPlanException(
                $"Learner plan upstream call failed with status {(int)response.StatusCode}.");
        }

        var body = await response.Content.ReadFromJsonAsync<OpenAiChatCompletionResponse>(
            JsonOptions,
            cancellationToken);
        var text = body?.Choices?.FirstOrDefault()?.Message?.Content;
        if (string.IsNullOrWhiteSpace(text))
        {
            logger.LogError("Learner plan upstream call returned no content. model={Model}", route.Model);
            throw new LearnerPlanException("Learner plan upstream call returned no content.");
        }

        LearnerPlanPayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<LearnerPlanPayload>(text, JsonOptions);
        }
        catch (JsonException exception)
        {
            logger.LogError(
                exception,
                "Learner plan output was not valid JSON. model={Model} body={Body}",
                route.Model,
                text.Length > 500 ? text[..500] : text);
            throw new LearnerPlanException("Learner plan output was not valid JSON.");
        }

        if (payload is null)
        {
            throw new LearnerPlanException("Learner plan output was empty.");
        }

        return payload.ToPlan(correlationId.Value);
    }

    private static string FormatDebriefs(IReadOnlyList<RecordedDebrief> debriefs)
    {
        if (debriefs.Count == 0)
        {
            return "(no debriefs recorded yet)";
        }

        var builder = new StringBuilder(debriefs.Count * 128);
        for (var index = 0; index < debriefs.Count; index++)
        {
            var debrief = debriefs[index];
            builder.Append((index + 1).ToString(CultureInfo.InvariantCulture));
            builder.Append(". [");
            builder.Append(debrief.RecordedAt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
            builder.Append("] ");
            builder.AppendLine(debrief.Summary);
            if (debrief.RecurringMistakes.Count > 0)
            {
                builder.Append("   Recurring: ");
                builder.AppendLine(string.Join("; ", debrief.RecurringMistakes.Select(m =>
                    $"{m.Pattern} ({m.Severity}) — \"{m.Example}\"")));
            }
            if (debrief.UsefulPhrases.Count > 0)
            {
                builder.Append("   Useful phrases: ");
                builder.AppendLine(string.Join("; ", debrief.UsefulPhrases));
            }
            if (debrief.PronunciationNotes.Count > 0)
            {
                builder.Append("   Pronunciation: ");
                builder.AppendLine(string.Join("; ", debrief.PronunciationNotes));
            }
            builder.Append("   Recommended next (from that session): ");
            builder.Append(debrief.RecommendedNextDrill.ActivityIntent);
            if (!string.IsNullOrWhiteSpace(debrief.RecommendedNextDrill.FocusTitle))
            {
                builder.Append(" — ");
                builder.Append(debrief.RecommendedNextDrill.FocusTitle);
            }
            builder.AppendLine();
        }
        return builder.ToString();
    }

    private static LearnerPlan SafeOpenPracticeFallback(string correlationId, string reason)
    {
        return new LearnerPlan(
            correlationId,
            new RecommendedSession("open_practice", string.Empty, reason),
            Array.Empty<string>());
    }
}

// MARK: - Wire types

internal sealed record LearnerPlanPayload(
    RecommendedSessionPayload? RecommendedSession,
    IReadOnlyList<string>? FocusAreas)
{
    public LearnerPlan ToPlan(string correlationId)
    {
        return new LearnerPlan(
            correlationId,
            new RecommendedSession(
                RecommendedSession?.ActivityIntent ?? "open_practice",
                RecommendedSession?.FocusTitle ?? string.Empty,
                RecommendedSession?.Reason ?? string.Empty),
            FocusAreas ?? Array.Empty<string>());
    }
}

internal sealed record RecommendedSessionPayload(
    string? ActivityIntent,
    string? FocusTitle,
    string? Reason);
