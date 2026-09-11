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
/// ICourseAuthorService backed by OpenAI Chat Completions. Renders the
/// curriculum-planner/author-course.v1 prompt with the learner's onboarding
/// profile and (on a re-mint) the existing course + completed lessons +
/// recent debrief evidence + the free-text reassessment request. Parses
/// the structured JSON output into an ActiveLearningPlan with 20–30
/// PlannedLessons ready to persist.
/// </summary>
public sealed class OpenAiCourseAuthorService(
    HttpClient httpClient,
    OpenAiRealtimeOptions options,
    IModelRouter modelRouter,
    IPromptRegistry promptRegistry,
    ILogger<OpenAiCourseAuthorService> logger) : ICourseAuthorService
{
    private static readonly PromptRef AuthorPromptRef = new("curriculum-planner/author-course", 1);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public async Task<ActiveLearningPlan> AuthorCourseAsync(
        CourseAuthorRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.ApiKey))
        {
            logger.LogError("Course author cannot run: OPENAI_API_KEY is empty at runtime.");
            throw new CourseAuthorException("OpenAI API key is not configured.");
        }

        var route = modelRouter.Resolve(new ModelRouteRequest(
            AiCapability.CurriculumModel,
            AiCallKind.Completion));

        var variables = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["targetLanguage"] = request.Profile.TargetLanguage,
            ["nativeLanguage"] = request.Profile.NativeLanguage,
            ["proficiencyBand"] = request.Profile.ProficiencyLevel,
            ["dailyMinutes"] = request.Profile.DailyMinutes.ToString(CultureInfo.InvariantCulture),
            ["goals"] = FormatGoals(request.Profile.Goals),
            ["existingCourse"] = FormatExistingCourse(request.ExistingCourse),
            ["completedLessons"] = FormatCompletedLessons(request.ExistingCourse, request.CompletedLessonIds),
            ["recentDebriefs"] = FormatDebriefs(request.RecentDebriefs),
            ["reassessmentRequest"] = string.IsNullOrWhiteSpace(request.ReassessmentRequest)
                ? "(none — initial mint)"
                : request.ReassessmentRequest,
        };

        RenderedPrompt rendered;
        try
        {
            rendered = promptRegistry.Render(AuthorPromptRef, variables);
        }
        catch (PromptRegistryException exception)
        {
            logger.LogError(
                exception,
                "Course author prompt render failed. promptId={PromptId} version={Version}",
                AuthorPromptRef.Id,
                AuthorPromptRef.Version);
            throw new CourseAuthorException(
                $"Course author prompt '{AuthorPromptRef.Id}' v{AuthorPromptRef.Version} could not be rendered.");
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
                "Course author upstream call failed. status={Status} model={Model} body={Body}",
                (int)response.StatusCode,
                route.Model,
                truncated);
            throw new CourseAuthorException(
                $"Course author upstream call failed with status {(int)response.StatusCode}.");
        }

        var body = await response.Content.ReadFromJsonAsync<OpenAiChatCompletionResponse>(
            JsonOptions,
            cancellationToken);
        var text = body?.Choices?.FirstOrDefault()?.Message?.Content;
        if (string.IsNullOrWhiteSpace(text))
        {
            logger.LogError("Course author returned no content. model={Model}", route.Model);
            throw new CourseAuthorException("Course author returned no content.");
        }

        CourseAuthorPayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<CourseAuthorPayload>(text, JsonOptions);
        }
        catch (JsonException exception)
        {
            logger.LogError(
                exception,
                "Course author output was not valid JSON. model={Model} body={Body}",
                route.Model,
                text.Length > 500 ? text[..500] : text);
            throw new CourseAuthorException("Course author output was not valid JSON.");
        }

        if (payload is null || payload.Lessons is null || payload.Lessons.Count == 0)
        {
            throw new CourseAuthorException("Course author output had no lessons.");
        }

        ValidatePayloadOrThrow(payload, route.Model);

        var plan = payload.ToActivePlan(request.ExistingCourse, request.CompletedLessonIds);

        // Deterministic progress preservation. The prompt asks the model
        // to keep completed lesson titles across a re-mint (matching the
        // old title, possibly slightly refined). Title-match is best-effort
        // — a punctuation change would lose the id. Aggressive
        // normalisation is done inside ToActivePlan; here we verify the
        // resulting plan carries every completed id through as Completed,
        // and refuse the re-mint if any drop. Otherwise a refined title
        // would silently regress the learner's progress.
        EnsureCompletedLessonsPreservedOrThrow(plan, request.CompletedLessonIds, route.Model);

        return plan;
    }

    /// <summary>
    /// Rejects course payloads that don't meet the contract declared in
    /// author-course.v1.yaml (20–30 lessons, each with a non-empty title
    /// and learningObjective, distinct positive order values, and
    /// estimatedMinutes in [5, 60]). Since `response_format` on the OpenAI
    /// call is `json_object` — not `json_schema` — the schema in the yaml
    /// is documentation for the model, not an enforced envelope. Without
    /// this server-side gate a partial or oversized response persists as
    /// the learner's real course.
    /// </summary>
    private void ValidatePayloadOrThrow(CourseAuthorPayload payload, string model)
    {
        const int minLessons = 20;
        const int maxLessons = 30;
        const int minMinutes = 5;
        const int maxMinutes = 60;

        var kept = new List<CourseAuthorLessonPayload>((payload.Lessons ?? []).Count);
        var seenOrders = new HashSet<int>();
        foreach (var lesson in payload.Lessons ?? [])
        {
            if (lesson is null)
            {
                continue;
            }
            if (string.IsNullOrWhiteSpace(lesson.Title) || string.IsNullOrWhiteSpace(lesson.LearningObjective))
            {
                logger.LogWarning(
                    "course.author.validation blank title or objective. model={Model}",
                    model);
                throw new CourseAuthorException("Course author output had a lesson with a blank title or objective.");
            }
            if (lesson.Order is null || lesson.Order <= 0)
            {
                logger.LogWarning(
                    "course.author.validation missing/non-positive order. model={Model}",
                    model);
                throw new CourseAuthorException("Course author output had a lesson with missing or non-positive order.");
            }
            if (!seenOrders.Add(lesson.Order.Value))
            {
                logger.LogWarning(
                    "course.author.validation duplicate order={Order}. model={Model}",
                    lesson.Order,
                    model);
                throw new CourseAuthorException($"Course author output had a duplicate order value ({lesson.Order}).");
            }
            if (lesson.EstimatedMinutes is null
                || lesson.EstimatedMinutes < minMinutes
                || lesson.EstimatedMinutes > maxMinutes)
            {
                logger.LogWarning(
                    "course.author.validation estimatedMinutes={EstimatedMinutes} out of range. model={Model}",
                    lesson.EstimatedMinutes,
                    model);
                throw new CourseAuthorException(
                    $"Course author output had estimatedMinutes ({lesson.EstimatedMinutes}) outside {minMinutes}..{maxMinutes}.");
            }
            kept.Add(lesson);
        }

        if (kept.Count < minLessons || kept.Count > maxLessons)
        {
            logger.LogWarning(
                "course.author.validation count={Count} outside {Min}..{Max}. model={Model}",
                kept.Count,
                minLessons,
                maxLessons,
                model);
            throw new CourseAuthorException(
                $"Course author output had {kept.Count} lessons, outside the required {minLessons}..{maxLessons}.");
        }
    }

    /// <summary>
    /// Guarantees the caller's completed-lesson ids each surface as
    /// Completed in the returned plan. When they don't, the model has
    /// dropped or renamed a completed lesson in a way that ToActivePlan's
    /// title-match couldn't recover — reassessment would silently regress
    /// the learner's progress. Throwing here lets the caller retry or
    /// surface the failure rather than persist a plan with holes.
    /// </summary>
    private void EnsureCompletedLessonsPreservedOrThrow(
        ActiveLearningPlan plan,
        IReadOnlyList<string> completedLessonIds,
        string model)
    {
        if (completedLessonIds.Count == 0)
        {
            return;
        }
        var completedInPlan = plan.Lessons
            .Where(lesson => lesson.Status == PlannedLessonStatus.Completed)
            .Select(lesson => lesson.LessonId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var missing = completedLessonIds
            .Where(id => !completedInPlan.Contains(id))
            .ToArray();
        if (missing.Length > 0)
        {
            logger.LogWarning(
                "course.author.validation completed ids dropped after re-mint. missingCount={Count} model={Model}",
                missing.Length,
                model);
            throw new CourseAuthorException(
                $"Course author output did not preserve {missing.Length} completed lesson(s) after re-mint.");
        }
    }

    private static string FormatGoals(IReadOnlyList<string> goals)
    {
        return goals.Count == 0 ? "(none stated)" : string.Join("; ", goals);
    }

    private static string FormatExistingCourse(ActiveLearningPlan? plan)
    {
        if (plan is null || plan.Lessons.Count == 0)
        {
            return "(none — initial mint)";
        }

        var builder = new StringBuilder(plan.Lessons.Count * 96);
        builder.Append("Course: ");
        builder.AppendLine(plan.Title);
        foreach (var lesson in plan.Lessons.OrderBy(lesson => lesson.Order))
        {
            builder.Append(lesson.Order.ToString(CultureInfo.InvariantCulture));
            builder.Append(". [");
            builder.Append(lesson.Status);
            builder.Append("] ");
            builder.Append(lesson.Title);
            builder.Append(" — ");
            builder.AppendLine(lesson.LearningObjective);
        }
        return builder.ToString();
    }

    private static string FormatCompletedLessons(
        ActiveLearningPlan? existingCourse,
        IReadOnlyList<string> completedLessonIds)
    {
        if (completedLessonIds.Count == 0)
        {
            return "(none)";
        }

        var existingById = existingCourse?.Lessons.ToDictionary(lesson => lesson.LessonId, lesson => lesson);
        var builder = new StringBuilder(completedLessonIds.Count * 64);
        foreach (var id in completedLessonIds)
        {
            if (existingById is not null && existingById.TryGetValue(id, out var lesson))
            {
                builder.Append("- ");
                builder.Append(lesson.Title);
                builder.Append(" — ");
                builder.AppendLine(lesson.LearningObjective);
            }
            else
            {
                builder.Append("- ");
                builder.AppendLine(id);
            }
        }
        return builder.ToString();
    }

    private static string FormatDebriefs(IReadOnlyList<RecordedDebrief> debriefs)
    {
        if (debriefs.Count == 0)
        {
            return "(no debriefs yet)";
        }
        var builder = new StringBuilder(debriefs.Count * 96);
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
                    $"{m.Pattern} ({m.Severity})")));
            }
        }
        return builder.ToString();
    }
}

