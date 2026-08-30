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
}

public sealed record RealtimeSessionRateLimitOptions(
    int MaxRequests,
    TimeSpan Window);

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
        var partitionKey = $"{tenantId.Value}:{userId.Value}";
        var count = await rateLimitTable.CountSinceAsync(
            partitionKey,
            now.Subtract(options.Window),
            cancellationToken);

        if (count >= options.MaxRequests)
        {
            throw new RealtimeSessionRateLimitException("Realtime session issue limit exceeded.");
        }

        await rateLimitTable.AddAsync(
            new RealtimeSessionRateLimitTableEntity(
                partitionKey,
                $"{now.UtcDateTime.Ticks:D19}:{Guid.NewGuid():N}",
                now),
            cancellationToken);
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
}
