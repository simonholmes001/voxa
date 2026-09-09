using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class RealtimeDebriefEndpointTests
{
    [Fact]
    public async Task PostAsyncReturns401WhenNoPrincipalIsAttachedToTheRequest()
    {
        var endpoint = new RealtimeDebriefEndpoint(new FakeDebriefService(_ => throw new NotSupportedException()));

        var response = await endpoint.PostAsync(
            principal: null,
            request: ValidBody(),
            correlationId: "corr-1",
            cancellationToken: CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Theory]
    [InlineData(null, "A1-A2", "fr-FR")]
    [InlineData("tutor", null, "fr-FR")]
    [InlineData("tutor", "A1-A2", null)]
    public async Task PostAsyncReturns400WhenRequiredCoachingSettingsAreMissing(
        string? coachingMode,
        string? proficiencyBand,
        string? targetLanguage)
    {
        var endpoint = new RealtimeDebriefEndpoint(new FakeDebriefService(_ => throw new NotSupportedException()));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: new SessionDebriefHttpRequest(
                coachingMode,
                proficiencyBand,
                targetLanguage,
                SessionIntent: "guided_lesson"),
            correlationId: "corr-2",
            cancellationToken: CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
    }

    [Fact]
    public async Task PostAsyncReturns503WhenTheAssessorCallFails()
    {
        var endpoint = new RealtimeDebriefEndpoint(
            new FakeDebriefService(_ => throw new SessionDebriefException("upstream")));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: ValidBody(),
            correlationId: "corr-3",
            cancellationToken: CancellationToken.None);

        Assert.Equal(503, response.StatusCode);
        Assert.Equal("debrief_unavailable", response.Error?.Code);
        Assert.True(response.Error?.Retryable);
    }

    [Fact]
    public async Task PostAsyncMapsSessionDebriefIntoHttpResponseAndForwardsTranscript()
    {
        SessionDebriefRequest? captured = null;
        var endpoint = new RealtimeDebriefEndpoint(new FakeDebriefService(req =>
        {
            captured = req;
            return new SessionDebrief(
                req.CorrelationId.Value,
                "Practiced past tense.",
                [new DebriefRecurringMistake("past participle", "I have ate", "medium")],
                ["How's it going?"],
                ["the 'th' needs more tongue-tip contact"],
                new DebriefRecommendedDrill("pronunciation_drill", "English th", "you tripped on 'th' twice."));
        }));

        var response = await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: new SessionDebriefHttpRequest(
                "tutor",
                "A1-A2",
                "fr-FR",
                SessionIntent: "guided_lesson",
                Transcript: [new TranscriptTurnDto("tutor", "Bonjour."), new TranscriptTurnDto("learner", "Salut !")]),
            correlationId: "corr-4",
            cancellationToken: CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        var body = response.Body!;
        Assert.Equal("corr-4", body.CorrelationId);
        Assert.Equal("Practiced past tense.", body.Summary);
        Assert.Single(body.RecurringMistakes);
        Assert.Equal("pronunciation_drill", body.RecommendedNextDrill.ActivityIntent);
        Assert.NotNull(captured);
        Assert.Equal(2, captured!.Transcript.Count);
        Assert.Equal("tutor", captured.Transcript[0].Role);
        Assert.Equal("Bonjour.", captured.Transcript[0].Text);
    }

    [Fact]
    public async Task PostAsyncDropsTranscriptTurnsWithEmptyText()
    {
        SessionDebriefRequest? captured = null;
        var endpoint = new RealtimeDebriefEndpoint(new FakeDebriefService(req =>
        {
            captured = req;
            return new SessionDebrief(
                req.CorrelationId.Value,
                "",
                [],
                [],
                [],
                new DebriefRecommendedDrill("open_practice", "", ""));
        }));

        await endpoint.PostAsync(
            principal: SamplePrincipal(),
            request: new SessionDebriefHttpRequest(
                "tutor",
                "A1-A2",
                "fr-FR",
                SessionIntent: "open_practice",
                Transcript:
                [
                    new TranscriptTurnDto("tutor", "  "),
                    new TranscriptTurnDto("learner", null),
                    new TranscriptTurnDto("tutor", "Bonjour."),
                ]),
            correlationId: "corr-5",
            cancellationToken: CancellationToken.None);

        Assert.NotNull(captured);
        // Two junk turns dropped, one real turn kept.
        Assert.Single(captured!.Transcript);
        Assert.Equal("Bonjour.", captured.Transcript[0].Text);
    }

    // MARK: - Helpers

    private static SessionDebriefHttpRequest ValidBody()
    {
        return new SessionDebriefHttpRequest(
            "tutor",
            "A1-A2",
            "fr-FR",
            SessionIntent: "open_practice");
    }

    private static AppSessionPrincipal SamplePrincipal()
    {
        return new AppSessionPrincipal(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"));
    }

    private sealed class FakeDebriefService(Func<SessionDebriefRequest, SessionDebrief> handler) : IDebriefService
    {
        public Task<SessionDebrief> GenerateDebriefAsync(
            SessionDebriefRequest request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(handler(request));
        }
    }
}
