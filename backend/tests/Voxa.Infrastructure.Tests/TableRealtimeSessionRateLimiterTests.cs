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

        var reservation = Assert.Single(table.Reservations);
        Assert.Equal("tenant-default:user-a", reservation.PartitionKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-30T10:00:00Z"), reservation.RequestedAt);
        Assert.Equal(DateTimeOffset.Parse("2026-08-30T10:00:00Z"), reservation.WindowStart);
        Assert.Equal(2, reservation.MaxRequests);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenWindowLimitIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new RecordingRealtimeSessionRateLimitTable(allowReservation: false);
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(now),
            new RealtimeSessionRateLimitOptions(2, TimeSpan.FromMinutes(1)));

        await Assert.ThrowsAsync<RealtimeSessionRateLimitException>(() =>
            limiter.EnsureAllowedAsync(
                TenantId.Create("tenant-default"),
                UserId.Create("user-a"),
                CancellationToken.None));

        var reservation = Assert.Single(table.Reservations);
        Assert.Equal("tenant-default:user-a", reservation.PartitionKey);
        Assert.Equal(now, reservation.RequestedAt);
        Assert.Equal(now, reservation.WindowStart);
    }

    [Fact]
    public async Task EnsureAllowedUsesAtomicReservationsUnderConcurrency()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new ConcurrentRealtimeSessionRateLimitTable();
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(now),
            new RealtimeSessionRateLimitOptions(2, TimeSpan.FromMinutes(1)));
        var requests = Enumerable.Range(0, 10)
            .Select(_ => TryEnsureAllowedAsync(limiter))
            .ToArray();

        var results = await Task.WhenAll(requests);

        Assert.Equal(2, results.Count(success => success));
        Assert.Equal(8, results.Count(success => !success));
        Assert.Equal(2, table.ReservedCount);
    }

    private static async Task<bool> TryEnsureAllowedAsync(TableRealtimeSessionRateLimiter limiter)
    {
        try
        {
            await limiter.EnsureAllowedAsync(
                TenantId.Create("tenant-default"),
                UserId.Create("user-a"),
                CancellationToken.None);
            return true;
        }
        catch (RealtimeSessionRateLimitException)
        {
            return false;
        }
    }

    private sealed class RecordingRealtimeSessionRateLimitTable(bool allowReservation = true) : IRealtimeSessionRateLimitTable
    {
        public List<Reservation> Reservations { get; } = [];

        public Task<bool> TryReserveAsync(
            string partitionKey,
            DateTimeOffset windowStart,
            int maxRequests,
            DateTimeOffset requestedAt,
            CancellationToken cancellationToken)
        {
            Reservations.Add(new Reservation(partitionKey, windowStart, maxRequests, requestedAt));
            return Task.FromResult(allowReservation);
        }
    }

    private sealed class ConcurrentRealtimeSessionRateLimitTable : IRealtimeSessionRateLimitTable
    {
        private readonly object gate = new();
        private int reservedCount;

        public int ReservedCount
        {
            get
            {
                lock (gate)
                {
                    return reservedCount;
                }
            }
        }

        public Task<bool> TryReserveAsync(
            string partitionKey,
            DateTimeOffset windowStart,
            int maxRequests,
            DateTimeOffset requestedAt,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                if (reservedCount >= maxRequests)
                {
                    return Task.FromResult(false);
                }

                reservedCount++;
                return Task.FromResult(true);
            }
        }
    }

    private sealed record Reservation(
        string PartitionKey,
        DateTimeOffset WindowStart,
        int MaxRequests,
        DateTimeOffset RequestedAt);

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
