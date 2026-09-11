using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class CourseReassessmentEndpointTests
{
    [Fact]
    public async Task PostAsyncReturns401WhenNoPrincipalIsAttached()
    {
        var endpoint = new CourseReassessmentEndpoint(new FakeReassessmentService((_, _) => throw new NotSupportedException()));

        var response = await endpoint.PostAsync(
            principal: null,
            request: new CourseReassessmentHttpRequest("more speaking"),
            correlationId: "corr-1",
            cancellationToken: CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task PostAsyncReturns404WhenTheLearnerHasNoState()
    {
        var endpoint = new CourseReassessmentEndpoint(new FakeReassessmentService(
            (_, _) => throw new LearnerStateNotFoundException(
                TenantId.Create("t"), UserId.Create("u"))));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: null,
            correlationId: "corr-2",
            cancellationToken: CancellationToken.None);

        Assert.Equal(404, response.StatusCode);
        Assert.Equal("learner_state_not_found", response.Error?.Code);
    }

    [Fact]
    public async Task PostAsyncReturns503WhenTheCourseAuthorFails()
    {
        var endpoint = new CourseReassessmentEndpoint(new FakeReassessmentService(
            (_, _) => throw new CourseAuthorException("upstream")));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: new CourseReassessmentHttpRequest("go"),
            correlationId: "corr-3",
            cancellationToken: CancellationToken.None);

        Assert.Equal(503, response.StatusCode);
        Assert.Equal("course_reassessment_unavailable", response.Error?.Code);
        Assert.True(response.Error?.Retryable);
    }

    [Fact]
    public async Task PostAsyncReturnsRetryable503WhenConcurrencyRetriesAreExhausted()
    {
        // Regression: CourseReassessmentService retries under optimistic
        // concurrency but eventually rethrows on the final attempt. The
        // endpoint used to let that escape as an unhandled 500 — clients
        // couldn't tell it was a transient conflict worth retrying. Now
        // maps to a retryable 503 with a stable error code.
        var endpoint = new CourseReassessmentEndpoint(new FakeReassessmentService(
            (_, _) => throw new StaleLearnerStateVersionException(
                TenantId.Create("t"),
                UserId.Create("u"),
                expectedVersion: LearnerStateVersion.Create(2),
                actualVersion: LearnerStateVersion.Create(3))));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: new CourseReassessmentHttpRequest("more speaking"),
            correlationId: "corr-conflict",
            cancellationToken: CancellationToken.None);

        Assert.Equal(503, response.StatusCode);
        Assert.Equal("course_reassessment_conflict", response.Error?.Code);
        Assert.True(response.Error?.Retryable);
        Assert.Equal("corr-conflict", response.Error?.CorrelationId);
    }

    [Fact]
    public async Task PostAsyncMapsResultingPlanIntoLearnerCourseHttpResponse()
    {
        CourseReassessmentCommand? captured = null;
        var endpoint = new CourseReassessmentEndpoint(new FakeReassessmentService((command, _) =>
        {
            captured = command;
            return Task.FromResult(new ActiveLearningPlan(
                "plan-x",
                "Everyday German",
                [],
                new PlannedLesson[]
                {
                    new("l1", "Greetings", "You'll say hello.", 1, 10, PlannedLessonStatus.Completed),
                    new("l2", "Cooking verbs", "You'll talk about food.", 2, 15, PlannedLessonStatus.Current),
                }));
        }));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: new CourseReassessmentHttpRequest("  more speaking practice  "),
            correlationId: "corr-4",
            cancellationToken: CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        var body = response.Body!;
        Assert.Equal("plan-x", body.PlanId);
        Assert.Equal("Everyday German", body.Title);
        Assert.Equal(2, body.Lessons.Count);
        Assert.Equal("Completed", body.Lessons[0].Status);
        Assert.Equal("Current", body.Lessons[1].Status);
        // The reassessment request is trimmed before being forwarded so
        // trailing whitespace from a UI text field doesn't leak into the
        // model's context.
        Assert.NotNull(captured);
        Assert.Equal("more speaking practice", captured!.ReassessmentRequest);
    }

    private static AppSessionPrincipal SamplePrincipal()
    {
        return new AppSessionPrincipal(TenantId.Create("tenant-default"), UserId.Create("user-a"));
    }

    private sealed class FakeReassessmentService(
        Func<CourseReassessmentCommand, CancellationToken, Task<ActiveLearningPlan>> handler) : ICourseReassessmentService
    {
        public Task<ActiveLearningPlan> ReassessAsync(
            CourseReassessmentCommand command,
            CancellationToken cancellationToken)
        {
            return handler(command, cancellationToken);
        }
    }
}
