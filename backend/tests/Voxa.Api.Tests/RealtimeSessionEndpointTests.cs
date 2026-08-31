using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class RealtimeSessionEndpointTests
{
    [Fact]
    public async Task PostReturnsUnauthorizedWithoutAuthenticatedAppSession()
    {
        var endpoint = new RealtimeSessionEndpoint(new StubRealtimeSessionService());

        var response = await endpoint.PostAsync(
            principal: null,
            new RealtimeSessionHttpRequest("tutor", "B1-B2", "fr-FR"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task PostReturnsShortLivedRealtimeClientSecretWithoutServerKey()
    {
        var endpoint = new RealtimeSessionEndpoint(new StubRealtimeSessionService());

        var response = await endpoint.PostAsync(
            new AppSessionPrincipal(TenantId.Create("tenant-default"), UserId.Create("user-a")),
            new RealtimeSessionHttpRequest("tutor", "B1-B2", "fr-FR"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.NotNull(response.Body);
        Assert.Equal("corr-123", response.Body.CorrelationId);
        Assert.Equal("realtime-client-secret", response.Body.ClientSecret);
        Assert.Equal("gpt-realtime-2.1", response.Body.Model);
        Assert.Equal("low", response.Body.ReasoningEffort);
        Assert.DoesNotContain("OPENAI_API_KEY", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("server-api-key", response.Body.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task PostReturnsBadRequestForInvalidSessionSettings()
    {
        var endpoint = new RealtimeSessionEndpoint(new StubRealtimeSessionService());

        var response = await endpoint.PostAsync(
            new AppSessionPrincipal(TenantId.Create("tenant-default"), UserId.Create("user-a")),
            new RealtimeSessionHttpRequest("", "B1-B2", "fr-FR"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
    }

    private sealed class StubRealtimeSessionService : IRealtimeSessionService
    {
        public Task<RealtimeSessionCredential> IssueClientSecretAsync(
            RealtimeSessionCommand command,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new RealtimeSessionCredential(
                command.CorrelationId.Value,
                "realtime-client-secret",
                "gpt-realtime-2.1",
                "low",
                DateTimeOffset.Parse("2026-08-29T08:20:00Z"),
                new RealtimeSessionSettingsContract(command.CoachingMode, command.ProficiencyBand, command.TargetLanguage)));
        }
    }
}
