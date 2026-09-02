using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class DevResetEndpointTests
{
    [Fact]
    public async Task DeleteReturnsNotFoundWhenDevResetIsDisabled()
    {
        var repository = new RecordingLearnerStateRepository();
        var endpoint = new DevResetEndpoint(repository, enabled: false);

        var response = await endpoint.DeleteAsync(
            new AppSessionPrincipal(TenantId.Create("tenant-default"), UserId.Create("user-a")),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(404, response.StatusCode);
        Assert.Equal("dev_reset_unavailable", response.Error?.Code);
        Assert.False(repository.Deleted);
    }

    [Fact]
    public async Task DeleteReturnsUnauthorizedWithoutAuthenticatedSession()
    {
        var repository = new RecordingLearnerStateRepository();
        var endpoint = new DevResetEndpoint(repository, enabled: true);

        var response = await endpoint.DeleteAsync(null, "corr-123", CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
        Assert.False(repository.Deleted);
    }

    [Fact]
    public async Task DeleteRemovesCurrentLearnerStateWhenEnabled()
    {
        var repository = new RecordingLearnerStateRepository();
        var endpoint = new DevResetEndpoint(repository, enabled: true);

        var response = await endpoint.DeleteAsync(
            new AppSessionPrincipal(TenantId.Create("tenant-default"), UserId.Create("user-a")),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.True(response.Body?.Deleted);
        Assert.True(repository.Deleted);
        Assert.Equal("tenant-default", repository.DeletedTenantId?.Value);
        Assert.Equal("user-a", repository.DeletedUserId?.Value);
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        public bool Deleted { get; private set; }
        public TenantId? DeletedTenantId { get; private set; }
        public UserId? DeletedUserId { get; private set; }

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            return Task.FromResult<LearnerState?>(null);
        }

        public Task<LearnerState> SaveAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            Deleted = true;
            DeletedTenantId = tenantId;
            DeletedUserId = userId;
            return Task.CompletedTask;
        }
    }
}
