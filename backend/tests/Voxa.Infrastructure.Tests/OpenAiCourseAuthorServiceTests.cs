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
        var handler = new RecordingHttpMessageHandler("""
            {
              "choices": [{
                "message": {
                  "role": "assistant",
                  "content": "{ \"courseTitle\": \"Everyday German\", \"lessons\": [ { \"title\": \"Greetings\", \"learningObjective\": \"You'll be able to say hello and goodbye naturally.\", \"order\": 1, \"estimatedMinutes\": 10 }, { \"title\": \"Cooking verbs\", \"learningObjective\": \"You'll be able to talk about preparing food.\", \"order\": 2, \"estimatedMinutes\": 15 } ] }"
                }
              }]
            }
            """);
        var service = MakeService(handler);

        var plan = await service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None);

        Assert.Equal("Everyday German", plan.Title);
        Assert.Equal(2, plan.Lessons.Count);
        Assert.Equal("Greetings", plan.Lessons[0].Title);
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
        var handler = new RecordingHttpMessageHandler(SampleThreeLessonResponseBody());
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
        var handler = new RecordingHttpMessageHandler("""
            {
              "choices": [{
                "message": {
                  "role": "assistant",
                  "content": "{ \"courseTitle\": \"Everyday German (revised)\", \"lessons\": [ { \"title\": \"Greetings\", \"learningObjective\": \"You'll say hello.\", \"order\": 1, \"estimatedMinutes\": 10 }, { \"title\": \"Cooking verbs\", \"learningObjective\": \"You'll talk about food.\", \"order\": 2, \"estimatedMinutes\": 15 }, { \"title\": \"Past tense basics\", \"learningObjective\": \"You'll describe yesterday.\", \"order\": 3, \"estimatedMinutes\": 15 } ] }"
                }
              }]
            }
            """);
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
        // Past tense is a new lesson → fresh GUID, Pending.
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
    public async Task AuthorCourseAsyncSortsLessonsByOrderBeforeAssigningStatus()
    {
        // Model returned lessons out of order; the service must sort
        // before marking Current, so the LOWEST-order pending lesson is
        // Current — not whichever one arrived first in the JSON.
        var handler = new RecordingHttpMessageHandler("""
            {
              "choices": [{
                "message": {
                  "role": "assistant",
                  "content": "{ \"courseTitle\": \"Test\", \"lessons\": [ { \"title\": \"Second\", \"learningObjective\": \"…\", \"order\": 2, \"estimatedMinutes\": 15 }, { \"title\": \"First\", \"learningObjective\": \"…\", \"order\": 1, \"estimatedMinutes\": 10 } ] }"
                }
              }]
            }
            """);
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
        var handler = new RecordingHttpMessageHandler(SampleThreeLessonResponseBody());
        var service = MakeService(handler);

        await service.AuthorCourseAsync(InitialMintRequest(), CancellationToken.None);

        Assert.Equal("Bearer server-api-key", handler.Request?.Headers.Authorization?.ToString());
        Assert.DoesNotContain("server-api-key", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"response_format\":{\"type\":\"json_object\"}", handler.Body, StringComparison.Ordinal);
        Assert.Contains("gpt-5.6-sol", handler.Body, StringComparison.Ordinal);
    }

    // MARK: - Helpers

    private static string SampleThreeLessonResponseBody()
    {
        return """
            {"choices":[{"message":{"role":"assistant","content":"{\"courseTitle\":\"Test\",\"lessons\":[{\"title\":\"Greetings\",\"learningObjective\":\"…\",\"order\":1,\"estimatedMinutes\":10},{\"title\":\"Numbers\",\"learningObjective\":\"…\",\"order\":2,\"estimatedMinutes\":10},{\"title\":\"Food\",\"learningObjective\":\"…\",\"order\":3,\"estimatedMinutes\":15}]}"}}]}
            """;
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