// MARK: - Wire types

internal sealed record CourseAuthorPayload(
    string? CourseTitle,
    IReadOnlyList<CourseAuthorLessonPayload>? Lessons)
{
    /// <summary>
    /// Converts the model's structured JSON into an ActiveLearningPlan.
    /// Assigns lesson IDs by re-using the existing course's ID for titles
    /// that clearly match (case-insensitive), so completed lessons keep
    /// their ID across a re-mint and the CompletedLessonIds referring to
    /// the old course stay valid. Marks the first non-completed lesson
    /// as Current; earlier lessons matching a completed ID stay Completed.
    /// </summary>
    public ActiveLearningPlan ToActivePlan(
        ActiveLearningPlan? existingCourse,
        IReadOnlyList<string> completedLessonIds)
    {
        var completed = new HashSet<string>(completedLessonIds, StringComparer.OrdinalIgnoreCase);

        // Build the reuse dictionary keyed by an aggressively-normalised
        // title (case-folded, punctuation-stripped, whitespace-collapsed).
        // The prompt says the model may "slightly refine" completed
        // lesson titles across a re-mint; the raw ordinal-case dictionary
        // used before would drop the id on any punctuation or spacing
        // change and silently regress the learner's progress.
        var existingByNormalisedTitle = existingCourse?.Lessons
            .GroupBy(lesson => NormaliseTitleForMatch(lesson.Title), StringComparer.Ordinal)
            .Where(group => !string.IsNullOrEmpty(group.Key))
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);

        var ordered = (Lessons ?? [])
            .Where(lesson => !string.IsNullOrWhiteSpace(lesson.Title))
            .OrderBy(lesson => lesson.Order ?? int.MaxValue)
            .ToArray();

        var lessons = new List<PlannedLesson>(ordered.Length);
        var markedCurrent = false;
        for (var index = 0; index < ordered.Length; index++)
        {
            var payload = ordered[index];
            var order = payload.Order ?? (index + 1);
            var estimatedMinutes = payload.EstimatedMinutes ?? 15;
            var title = payload.Title!.Trim();
            var objective = (payload.LearningObjective ?? string.Empty).Trim();

            // Re-use the existing lesson's ID when the normalised title
            // matches, so CompletedLessonIds from the old course still
            // resolve even if the model refined punctuation or spacing.
            string lessonId;
            var normalisedTitle = NormaliseTitleForMatch(title);
            if (existingByNormalisedTitle is not null
                && !string.IsNullOrEmpty(normalisedTitle)
                && existingByNormalisedTitle.TryGetValue(normalisedTitle, out var existing))
            {
                lessonId = existing.LessonId;
            }
            else
            {
                lessonId = Guid.NewGuid().ToString("N");
            }

            PlannedLessonStatus status;
            if (completed.Contains(lessonId))
            {
                status = PlannedLessonStatus.Completed;
            }
            else if (!markedCurrent)
            {
                status = PlannedLessonStatus.Current;
                markedCurrent = true;
            }
            else
            {
                status = PlannedLessonStatus.Pending;
            }

            lessons.Add(new PlannedLesson(lessonId, title, objective, order, estimatedMinutes, status));
        }

        var planId = string.IsNullOrWhiteSpace(existingCourse?.PlanId)
            ? Guid.NewGuid().ToString("N")
            : existingCourse!.PlanId;
        var title2 = string.IsNullOrWhiteSpace(CourseTitle)
            ? (existingCourse?.Title ?? "Your course")
            : CourseTitle!.Trim();

        return new ActiveLearningPlan(planId, title2, existingCourse?.KnowledgeUnitIds ?? [], lessons);
    }

    /// <summary>
    /// Aggressive normalisation used to match a lesson's title back to its
    /// counterpart in a previous course version. Case-folds, strips
    /// non-alphanumeric characters, and collapses whitespace. So
    /// "Ordering food at a restaurant" and "Ordering food, at a
    /// restaurant." both collapse to "ordering food at a restaurant" —
    /// the model's minor punctuation refinements no longer drop the id.
    /// </summary>
    private static string NormaliseTitleForMatch(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return string.Empty;
        }
        var builder = new StringBuilder(raw.Length);
        var previousWasSpace = false;
        foreach (var ch in raw)
        {
            if (char.IsLetterOrDigit(ch))
            {
                builder.Append(char.ToLowerInvariant(ch));
                previousWasSpace = false;
            }
            else if (char.IsWhiteSpace(ch) || ch == '-' || ch == '_')
            {
                if (!previousWasSpace && builder.Length > 0)
                {
                    builder.Append(' ');
                    previousWasSpace = true;
                }
            }
            // Otherwise (punctuation, symbols): drop.
        }
        // Trim a possible trailing space introduced by the collapsing rule.
        if (builder.Length > 0 && builder[^1] == ' ')
        {
            builder.Length -= 1;
        }
        return builder.ToString();
    }
}

internal sealed record CourseAuthorLessonPayload(
    string? Title,
    string? LearningObjective,
    int? Order,
    int? EstimatedMinutes);
