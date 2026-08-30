using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Voxa.Application.Authentication;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.Persistence;

public interface IRefreshSessionTable
{
    DateTimeOffset UtcNow { get; }

    Task<RefreshSessionTableEntity?> GetAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken);

    Task UpsertAsync(
        RefreshSessionTableEntity entity,
        CancellationToken cancellationToken);

    Task DeleteAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken);
}

public sealed record RefreshSessionTableEntity(
    string PartitionKey,
    string RowKey,
    DateTimeOffset ExpiresAt,
    string PayloadJson);

public sealed class TableRefreshSessionStore(IRefreshSessionTable table) : IRefreshSessionStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private const string PartitionKey = "refresh-session";

    public Task StoreAsync(
        string refreshToken,
        VerifiedAppSessionSubject subject,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken)
    {
        return table.UpsertAsync(
            new RefreshSessionTableEntity(
                PartitionKey,
                TokenRowKey(refreshToken),
                expiresAt,
                JsonSerializer.Serialize(RefreshSessionDocument.FromSubject(subject), JsonOptions)),
            cancellationToken);
    }

    public async Task<VerifiedAppSessionSubject?> GetAsync(
        string refreshToken,
        CancellationToken cancellationToken)
    {
        var entity = await table.GetAsync(PartitionKey, TokenRowKey(refreshToken), cancellationToken);
        if (entity is null)
        {
            return null;
        }

        if (entity.ExpiresAt <= table.UtcNow)
        {
            await table.DeleteAsync(PartitionKey, TokenRowKey(refreshToken), cancellationToken);
            return null;
        }

        var document = JsonSerializer.Deserialize<RefreshSessionDocument>(entity.PayloadJson, JsonOptions)
            ?? throw new InvalidOperationException("Refresh session payload could not be deserialized.");
        return document.ToSubject();
    }

    public Task RevokeAsync(string refreshToken, CancellationToken cancellationToken)
    {
        return table.DeleteAsync(PartitionKey, TokenRowKey(refreshToken), cancellationToken);
    }

    private static string TokenRowKey(string refreshToken)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(refreshToken));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}

public sealed class InMemoryRefreshSessionTable(
    DateTimeOffset? utcNow = null) : IRefreshSessionTable
{
    private readonly Lock gate = new();
    private readonly Dictionary<string, RefreshSessionTableEntity> entities = new();

    public DateTimeOffset UtcNow { get; } = utcNow ?? DateTimeOffset.Parse("2026-08-29T08:00:00Z");

    public Task<RefreshSessionTableEntity?> GetAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            entities.TryGetValue(Key(partitionKey, rowKey), out var entity);
            return Task.FromResult(entity);
        }
    }

    public Task UpsertAsync(
        RefreshSessionTableEntity entity,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            entities[Key(entity.PartitionKey, entity.RowKey)] = entity;
            return Task.CompletedTask;
        }
    }

    public Task DeleteAsync(
        string partitionKey,
        string rowKey,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            entities.Remove(Key(partitionKey, rowKey));
            return Task.CompletedTask;
        }
    }

    private static string Key(string partitionKey, string rowKey) => $"{partitionKey}:{rowKey}";
}

internal sealed record RefreshSessionDocument(
    string TenantId,
    string UserId)
{
    public static RefreshSessionDocument FromSubject(VerifiedAppSessionSubject subject)
    {
        return new RefreshSessionDocument(subject.TenantId.Value, subject.UserId.Value);
    }

    public VerifiedAppSessionSubject ToSubject()
    {
        return new VerifiedAppSessionSubject(
            TenantId: Domain.Learners.TenantId.Create(TenantId),
            UserId: Domain.Learners.UserId.Create(UserId));
    }
}
