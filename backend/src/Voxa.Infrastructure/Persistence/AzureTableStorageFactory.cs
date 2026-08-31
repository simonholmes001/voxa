using Azure;
using Azure.Data.Tables;
using Azure.Identity;
using Voxa.Application.Realtime;

namespace Voxa.Infrastructure.Persistence;

public static class AzureTableStorageFactory
{
    public static ILearnerStateTable CreateLearnerStateTable(string storageAccountName)
    {
        return new AzureLearnerStateTable(CreateTableClient(storageAccountName, "LearnerState"));
    }

    public static IRefreshSessionTable CreateRefreshSessionTable(string storageAccountName)
    {
        return new AzureRefreshSessionTable(CreateTableClient(storageAccountName, "RefreshSessions"));
    }

    public static IRealtimeSessionAuditTable CreateRealtimeSessionAuditTable(string storageAccountName)
    {
        return new AzureRealtimeSessionAuditTable(CreateTableClient(storageAccountName, "RealtimeSessionAudit"));
    }

    public static IRealtimeSessionRateLimitTable CreateRealtimeSessionRateLimitTable(string storageAccountName)
    {
        return new AzureRealtimeSessionRateLimitTable(CreateTableClient(storageAccountName, "RealtimeSessionRateLimit"));
    }

    private static TableClient CreateTableClient(string storageAccountName, string tableName)
    {
        if (string.IsNullOrWhiteSpace(storageAccountName))
        {
            throw new ArgumentException("Storage account name is required.", nameof(storageAccountName));
        }

        var tableClient = new TableClient(
            new Uri($"https://{storageAccountName}.table.core.windows.net"),
            tableName,
            new DefaultAzureCredential());
        return tableClient;
    }
}

public sealed class AzureLearnerStateTable(TableClient tableClient) : ILearnerStateTable
{
    public async Task<LearnerStateTableEntity?> GetAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken)
    {
        var response = await tableClient.GetEntityIfExistsAsync<TableEntity>(
            partitionKey,
            rowKey,
            cancellationToken: cancellationToken);

        if (!response.HasValue)
        {
            return null;
        }

        var entity = response.Value!;
        return new LearnerStateTableEntity(
            entity.PartitionKey,
            entity.RowKey,
            entity.ETag.ToString(),
            entity.GetInt64("Version")
                ?? throw new InvalidOperationException("Learner state table entity is missing Version."),
            entity.GetString("PayloadJson")
                ?? throw new InvalidOperationException("Learner state table entity is missing PayloadJson."));
    }

    public async Task UpsertAsync(
        LearnerStateTableEntity entity,
        string? expectedETag,
        CancellationToken cancellationToken)
    {
        var tableEntity = new TableEntity(entity.PartitionKey, entity.RowKey)
        {
            ["Version"] = entity.Version,
            ["PayloadJson"] = entity.PayloadJson
        };

        if (expectedETag is null)
        {
            await tableClient.AddEntityAsync(tableEntity, cancellationToken);
            return;
        }

        await tableClient.UpdateEntityAsync(
            tableEntity,
            new ETag(expectedETag),
            TableUpdateMode.Replace,
            cancellationToken);
    }
}

public sealed class AzureRefreshSessionTable(TableClient tableClient) : IRefreshSessionTable
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;

    public async Task<RefreshSessionTableEntity?> GetAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken)
    {
        var response = await tableClient.GetEntityIfExistsAsync<TableEntity>(
            partitionKey,
            rowKey,
            cancellationToken: cancellationToken);

        if (!response.HasValue)
        {
            return null;
        }

        var entity = response.Value!;
        return new RefreshSessionTableEntity(
            entity.PartitionKey,
            entity.RowKey,
            entity.GetDateTimeOffset("ExpiresAt")
                ?? throw new InvalidOperationException("Refresh session table entity is missing ExpiresAt."),
            entity.GetString("PayloadJson")
                ?? throw new InvalidOperationException("Refresh session table entity is missing PayloadJson."));
    }

    public Task UpsertAsync(
        RefreshSessionTableEntity entity,
        CancellationToken cancellationToken)
    {
        var tableEntity = new TableEntity(entity.PartitionKey, entity.RowKey)
        {
            ["ExpiresAt"] = entity.ExpiresAt,
            ["PayloadJson"] = entity.PayloadJson
        };

        return tableClient.UpsertEntityAsync(
            tableEntity,
            TableUpdateMode.Replace,
            cancellationToken);
    }

    public async Task DeleteAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken)
    {
        try
        {
            await tableClient.DeleteEntityAsync(
                partitionKey,
                rowKey,
                ETag.All,
                cancellationToken);
        }
        catch (RequestFailedException exception) when (exception.Status == 404)
        {
        }
    }
}

