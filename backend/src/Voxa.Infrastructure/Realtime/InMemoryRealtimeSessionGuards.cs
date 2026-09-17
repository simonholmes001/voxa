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
        var monthlyWindowStart = MonthStart(now);
        await ReserveAsync(
            $"user:{tenantId.Value}:{userId.Value}:burst",
            WindowStart(now, options.Window),
            options.MaxRequests,
            now,
            "Realtime session issue limit exceeded.",
            "realtime_session_rate_limited",
            cancellationToken);
        await ReserveAsync(
            $"user:{tenantId.Value}:{userId.Value}:month",
            monthlyWindowStart,
            options.MonthlyUserSessionLimit,
            now,
            "Monthly realtime session budget exhausted.",
            "realtime_session_budget_exhausted",
            cancellationToken);
        await ReserveAsync(
            $"tenant:{tenantId.Value}:month",
            monthlyWindowStart,
            options.MonthlyTenantSessionLimit,
            now,
            "Tenant monthly realtime session budget exhausted.",
            "realtime_session_budget_exhausted",
            cancellationToken);
    }

    private async Task ReserveAsync(
        string partitionKey,
        DateTimeOffset windowStart,
        int maxRequests,
        DateTimeOffset requestedAt,
        string rejectionMessage,
        string rejectionCode,
        CancellationToken cancellationToken)
    {
        if (maxRequests <= 0)
        {
            throw new RealtimeSessionRateLimitException(rejectionMessage, rejectionCode);
        }

        var reserved = await rateLimitTable.TryReserveAsync(
            partitionKey,
            windowStart,
            maxRequests,
            requestedAt,
            cancellationToken);
        if (!reserved)
        {
            throw new RealtimeSessionRateLimitException(rejectionMessage, rejectionCode);
        }
    }

    public async Task DeleteForSubjectAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        await rateLimitTable.DeletePartitionAsync(
            $"user:{tenantId.Value}:{userId.Value}:month",
            cancellationToken);
        await rateLimitTable.DeletePartitionAsync(
            $"user:{tenantId.Value}:{userId.Value}:burst",
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
