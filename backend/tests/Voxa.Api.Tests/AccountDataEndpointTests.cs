using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class AccountDataEndpointTests
{
    [Fact]
    public async Task ExportReturnsUnauthorizedWithoutAuthenticatedSession()
    {
        var endpoint = new AccountDataEndpoint(new StubAccountDataService());

        var response = await endpoint.ExportAsync(null, "corr-123", CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task ExportReturnsLearnerDataForAuthenticatedSession()
    {
        var endpoint = new AccountDataEndpoint(new StubAccountDataService());

        var response = await endpoint.ExportAsync(Principal(), "corr-123", CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.Equal("corr-123", response.Body?.CorrelationId);
        Assert.Equal("tenant-default", response.Body?.TenantId);
        Assert.Equal("user-a", response.Body?.UserId);
        Assert.Single(response.Body?.LanguageProfiles ?? []);
    }

    [Fact]
    public async Task DeleteReturnsUnauthorizedWithoutAuthenticatedSession()
    {
        var endpoint = new AccountDataEndpoint(new StubAccountDataService());

        var response = await endpoint.DeleteAsync(null, "corr-123", CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task DeleteRemovesAccountDataForAuthenticatedSession()
    {
        var service = new StubAccountDataService();
        var endpoint = new AccountDataEndpoint(service);

        var response = await endpoint.DeleteAsync(Principal(), "corr-123", CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.True(response.Body?.Deleted);
        Assert.Equal(1, response.Body?.DeletedLanguageProfileCount);
        Assert.Equal("tenant-default", service.DeletedPrincipal?.TenantId.Value);
        Assert.Equal("user-a", service.DeletedPrincipal?.UserId.Value);
    }

    private static AppSessionPrincipal Principal() =>
        new(TenantId.Create("tenant-default"), UserId.Create("user-a"));

    private sealed class StubAccountDataService : IAccountDataService
    {
        public AppSessionPrincipal? DeletedPrincipal { get; private set; }

        public Task<AccountDataExport> ExportAsync(
            AppSessionPrincipal principal,
            CorrelationId correlationId,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new AccountDataExport(
                correlationId.Value,
                principal.TenantId.Value,
                principal.UserId.Value,
                DateTimeOffset.Parse("2026-09-15T08:00:00Z"),
                "2026-09-15",
                [
                    new AccountLanguageProfileExport(
                        "fr-FR",
                        1,
                        new LearnerProfileContract("fr-FR", "en-US", "A1", ["travel"], 15),
                        new ActiveLearningPlanExport("plan-1", "Survival French", ["greetings"], []),
                        new LessonCheckpointContract("lesson-1", "unit-1", 0, DateTimeOffset.Parse("2026-09-15T08:00:00Z")),
                        [],
                        [],
                        [])
                ]));
        }

        public Task<AccountDeletionResult> DeleteAsync(
            AppSessionPrincipal principal,
            CorrelationId correlationId,
            CancellationToken cancellationToken)
        {
            DeletedPrincipal = principal;
            return Task.FromResult(new AccountDeletionResult(correlationId.Value, true, 1));
        }
    }
}
