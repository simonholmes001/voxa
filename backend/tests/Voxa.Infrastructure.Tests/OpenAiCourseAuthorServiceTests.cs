using System.Net;
using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Voxa.Application.Ai;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiCourseAuthorServiceTests
{
    private static readonly TenantId Tenant = TenantId.Create("tenant-a");
    private static readonly UserId User = UserId.Create("user-a");

    [Fact]
    public async Task AuthorCourseAsyncRendersPromptWithProfileAndParsesStructuredCourse()
    {
        var handler = new RecordingHttpMessageHandler(SampleTwentyLessonResponseBody("Everyday German"));
        var service = MakeService(handler);

        var plan = await service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None);

        Assert.Equal("Everyday German", plan.Title);
        Assert.Equal(20, plan.Lessons.Count);
        Assert.Equal("Lesson 1", plan.Lessons[0].Title);
        Assert.Equal(1, plan.Lessons[0].Order);
        Assert.Equal(PlannedLessonStatus.Current, plan.Lessons[0].Status);
        Assert.Equal(PlannedLessonStatus.Pending, plan.Lessons[1].Status);

        // Prompt actually received the learner's profile as context.
        Assert.Contains("de-DE", handler.Body, StringComparison.Ordinal);
        Assert.Contains("A1-A2", handler.Body, StringComparison.Ordinal);
        Assert.Contains("travel", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AuthorCourseAsyncMarksTheFirstNonCompletedLessonAsCurrent()
    {
        var handler = new RecordingHttpMessageHandler(SampleTwentyLessonResponseBody("Test"));
        var service = MakeService(handler);

        var plan = await service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None);

        Assert.Equal(PlannedLessonStatus.Current, plan.Lessons[0].Status);
        Assert.Equal(PlannedLessonStatus.Pending, plan.Lessons[1].Status);
        Assert.Equal(PlannedLessonStatus.Pending, plan.Lessons[2].Status);
    }

    [Fact]
    public async Task AuthorCourseAsyncPreservesCompletedLessonIdsAcrossAReMint()
    {
        // A re-mint that keeps the "Greetings" title should keep its
        // lesson ID, so a CompletedLessonIds referring to the OLD course
        // still resolves against the NEW course. This is what makes
        // "lesson 3 of 27 → lesson 3 of 29" preserve progress semantics.
        var existingCourse = new ActiveLearningPlan(
            "old-plan",
            "Old German course",
            [],
            new PlannedLesson[]
            {
                new("existing-greetings-id", "Greetings", "…", 1, 10, PlannedLessonStatus.Completed),
                new("existing-cooking-id", "Cooking verbs", "…", 2, 15, PlannedLessonStatus.Current),
            });
        // The model returns a 20-lesson course whose first two titles
        // match the existing course's, and 18 fresh lessons for the rest.
        var lessons = new List<(string title, string obj, int order, int minutes)>
        {
            ("Greetings", "You'll say hello.", 1, 10),
            ("Cooking verbs", "You'll talk about food.", 2, 15),
        };
        for (var i = 3; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", "You'll do a thing.", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(
            BuildResponseBody("Everyday German (revised)", lessons));
        var service = MakeService(handler);
        var request = InitialMintRequest() with
        {
            ExistingCourse = existingCourse,
            CompletedLessonIds = ["existing-greetings-id"],
            ReassessmentRequest = "add more past-tense practice",
        };

        var plan = await service.AuthorCourseAsync(request, CancellationToken.None);

        // Greetings kept its ID → marked Completed thanks to CompletedLessonIds.
        Assert.Equal("existing-greetings-id", plan.Lessons[0].LessonId);
        Assert.Equal(PlannedLessonStatus.Completed, plan.Lessons[0].Status);
        // Cooking verbs kept its ID too (title match) but wasn't completed → Current.
        Assert.Equal("existing-cooking-id", plan.Lessons[1].LessonId);
        Assert.Equal(PlannedLessonStatus.Current, plan.Lessons[1].Status);
        // Following lessons are fresh GUIDs, Pending.
        Assert.NotEqual("existing-greetings-id", plan.Lessons[2].LessonId);
        Assert.NotEqual("existing-cooking-id", plan.Lessons[2].LessonId);
        Assert.Equal(PlannedLessonStatus.Pending, plan.Lessons[2].Status);
        // Plan ID carries through the re-mint so downstream references
        // (learner state, checkpoints) don't dangle.
        Assert.Equal("old-plan", plan.PlanId);
        // Reassessment request reached the model.
        Assert.Contains("past-tense practice", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AuthorCourseAsyncPreservesCompletedLessonIdEvenWhenModelRefinesPunctuation()
    {
        // Regression: the model refined the completed title from
        // "Ordering food at a restaurant" to "Ordering food, at a
        // restaurant." (added comma + period). Ordinal-case title match
        // would have dropped the id and silently regressed progress.
        // With aggressive title normalisation the id is preserved.
        var existingCourse = new ActiveLearningPlan(
            "old-plan",
            "Old German course",
            [],
            new PlannedLesson[]
            {
                new("id-ordering", "Ordering food at a restaurant", "…", 1, 15, PlannedLessonStatus.Completed),
            });
        var lessons = new List<(string title, string obj, int order, int minutes)>
        {
            ("Ordering food, at a restaurant.", "You'll order a meal.", 1, 15),
        };
        for (var i = 2; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", "You'll do a thing.", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("Refined", lessons));
        var service = MakeService(handler);
        var request = InitialMintRequest() with
        {
            ExistingCourse = existingCourse,
            CompletedLessonIds = ["id-ordering"],
        };

        var plan = await service.AuthorCourseAsync(request, CancellationToken.None);

        Assert.Equal("id-ordering", plan.Lessons[0].LessonId);
        Assert.Equal(PlannedLessonStatus.Completed, plan.Lessons[0].Status);
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsWhenCompletedLessonIdIsDroppedByReMint()
    {
        // Even after normalisation, if the model drops or renames a
        // completed lesson beyond recognition, we refuse to persist a
        // plan that has silently lost progress.
        var existingCourse = new ActiveLearningPlan(
            "old-plan",
            "Old",
            [],
            new PlannedLesson[]
            {
                new("id-lost", "Uncommon completed topic", "…", 1, 15, PlannedLessonStatus.Completed),
            });
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", "You'll do a thing.", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("New", lessons));
        var service = MakeService(handler);
        var request = InitialMintRequest() with
        {
            ExistingCourse = existingCourse,
            CompletedLessonIds = ["id-lost"],
        };

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(request, CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncSortsLessonsByOrderBeforeAssigningStatus()
    {
        // Model returned lessons out of order; the service must sort
        // before marking Current, so the LOWEST-order pending lesson is
        // Current — not whichever one arrived first in the JSON.
        var lessons = new List<(string title, string obj, int order, int minutes)>
        {
            ("Second", "…", 2, 15),
            ("First", "…", 1, 10),
        };
        for (var i = 3; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", "…", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("Test", lessons));
        var service = MakeService(handler);

        var plan = await service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None);

        Assert.Equal("First", plan.Lessons[0].Title);
        Assert.Equal(PlannedLessonStatus.Current, plan.Lessons[0].Status);
        Assert.Equal("Second", plan.Lessons[1].Title);
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsCourseAuthorExceptionWhenModelReturnsNoLessons()
    {
        // A safety net: if the assessor emits an empty list, we don't
        // silently persist a broken plan. The endpoint maps this to a
        // retriable 503 so the learner sees an actionable error, not a
        // ghost course.
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"{\"courseTitle\":\"Broken\",\"lessons\":[]}"}}]}
            """);
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsCourseAuthorExceptionOnUpstreamFailure()
    {
        var handler = new RecordingHttpMessageHandler("""{"error":"quota"}""", HttpStatusCode.TooManyRequests);
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsCourseAuthorExceptionWhenModelReturnsNonJson()
    {
        var handler = new RecordingHttpMessageHandler("""
            {"choices":[{"message":{"role":"assistant","content":"not JSON, just prose"}}]}
            """);
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncSendsBearerTokenOnlyInAuthorizationHeaderAndUsesJsonObject()
    {
        var handler = new RecordingHttpMessageHandler(SampleTwentyLessonResponseBody("Test"));
        var service = MakeService(handler);

        await service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None);

        Assert.Equal("Bearer server-api-key", handler.Request?.Headers.Authorization?.ToString());
        Assert.DoesNotContain("server-api-key", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"response_format\":{\"type\":\"json_object\"}", handler.Body, StringComparison.Ordinal);
        Assert.Contains("gpt-5.6-sol", handler.Body, StringComparison.Ordinal);
    }

    // MARK: - Schema validation (High finding from PR #111 review)

    [Fact]
    public async Task AuthorCourseAsyncThrowsWhenFewerThanTwentyLessons()
    {
        // The prompt schema declares minItems: 20; response_format is only
        // json_object (not json_schema), so the count is enforced in the
        // application code. Without this gate a 5-lesson response would
        // persist as the learner's real "course".
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 19; i++)
        {
            lessons.Add(($"Lesson {i}", "…", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("Short", lessons));
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsWhenMoreThanThirtyLessons()
    {
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 31; i++)
        {
            lessons.Add(($"Lesson {i}", "…", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("Long", lessons));
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsWhenLessonHasBlankObjective()
    {
        // Objective is a required contract field. A blank one would
        // surface as an empty subtitle in Home + CourseDetail.
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", i == 5 ? "   " : "…", i, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("With blank", lessons));
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsWhenTwoLessonsShareTheSameOrder()
    {
        // Duplicate order values break the arc's "lesson N of M"
        // semantic — Home would show the wrong current lesson.
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 20; i++)
        {
            var order = i == 10 ? 5 : i; // duplicate 5
            lessons.Add(($"Lesson {i}", "…", order, 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("Dup", lessons));
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    [Fact]
    public async Task AuthorCourseAsyncThrowsWhenEstimatedMinutesOutsideExpectedRange()
    {
        // Schema says 5..60. A 3-minute or 90-minute lesson doesn't fit
        // the daily-minutes cadence assumption and would misrender in
        // the UI ("~3 min" is misleading for a real session).
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", "…", i, i == 7 ? 3 : 15));
        }
        var handler = new RecordingHttpMessageHandler(BuildResponseBody("Bad", lessons));
        var service = MakeService(handler);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None));
    }

    // MARK: - Helpers

    private static string SampleTwentyLessonResponseBody(string courseTitle)
    {
        var lessons = new List<(string title, string obj, int order, int minutes)>();
        for (var i = 1; i <= 20; i++)
        {
            lessons.Add(($"Lesson {i}", "You'll do a thing.", i, 15));
        }
        return BuildResponseBody(courseTitle, lessons);
    }

    /// <summary>
    /// Assembles the OpenAI response envelope around a course payload.
    /// Keeps the tests readable — the raw JSON-in-JSON strings the old
    /// tests inlined were unmaintainable once we needed 20+ lessons.
    /// </summary>
    private static string BuildResponseBody(
        string courseTitle,
        List<(string title, string obj, int order, int minutes)> lessons)
    {
        var payload = new
        {
            courseTitle,
            lessons = lessons
                .Select(l => new
                {
                    title = l.title,
                    learningObjective = l.obj,
                    order = l.order,
                    estimatedMinutes = l.minutes,
                })
                .ToArray(),
        };
        var content = System.Text.Json.JsonSerializer.Serialize(payload);
        var envelope = new
        {
            choices = new[]
            {
                new { message = new { role = "assistant", content } },
            },
        };
        return System.Text.Json.JsonSerializer.Serialize(envelope);
    }

    private static CourseAuthorRequest InitialMintRequest()
    {
        return new CourseAuthorRequest(
            Tenant,
            User,
            CorrelationId.Create("corr-mint"),
            new LearnerProfile(Tenant, User, "de-DE", "en-US", "A1-A2", ["travel"], 15),
            ExistingCourse: null,
            CompletedLessonIds: [],
            RecentDebriefs: [],
            ReassessmentRequest: null);
    }

    private static OpenAiCourseAuthorService MakeService(RecordingHttpMessageHandler handler)
    {
        var client = new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") };
        return new OpenAiCourseAuthorService(
            client,
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.CurriculumModel,
                "gpt-5.6-sol",
                "high",
                ModelRouteSource.ConfigDefault,
                null)),
            EmbeddedPromptRegistry.CreateDefault(),
            NullLogger<OpenAiCourseAuthorService>.Instance);
    }

    private sealed class RecordingHttpMessageHandler(
        string responseBody,
        HttpStatusCode statusCode = HttpStatusCode.OK) : HttpMessageHandler
    {
        public HttpRequestMessage? Request { get; private set; }
        public string Body { get; private set; } = "";

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Request = request;
            Body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json"),
            };
        }
    }

    private sealed class StubModelRouter(ModelRoute route) : IModelRouter
    {
        public ModelRoute Resolve(ModelRouteRequest request) => route;
    }
}
