using Voxa.Application.Realtime;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.Persistence;
using Voxa.Infrastructure.Realtime;

namespace Voxa.Infrastructure.Tests;

public sealed class TableRealtimeSessionRateLimiterTests
{
    [Fact]
    public async Task EnsureAllowedRecordsAttemptWhenUnderLimit()
    {
        var table = new RecordingRealtimeSessionRateLimitTable();
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(DateTimeOffset.Parse("2026-08-30T10:00:00Z")),
            new RealtimeSessionRateLimitOptions(2, TimeSpan.FromMinutes(1)));

        await limiter.EnsureAllowedAsync(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CancellationToken.None);

        var attempt = Assert.Single(table.Entities);
        Assert.Equal("tenant-default:user-a", attempt.PartitionKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-30T10:00:00Z"), attempt.RequestedAt);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenWindowLimitIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new RecordingRealtimeSessionRateLimitTable(existingCount: 2);
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(now),
            new RealtimeSessionRateLimitOptions(2, TimeSpan.FromMinutes(1)));

        await Assert.ThrowsAsync<RealtimeSessionRateLimitException>(() =>
            limiter.EnsureAllowedAsync(
                TenantId.Create("tenant-default"),
                UserId.Create("user-a"),
                CancellationToken.None));

        Assert.Empty(table.Entities);
        Assert.Equal("tenant-default:user-a", table.CountedPartitionKey);
        Assert.Equal(now.AddMinutes(-1), table.CountedSince);
    }

    private sealed class RecordingRealtimeSessionRateLimitTable(int existingCount = 0) : IRealtimeSessionRateLimitTable
    {
        public List<RealtimeSessionRateLimitTableEntity> Entities { get; } = [];

        public string? CountedPartitionKey { get; private set; }

        public DateTimeOffset? CountedSince { get; private set; }

        public Task<int> CountSinceAsync(
            string partitionKey,
            DateTimeOffset since,
            CancellationToken cancellationToken)
        {
            CountedPartitionKey = partitionKey;
            CountedSince = since;
            return Task.FromResult(existingCount);
        }

        public Task AddAsync(
            RealtimeSessionRateLimitTableEntity entity,
            CancellationToken cancellationToken)
        {
            Entities.Add(entity);
            return Task.CompletedTask;
        }
    }

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
