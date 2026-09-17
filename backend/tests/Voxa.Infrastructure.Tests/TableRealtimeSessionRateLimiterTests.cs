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

        var batch = Assert.Single(table.Batches);
        Assert.Equal("tenant:tenant-default", batch.PartitionKey);
        Assert.Equal(3, batch.Reservations.Count);
        var reservation = batch.Reservations[0];
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

        var batch = Assert.Single(table.Batches);
        var reservation = batch.Reservations[0];
        Assert.Equal($"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}", reservation.RowKey);
        Assert.Equal(now, reservation.RequestedAt);
        Assert.Equal(now, reservation.WindowStart);
        Assert.Empty(table.CommittedReservations);
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
        var batch = Assert.Single(table.Batches);
        Assert.Equal($"burst:user-a:{Ticks("2026-08-30T10:00:00Z")}", batch.Reservations[0].RowKey);
        Assert.Equal($"user-month:user-a:{Ticks("2026-08-01T00:00:00Z")}", batch.Reservations[1].RowKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-01T00:00:00Z"), batch.Reservations[1].WindowStart);
        Assert.Empty(table.CommittedReservations);
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
        var batch = Assert.Single(table.Batches);
        Assert.Equal(3, batch.Reservations.Count);
        var reservation = batch.Reservations[2];
        Assert.Equal($"tenant-month:{Ticks("2026-08-01T00:00:00Z")}", reservation.RowKey);
        Assert.Equal(DateTimeOffset.Parse("2026-08-01T00:00:00Z"), reservation.WindowStart);
        Assert.Empty(table.CommittedReservations);
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

        var batch = Assert.Single(table.Batches);
        Assert.Equal(DateTimeOffset.Parse("2026-09-01T00:00:00Z"), batch.Reservations[1].WindowStart);
        Assert.Equal(DateTimeOffset.Parse("2026-09-01T00:00:00Z"), batch.Reservations[2].WindowStart);
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
        public List<ReservationBatch> Batches { get; } = [];
        public List<Reservation> CommittedReservations { get; } = [];

        public Task<RealtimeSessionRateLimitReservationResult> TryReserveAsync(
            string partitionKey,
            IReadOnlyList<RealtimeSessionRateLimitReservation> reservations,
            CancellationToken cancellationToken)
        {
            Batches.Add(new ReservationBatch(partitionKey, reservations.ToList()));
            var rejected = reservations.FirstOrDefault(reservation =>
                string.Equals(reservation.RowKey, rejectedRowKey, StringComparison.Ordinal));
            if (rejected is not null)
            {
                return Task.FromResult(RealtimeSessionRateLimitReservationResult.Rejected(rejected.RowKey));
            }

            CommittedReservations.AddRange(reservations.Select(reservation =>
                new Reservation(reservation.RowKey, reservation.WindowStart, reservation.MaxRequests, reservation.RequestedAt)));
            return Task.FromResult(RealtimeSessionRateLimitReservationResult.Success);
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
            IReadOnlyList<RealtimeSessionRateLimitReservation> reservations,
            CancellationToken cancellationToken)
        {
            lock (gate)
            {
                foreach (var reservation in reservations)
                {
                    if (reservedCounts.GetValueOrDefault(reservation.RowKey) >= reservation.MaxRequests)
                    {
                        return Task.FromResult(RealtimeSessionRateLimitReservationResult.Rejected(reservation.RowKey));
                    }
                }

                foreach (var reservation in reservations)
                {
                    reservedCounts[reservation.RowKey] = reservedCounts.GetValueOrDefault(reservation.RowKey) + 1;
                }

                return Task.FromResult(RealtimeSessionRateLimitReservationResult.Success);
            }
        }

        public Task DeleteRowsWithPrefixAsync(
            string partitionKey,
            string rowKeyPrefix,
            CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed record Reservation(
        string RowKey,
        DateTimeOffset WindowStart,
        int MaxRequests,
        DateTimeOffset RequestedAt);

    private sealed record ReservationBatch(
        string PartitionKey,
        IReadOnlyList<RealtimeSessionRateLimitReservation> Reservations);

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
