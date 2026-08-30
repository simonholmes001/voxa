using Voxa.Application.Realtime;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.Persistence;
using Voxa.Infrastructure.Realtime;

namespace Voxa.Infrastructure.Tests;

public sealed class TableRealtimeSessionAuditLogTests
{
    [Fact]
    public async Task RecordStoresAuditEventByTenantAndUser()
    {
        var table = new RecordingRealtimeSessionAuditTable();
        var audit = new TableRealtimeSessionAuditLog(
            table,
            new FixedClock(DateTimeOffset.Parse("2026-08-30T10:00:00Z")));

        await audit.RecordAsync(
            new RealtimeSessionAuditEvent(
                "corr-123",
                "tenant-default",
                "user-a",
                "issued",
                "tutor",
                "fr-FR"),
            CancellationToken.None);

        var entity = Assert.Single(table.Entities);
        Assert.Equal("tenant-default:user-a", entity.PartitionKey);
        Assert.Contains("corr-123", entity.RowKey, StringComparison.Ordinal);
        Assert.Equal("corr-123", entity.CorrelationId);
        Assert.Equal("issued", entity.Outcome);
        Assert.Equal("tutor", entity.CoachingMode);
        Assert.Equal("fr-FR", entity.TargetLanguage);
        Assert.Equal(DateTimeOffset.Parse("2026-08-30T10:00:00Z"), entity.RecordedAt);
    }

    private sealed class RecordingRealtimeSessionAuditTable : IRealtimeSessionAuditTable
    {
        public List<RealtimeSessionAuditTableEntity> Entities { get; } = [];

        public Task AddAsync(
            RealtimeSessionAuditTableEntity entity,
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