public interface IRealtimeSessionAuditTable
{
    Task AddAsync(
        RealtimeSessionAuditTableEntity entity,
        CancellationToken cancellationToken);
}

public sealed record RealtimeSessionAuditTableEntity(
    string PartitionKey,
    string RowKey,
    string CorrelationId,
    string TenantId,
    string UserId,
    string Outcome,
    string CoachingMode,
    string TargetLanguage,
    DateTimeOffset RecordedAt);

public sealed class AzureRealtimeSessionAuditTable(TableClient tableClient) : IRealtimeSessionAuditTable
{
    public Task AddAsync(
        RealtimeSessionAuditTableEntity entity,
        CancellationToken cancellationToken)
    {
        var tableEntity = new TableEntity(entity.PartitionKey, entity.RowKey)
        {
            ["CorrelationId"] = entity.CorrelationId,
            ["TenantId"] = entity.TenantId,
            ["UserId"] = entity.UserId,
            ["Outcome"] = entity.Outcome,
            ["CoachingMode"] = entity.CoachingMode,
            ["TargetLanguage"] = entity.TargetLanguage,
            ["RecordedAt"] = entity.RecordedAt
        };

        return tableClient.AddEntityAsync(tableEntity, cancellationToken);
    }
}

public interface IRealtimeSessionRateLimitTable
{
    Task<bool> TryReserveAsync(
        string partitionKey,
        DateTimeOffset windowStart,
        int maxRequests,
        DateTimeOffset requestedAt,
        CancellationToken cancellationToken);
}

public sealed record RealtimeSessionRateLimitTableEntity(
    string PartitionKey,
    string RowKey,
    DateTimeOffset WindowStart,
    DateTimeOffset LastRequestedAt,
    int Count,
    string ETag);

public sealed class AzureRealtimeSessionRateLimitTable(TableClient tableClient) : IRealtimeSessionRateLimitTable
{
    public async Task<bool> TryReserveAsync(
        string partitionKey,
        DateTimeOffset windowStart,
        int maxRequests,
        DateTimeOffset requestedAt,
        CancellationToken cancellationToken)
    {
        var rowKey = $"{windowStart.UtcTicks:D19}";
        for (var attempt = 0; attempt < 3; attempt++)
        {
            var response = await tableClient.GetEntityIfExistsAsync<TableEntity>(
                partitionKey,
                rowKey,
                cancellationToken: cancellationToken);

            if (!response.HasValue)
            {
                var newEntity = new TableEntity(partitionKey, rowKey)
                {
                    ["WindowStart"] = windowStart,
                    ["LastRequestedAt"] = requestedAt,
                    ["Count"] = 1
                };

                try
                {
                    await tableClient.AddEntityAsync(newEntity, cancellationToken);
                    return true;
                }
                catch (RequestFailedException exception) when (exception.Status == 409)
                {
                    continue;
                }
            }

            var entity = response.Value!;
            var count = entity.GetInt32("Count")
                ?? throw new InvalidOperationException("Realtime rate-limit table entity is missing Count.");
            if (count >= maxRequests)
            {
                return false;
            }

            entity["Count"] = count + 1;
            entity["LastRequestedAt"] = requestedAt;

            try
            {
                await tableClient.UpdateEntityAsync(
                    entity,
                    entity.ETag,
                    TableUpdateMode.Replace,
                    cancellationToken);
                return true;
            }
            catch (RequestFailedException exception) when (exception.Status == 412)
            {
                continue;
            }
        }

        throw new RealtimeSessionRateLimitException("Realtime session issue limit could not be reserved.");
    }
}
