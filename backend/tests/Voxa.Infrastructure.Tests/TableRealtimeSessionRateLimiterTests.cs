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
        Assert.All(table.Reservations, reservation => Assert.Equal("tenant:tenant-default", reservation.PartitionKey));
        var reservation = table.Reservations[0];
        Assert.Equal($"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}", reservation.RowKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-30T10:00:00Z"), reservation.RequestedAt);
        Assert.Equal(DateTimeOffset.Parse("2026-08-30T10:00:00Z"), reservation.WindowStart);
        Assert.Equal(2, reservation.MaxRequests);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenWindowLimitIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new RecordingRealtimeSessionRateLimitTable(rejectedRowKey: $"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}");
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
        Assert.Equal($"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}", reservation.RowKey);
        Assert.Equal(now, reservation.RequestedAt);
        Assert.Equal(now, reservation.WindowStart);
        Assert.Empty(table.CommittedReservations);
        Assert.Empty(table.ReleasedRows);
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
            [
                ("tenant:tenant-default", "user-month:user-a:"),
                ("tenant:tenant-default", "burst:user-a:")
            ],
            table.DeletedPrefixes);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenMonthlyUserBudgetIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new RecordingRealtimeSessionRateLimitTable(rejectedRowKey: $"user-month:user-a:{Ticks("2026-08-01T00:00:00Z")}");
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
        Assert.Equal(2, table.Reservations.Count);
        Assert.Equal($"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}", table.Reservations[0].RowKey);
        Assert.Equal($"user-month:user-a:{Ticks("2026-08-01T00:00:00Z")}", table.Reservations[1].RowKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-01T00:00:00Z"), table.Reservations[1].WindowStart);
        Assert.Equal(
            [("tenant:tenant-default", $"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}")],
            table.ReleasedRows);
    }

    [Fact]
    public async Task EnsureAllowedRejectsWhenMonthlyTenantBudgetIsReached()
    {
        var now = DateTimeOffset.Parse("2026-08-30T10:00:00Z");
        var table = new RecordingRealtimeSessionRateLimitTable(rejectedRowKey: $"tenant-month:{Ticks("2026-08-01T00:00:00Z")}");
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
        Assert.Equal($"tenant-month:{Ticks("2026-08-01T00:00:00Z")}", reservation.RowKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-01T00:00:00Z"), reservation.WindowStart);
        Assert.Equal(
            [
                ("tenant:tenant-default", $"user-month:user-a:{Ticks("2026-08-01T00:00:00Z")}"),
                ("tenant:tenant-default", $"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}")
            ],
            table.ReleasedRows);
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

    [Fact]
    public async Task EnsureAllowedReservesSharedTenantBudgetWithoutBatchingDuplicateTenantRows()
    {
        var table = new RecordingRealtimeSessionRateLimitTable();
        var limiter = new TableRealtimeSessionRateLimiter(
            table,
            new FixedClock(DateTimeOffset.Parse("2026-08-30T10:00:00Z")),
            Options(monthlyTenantLimit: 10));

        await limiter.EnsureAllowedAsync(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CancellationToken.None);
        await limiter.EnsureAllowedAsync(
            TenantId.Create("tenant-default"),
            UserId.Create("user-b"),
            CancellationToken.None);

        Assert.Equal(6, table.Reservations.Count);
        Assert.Equal(2, table.Reservations.Count(reservation =>
            reservation.RowKey == $"tenant-month:{Ticks("2026-08-01T00:00:00Z")}"));
        Assert.Empty(table.ReleasedRows);
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

    private sealed class RecordingRealtimeSessionRateLimitTable(string? rejectedRowKey = null) : IRealtimeSessionRateLimitTable
    {
        public List<Reservation> Reservations { get; } = [];
        public List<Reservation> CommittedReservations { get; } = [];
        public List<(string PartitionKey, string RowKey)> ReleasedRows { get; } = [];

        public Task<RealtimeSessionRateLimitReservationResult> TryReserveAsync(
            string partitionKey,
            RealtimeSessionRateLimitReservation reservation,
            CancellationToken cancellationToken)
        {
            Reservations.Add(new Reservation(
                partitionKey,
                reservation.RowKey,
                reservation.WindowStart,
                reservation.MaxRequests,
                reservation.RequestedAt));
            if (string.Equals(reservation.RowKey, rejectedRowKey, StringComparison.Ordinal))
            {
                return Task.FromResult(RealtimeSessionRateLimitReservationResult.Rejected(reservation.RowKey));
            }

            CommittedReservations.Add(new Reservation(
                partitionKey,
                reservation.RowKey,
                reservation.WindowStart,
                reservation.MaxRequests,
                reservation.RequestedAt));
            return Task.FromResult(RealtimeSessionRateLimitReservationResult.Success);
        }

        public Task ReleaseAsync(
            string partitionKey,
            string rowKey,
            CancellationToken cancellationToken)
        {
            ReleasedRows.Add((partitionKey, rowKey));
            var index = CommittedReservations.FindIndex(reservation =>
                reservation.PartitionKey == partitionKey && reservation.RowKey == rowKey);
            if (index >= 0)
            {
                CommittedReservations.RemoveAt(index);
            }

            return Task.CompletedTask;
        }

        public List<(string PartitionKey, string RowKeyPrefix)> DeletedPrefixes { get; } = [];

        public Task DeleteRowsWithPrefixAsync(
            string partitionKey,
            string rowKeyPrefix,
            CancellationToken cancellationToken)
        {
            DeletedPrefixes.Add((partitionKey, rowKeyPrefix));
            return Task.CompletedTask;
        }
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
                    return reservedCounts.GetValueOrDefault($"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}");
                }
            }
        }

        public Task<RealtimeSessionRateLimitReservationResult> TryReserveAsync(
            string partitionKey,
            RealtimeSessionRateLimitReservation reservation,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                if (reservedCounts.GetValueOrDefault(reservation.RowKey) >= reservation.MaxRequests)
                {
                    return Task.FromResult(RealtimeSessionRateLimitReservationResult.Rejected(reservation.RowKey));
                }

                reservedCounts[reservation.RowKey] = reservedCounts.GetValueOrDefault(reservation.RowKey) + 1;
                return Task.FromResult(RealtimeSessionRateLimitReservationResult.Success);
            }
        }

        public Task ReleaseAsync(
            string partitionKey,
            string rowKey,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                var count = reservedCounts.GetValueOrDefault(rowKey);
                if (count <= 1)
                {
                    reservedCounts.Remove(rowKey);
                }
                else
                {
                    reservedCounts[rowKey] = count - 1;
                }
            }

            return Task.CompletedTask;
        }

        public Task DeleteRowsWithPrefixAsync(
            string partitionKey,
            string rowKeyPrefix,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed record Reservation(
        string PartitionKey,
        string RowKey,
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

    private static string Ticks(string instant) => DateTimeOffset.Parse(instant).UtcTicks.ToString("D19");

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
