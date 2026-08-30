using Voxa.Application.Authentication;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Infrastructure.Tests;

public sealed class TableRefreshSessionStoreTests
{
    [Fact]
    public async Task StoreAndGetAsyncRoundTripsRefreshSessionSubject()
    {
        var table = new InMemoryRefreshSessionTable();
        var store = new TableRefreshSessionStore(table);
        var subject = new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-a"));

        await store.StoreAsync("refresh-token", subject, DateTimeOffset.Parse("2026-08-29T09:00:00Z"), CancellationToken.None);
        var loaded = await store.GetAsync("refresh-token", CancellationToken.None);

        Assert.Equal(subject, loaded);
    }

    [Fact]
    public async Task GetAsyncReturnsNullForExpiredRefreshSession()
    {
        var table = new InMemoryRefreshSessionTable(DateTimeOffset.Parse("2026-08-29T10:00:00Z"));
        var store = new TableRefreshSessionStore(table);
        var subject = new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-a"));

        await store.StoreAsync("refresh-token", subject, DateTimeOffset.Parse("2026-08-29T09:00:00Z"), CancellationToken.None);
        var loaded = await store.GetAsync("refresh-token", CancellationToken.None);

        Assert.Null(loaded);
    }

    [Fact]
    public async Task RevokeAsyncRemovesRefreshSession()
    {
        var table = new InMemoryRefreshSessionTable();
        var store = new TableRefreshSessionStore(table);
        var subject = new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-a"));
        await store.StoreAsync("refresh-token", subject, DateTimeOffset.Parse("2026-08-29T09:00:00Z"), CancellationToken.None);

        await store.RevokeAsync("refresh-token", CancellationToken.None);
        var loaded = await store.GetAsync("refresh-token", CancellationToken.None);

        Assert.Null(loaded);
    }

    [Fact]
    public async Task StoreAsyncDoesNotUseRawRefreshTokenAsRowKey()
    {
        var table = new RecordingRefreshSessionTable();
        var store = new TableRefreshSessionStore(table);
        var subject = new VerifiedAppSessionSubject(TenantId.Create("tenant-default"), UserId.Create("user-a"));

        await store.StoreAsync("refresh-token", subject, DateTimeOffset.Parse("2026-08-29T09:00:00Z"), CancellationToken.None);

        Assert.NotNull(table.StoredEntity);
        Assert.NotEqual("refresh-token", table.StoredEntity.RowKey);
    }

    private sealed class RecordingRefreshSessionTable : IRefreshSessionTable
    {
        public DateTimeOffset UtcNow { get; } = DateTimeOffset.Parse("2026-08-29T08:00:00Z");

        public RefreshSessionTableEntity? StoredEntity { get; private set; }

        public Task<RefreshSessionTableEntity?> GetAsync(
            string partitionKey,
            string rowKey,
            CancellationToken cancellationToken)
        {
            return Task.FromResult<RefreshSessionTableEntity?>(null);
        }

        public Task UpsertAsync(
            RefreshSessionTableEntity entity,
            CancellationToken cancellationToken)
        {
            StoredEntity = entity;
            return Task.CompletedTask;
        }

        public Task DeleteAsync(
            string partitionKey,
            string rowKey,
            CancellationToken cancellationToken)
        {
            return Task.CompletedTask;
        }
    }
}
