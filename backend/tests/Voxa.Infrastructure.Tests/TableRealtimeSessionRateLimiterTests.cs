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
            Options(maxRequests: 2));

        await limiter.EnsureAllowedAsync(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CancellationToken.None);

        Assert.Equal(3, table.Reservations.Count);
        var reservation = table.Reservations[0];
        Assert.Equal("user:tenant-default:user-a:burst", reservation.PartitionKey);
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
            Options(maxRequests: 2));

        await Assert.ThrowsAsync<RealtimeSessionRateLimitException>(() =>
            limiter.EnsureAllowedAsync(
                TenantId.Create("tenant-default"),
                UserId.Create("user-a"),
                CancellationToken.None));

        var reservation = Assert.Single(table.Reservations);
        Assert.Equal("user:tenant-default:user-a:burst", reservation.PartitionKey);
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
            Options(maxRequests: 2));
        var requests = Enumerable.Range(0, 10)
            .Select(_ => TryEnsureAllowedAsync(limiter))
            .ToArray();

        var results = await Task.WhenAll(requests);

        Assert.Equal(2, results.Count(success => success));
        Assert.Equal(8, results.Count(success => !success));
        Assert.Equal(2, table.ReservedCount);
    }

    [Fact]
    public async Task DeleteForSubjectRemovesPartition()
    {
        var table = new RecordingRealtimeSessionRateLimitTable();
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(DateTimeOffset.Parse("2026-08-30T10:00:00Z")),
            Options(maxRequests: 2));

        await limiter.DeleteForSubjectAsync(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CancellationToken.None);

        Assert.Equal(
            ["user:tenant-default:user-a:month", "user:tenant-default:user-a:burst"],
            table.DeletedPartitionKeys);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenMonthlyUserBudgetIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new SelectiveRealtimeSessionRateLimitTable("user:tenant-default:user-a:month");
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(now),
            Options(monthlyUserLimit: 1));

        var exception = await Assert.ThrowsAsync<RealtimeSessionRateLimitException>(() =>
            limiter.EnsureAllowedAsync(
                TenantId.Create("tenant-default"),
                UserId.Create("user-a"),
                CancellationToken.None));

        Assert.Equal("realtime_session_budget_exhausted", exception.Code);
        Assert.Equal("user:tenant-default:user-a:burst", table.Reservations[0].PartitionKey);
        Assert.Equal("user:tenant-default:user-a:month", table.Reservations[1].PartitionKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-01T00:00:00Z"), table.Reservations[1].WindowStart);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenMonthlyTenantBudgetIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new SelectiveRealtimeSessionRateLimitTable("tenant:tenant-default:month");
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(now),
            Options(monthlyTenantLimit: 1));

        var exception = await Assert.ThrowsAsync<RealtimeSessionRateLimitException>(() =>
            limiter.EnsureAllowedAsync(
                TenantId.Create("tenant-default"),
                UserId.Create("user-a"),
                CancellationToken.None));

        Assert.Equal("realtime_session_budget_exhausted", exception.Code);
        Assert.Equal(3, table.Reservations.Count);
        var reservation = table.Reservations[2];
        Assert.Equal("tenant:tenant-default:month", reservation.PartitionKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-01T00:00:00Z"), reservation.WindowStart);
    }

    [Fact]
    public async Task EnsureAllowedStartsNewMonthlyBudgetOnMonthRollover()
    {
        var table = new RecordingRealtimeSessionRateLimitTable();
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(DateTimeOffset.Parse("2026-09-01T00:00:00Z")),
            Options());

        await limiter.EnsureAllowedAsync(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CancellationToken.None);

        Assert.Equal(DateTimeOffset.Parse("2026-09-01T00:00:00Z"), table.Reservations[1].WindowStart);
        Assert.Equal(DateTimeOffset.Parse("2026-09-01T00:00:00Z"), table.Reservations[2].WindowStart);
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

        public List<string> DeletedPartitionKeys { get; } = [];

        public Task DeletePartitionAsync(
            string partitionKey,
            CancellationToken cancellationToken)
        {
            DeletedPartitionKeys.Add(partitionKey);
            return Task.CompletedTask;
        }
    }

    private sealed class SelectiveRealtimeSessionRateLimitTable(string rejectedPartitionKey) : IRealtimeSessionRateLimitTable
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
            return Task.FromResult(!string.Equals(partitionKey, rejectedPartitionKey, StringComparison.Ordinal));
        }

        public Task DeletePartitionAsync(
            string partitionKey,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class ConcurrentRealtimeSessionRateLimitTable : IRealtimeSessionRateLimitTable
    {
        private readonly object gate = new();
        private readonly Dictionary<string, int> reservedCounts = new(StringComparer.Ordinal);

        public int ReservedCount
        {
            get
            {
                lock (gate)
                {
                    return reservedCounts.GetValueOrDefault("user:tenant-default:user-a:burst");
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
                var count = reservedCounts.GetValueOrDefault(partitionKey);
                if (count >= maxRequests)
                {
                    return Task.FromResult(false);
                }

                reservedCounts[partitionKey] = count + 1;
                return Task.FromResult(true);
            }
        }

        public Task DeletePartitionAsync(
            string partitionKey,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed record Reservation(
        string PartitionKey,
        DateTimeOffset WindowStart,
        int MaxRequests,
        DateTimeOffset RequestedAt);

    private static RealtimeSessionRateLimitOptions Options(
        int maxRequests = 12,
        int monthlyUserLimit = 600,
        int monthlyTenantLimit = 6_000)
    {
        return new RealtimeSessionRateLimitOptions(
            maxRequests,
            TimeSpan.FromMinutes(1),
            monthlyUserLimit,
            monthlyTenantLimit);
    }

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
