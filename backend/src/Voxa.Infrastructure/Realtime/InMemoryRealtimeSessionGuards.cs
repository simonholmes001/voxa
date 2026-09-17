using Voxa.Application.Realtime;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Infrastructure.Realtime;

public sealed class InMemoryRealtimeSessionRateLimiter : IRealtimeSessionRateLimiter
{
    public Task EnsureAllowedAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.CompletedTask;
    }

    public Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.CompletedTask;
    }
}

public sealed record RealtimeSessionRateLimitOptions(
    int MaxRequests,
    TimeSpan Window,
    int MonthlyUserSessionLimit,
    int MonthlyTenantSessionLimit)
{
    public const int DefaultMaxRequests = 12;
    public static readonly TimeSpan DefaultWindow = TimeSpan.FromMinutes(1);
    public const int DefaultMonthlyUserSessionLimit = 600;
    public const int DefaultMonthlyTenantSessionLimit = 6_000;
}

public sealed class TableRealtimeSessionRateLimiter(
    IRealtimeSessionRateLimitTable rateLimitTable,
    ISystemClock clock,
    RealtimeSessionRateLimitOptions options) : IRealtimeSessionRateLimiter
{
    public async Task EnsureAllowedAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        var now = clock.UtcNow;
        EnsurePositiveLimit(options.MaxRequests, "Realtime session issue limit exceeded.", "realtime_session_rate_limited");
        EnsurePositiveLimit(options.MonthlyUserSessionLimit, "Monthly realtime session budget exhausted.", "realtime_session_budget_exhausted");
        EnsurePositiveLimit(options.MonthlyTenantSessionLimit, "Tenant monthly realtime session budget exhausted.", "realtime_session_budget_exhausted");

        var monthlyWindowStart = MonthStart(now);
        var partitionKey = TenantPartitionKey(tenantId);
        var reservations = new[]
        {
            new RealtimeSessionRateLimitReservation(
                BurstRowKey(userId, WindowStart(now, options.Window)),
                WindowStart(now, options.Window),
                options.MaxRequests,
                now),
            new RealtimeSessionRateLimitReservation(
                UserMonthRowKey(userId, monthlyWindowStart),
                monthlyWindowStart,
                options.MonthlyUserSessionLimit,
                now),
            new RealtimeSessionRateLimitReservation(
                TenantMonthRowKey(monthlyWindowStart),
                monthlyWindowStart,
                options.MonthlyTenantSessionLimit,
                now),
        };
        var committed = new List<RealtimeSessionRateLimitReservation>(reservations.Length);
        try
        {
            foreach (var reservation in reservations)
            {
                var result = await rateLimitTable.TryReserveAsync(
                    partitionKey,
                    reservation,
                    cancellationToken);

                if (result.Succeeded)
                {
                    committed.Add(reservation);
                    continue;
                }

                throw RejectionFor(result.RejectedRowKey);
            }
        }
        catch
        {
            await ReleaseCommittedAsync(partitionKey, committed, CancellationToken.None);
            throw;
        }
    }

    private async Task ReleaseCommittedAsync(
        string partitionKey,
        IReadOnlyList<RealtimeSessionRateLimitReservation> committed,
        CancellationToken cancellationToken)
    {
        for (var index = committed.Count - 1; index >= 0; index--)
        {
            await rateLimitTable.ReleaseAsync(
                partitionKey,
                committed[index].RowKey,
                cancellationToken);
        }
    }

    private static RealtimeSessionRateLimitException RejectionFor(string? rowKey)
    {
        if (rowKey?.StartsWith("burst:", StringComparison.Ordinal) == true)
        {
            return new RealtimeSessionRateLimitException(
                "Realtime session issue limit exceeded.",
                "realtime_session_rate_limited");
        }

        return new RealtimeSessionRateLimitException(
            "Monthly realtime session budget exhausted.",
            "realtime_session_budget_exhausted");
    }

    private static void EnsurePositiveLimit(int value, string rejectionMessage, string rejectionCode)
    {
        if (value <= 0)
        {
            throw new RealtimeSessionRateLimitException(rejectionMessage, rejectionCode);
        }
    }

    public async Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        await rateLimitTable.DeleteRowsWithPrefixAsync(
            TenantPartitionKey(tenantId),
            $"user-month:{userId.Value}:",
            cancellationToken);
        await rateLimitTable.DeleteRowsWithPrefixAsync(
            TenantPartitionKey(tenantId),
            $"burst:{userId.Value}:",
            cancellationToken);
    }

    private static DateTimeOffset WindowStart(DateTimeOffset now, TimeSpan window)
    {
        var ticks = now.UtcTicks - (now.UtcTicks % window.Ticks);
        return new DateTimeOffset(ticks, TimeSpan.Zero);
    }

    private static DateTimeOffset MonthStart(DateTimeOffset now)
    {
        var utc = now.UtcDateTime;
        return new DateTimeOffset(utc.Year, utc.Month, 1, 0, 0, 0, TimeSpan.Zero);
    }

    private static string TenantPartitionKey(TenantId tenantId) => $"tenant:{tenantId.Value}";

    private static string BurstRowKey(UserId userId, DateTimeOffset windowStart) =>
        $"burst:{userId.Value}:{windowStart.UtcTicks:D19}";

    private static string UserMonthRowKey(UserId userId, DateTimeOffset windowStart) =>
        $"user-month:{userId.Value}:{windowStart.UtcTicks:D19}";

    private static string TenantMonthRowKey(DateTimeOffset windowStart) =>
        $"tenant-month:{windowStart.UtcTicks:D19}";
}

public sealed class InMemoryRealtimeSessionAuditLog : IRealtimeSessionAuditLog
{
    public List<RealtimeSessionAuditEvent> Events { get; } = [];

    public Task RecordAsync(
        RealtimeSessionAuditEvent auditEvent,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Events.Add(auditEvent);
        return Task.CompletedTask;
    }

    public Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Events.RemoveAll(auditEvent =>
            string.Equals(auditEvent.TenantId, tenantId.Value, StringComparison.Ordinal)
            && string.Equals(auditEvent.UserId, userId.Value, StringComparison.Ordinal));
        return Task.CompletedTask;
    }
}

public sealed class TableRealtimeSessionAuditLog(
    IRealtimeSessionAuditTable auditTable,
    ISystemClock clock) : IRealtimeSessionAuditLog
{
    public Task RecordAsync(
        RealtimeSessionAuditEvent auditEvent,
        CancellationToken cancellationToken)
    {
        var recordedAt = clock.UtcNow;
        var partitionKey = $"{auditEvent.TenantId}:{auditEvent.UserId}";
        var rowKey = $"{DateTimeOffset.MaxValue.Ticks - recordedAt.UtcDateTime.Ticks:D19}:{auditEvent.CorrelationId}";

        return auditTable.AddAsync(
            new RealtimeSessionAuditTableEntity(
                partitionKey,
                rowKey,
                auditEvent.CorrelationId,
                auditEvent.TenantId,
                auditEvent.UserId,
                auditEvent.Outcome,
                auditEvent.CoachingMode,
                auditEvent.TargetLanguage,
                recordedAt),
            cancellationToken);
    }

    public Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        return auditTable.DeletePartitionAsync(
            $"{tenantId.Value}:{userId.Value}",
            cancellationToken);
    }
}
