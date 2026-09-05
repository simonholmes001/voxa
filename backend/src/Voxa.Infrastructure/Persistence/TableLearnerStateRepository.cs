using System.Text.Json;
using System.Text;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.Persistence;

public interface ILearnerStateTable
{
    Task<LearnerStateTableEntity?> GetAsync(string partitionKey, string rowKey, CancellationToken cancellationToken);

    Task UpsertAsync(
        LearnerStateTableEntity entity,
        string? expectedETag,
        CancellationToken cancellationToken);

    Task DeleteAsync(string partitionKey, string rowKey, CancellationToken cancellationToken);

    Task<IReadOnlyList<LearnerStateTableEntity>> ListAsync(string partitionKey, CancellationToken cancellationToken);
}

public sealed record LearnerStateTableEntity(
    string PartitionKey,
    string RowKey,
    string ETag,
    long Version,
    string PayloadJson);

public sealed class TableLearnerStateRepository(ILearnerStateTable table) : ILearnerStateRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<LearnerState?> GetAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        var partitionKey = PartitionKey(tenantId);
        var activeLanguage = await GetActiveLanguageAsync(tenantId, userId, cancellationToken);
        if (activeLanguage is not null)
        {
            return await GetAsync(tenantId, userId, activeLanguage, cancellationToken);
        }

        var entity = await table.GetAsync(partitionKey, LegacyRowKey(userId), cancellationToken);
        if (entity is not null)
        {
            return Deserialize(entity.PayloadJson).WithVersion(LearnerStateVersion.Create(entity.Version));
        }

        return (await ListAsync(tenantId, userId, cancellationToken)).FirstOrDefault();
    }

    public async Task<LearnerState?> GetAsync(
        TenantId tenantId,
        UserId userId,
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        var partitionKey = PartitionKey(tenantId);
        var entity = await table.GetAsync(partitionKey, ProfileRowKey(userId, targetLanguage), cancellationToken);
        if (entity is not null)
        {
            return Deserialize(entity.PayloadJson).WithVersion(LearnerStateVersion.Create(entity.Version));
        }

        // Existing single-profile rows used the user id as their row key.
        var legacy = await table.GetAsync(partitionKey, LegacyRowKey(userId), cancellationToken);
        if (legacy is null)
        {
            return null;
        }

        var legacyState = Deserialize(legacy.PayloadJson).WithVersion(LearnerStateVersion.Create(legacy.Version));
        return string.Equals(legacyState.Profile.TargetLanguage, targetLanguage, StringComparison.OrdinalIgnoreCase)
            ? legacyState
            : null;
    }

    public async Task<IReadOnlyList<LearnerState>> ListAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        var entities = await table.ListAsync(PartitionKey(tenantId), cancellationToken);
        return entities
            .Where(entity => !entity.RowKey.StartsWith("active:", StringComparison.Ordinal))
            .Select(entity => Deserialize(entity.PayloadJson).WithVersion(LearnerStateVersion.Create(entity.Version)))
            .Where(state => state.UserId == userId)
            .GroupBy(state => state.Profile.TargetLanguage, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(state => state.Version.Value).First())
            .OrderBy(state => state.Profile.TargetLanguage, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public async Task<string?> GetActiveLanguageAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        var marker = await table.GetAsync(PartitionKey(tenantId), ActiveRowKey(userId), cancellationToken);
        return marker is null ? null : DeserializeActiveLanguage(marker.PayloadJson);
    }

    public async Task SetActiveLanguageAsync(
        TenantId tenantId,
        UserId userId,
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        var state = await GetAsync(tenantId, userId, targetLanguage, cancellationToken);
        if (state is null)
        {
            throw new LearnerStateNotFoundException(tenantId, userId);
        }

        var partitionKey = PartitionKey(tenantId);
        var rowKey = ActiveRowKey(userId);
        var current = await table.GetAsync(partitionKey, rowKey, cancellationToken);
        var marker = new LearnerStateTableEntity(
            partitionKey,
            rowKey,
            Guid.NewGuid().ToString("n"),
            current?.Version ?? 0,
            JsonSerializer.Serialize(new ActiveLanguageDocument(state.Profile.TargetLanguage), JsonOptions));
        await table.UpsertAsync(marker, current?.ETag, cancellationToken);
    }

    public async Task<LearnerState> SaveAsync(
        LearnerState state,
        LearnerStateVersion? expectedVersion,
        CancellationToken cancellationToken)
    {
        var partitionKey = PartitionKey(state.TenantId);
        var rowKey = ProfileRowKey(state.UserId, state.Profile.TargetLanguage);
        var current = await table.GetAsync(partitionKey, rowKey, cancellationToken);
        var legacyRowKey = LegacyRowKey(state.UserId);
        var legacy = current is null
            ? await table.GetAsync(partitionKey, legacyRowKey, cancellationToken)
            : null;
        current ??= legacy;

        if (current is not null && expectedVersion != LearnerStateVersion.Create(current.Version))
        {
            throw new StaleLearnerStateVersionException(
                state.TenantId,
                state.UserId,
                expectedVersion,
                LearnerStateVersion.Create(current.Version));
        }

        if (current is null && expectedVersion is not null)
        {
            throw new StaleLearnerStateVersionException(
                state.TenantId,
                state.UserId,
                expectedVersion,
                LearnerStateVersion.Create(0));
        }

        var nextVersion = current is null ? LearnerStateVersion.Create(1) : LearnerStateVersion.Create(current.Version).Next();
        var saved = state.WithVersion(nextVersion);
        var entity = new LearnerStateTableEntity(
            partitionKey,
            rowKey,
            Guid.NewGuid().ToString("n"),
            nextVersion.Value,
            JsonSerializer.Serialize(LearnerStateDocument.FromDomain(saved), JsonOptions));

        await table.UpsertAsync(entity, current?.ETag, cancellationToken);
        if (legacy is not null)
        {
            await table.DeleteAsync(partitionKey, legacyRowKey, cancellationToken);
        }
        return saved;
    }

    public async Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
    {
        var partitionKey = PartitionKey(tenantId);
        var entities = await table.ListAsync(partitionKey, cancellationToken);
        var profilePrefix = ProfileRowPrefix(userId);
        foreach (var entity in entities.Where(entity =>
                     entity.RowKey == LegacyRowKey(userId)
                     || entity.RowKey == ActiveRowKey(userId)
                     || entity.RowKey.StartsWith(profilePrefix, StringComparison.Ordinal)))
        {
            await table.DeleteAsync(partitionKey, entity.RowKey, cancellationToken);
        }
    }

    private static LearnerState Deserialize(string payloadJson)
    {
        var document = JsonSerializer.Deserialize<LearnerStateDocument>(payloadJson, JsonOptions)
            ?? throw new InvalidOperationException("Learner state payload could not be deserialized.");
        return document.ToDomain();
    }

    private static string PartitionKey(TenantId tenantId) => tenantId.Value;

    private static string LegacyRowKey(UserId userId) => userId.Value;

    private static string ProfileRowPrefix(UserId userId) =>
        $"profile-{Convert.ToHexString(Encoding.UTF8.GetBytes(userId.Value))}-";

    private static string ProfileRowKey(UserId userId, string targetLanguage) =>
        $"{ProfileRowPrefix(userId)}{Convert.ToHexString(Encoding.UTF8.GetBytes(targetLanguage.Trim().ToLowerInvariant()))}";

    private static string ActiveRowKey(UserId userId) => $"active:{userId.Value}";

    private static string DeserializeActiveLanguage(string payloadJson) =>
        JsonSerializer.Deserialize<ActiveLanguageDocument>(payloadJson, JsonOptions)?.ActiveLanguageKey
        ?? throw new InvalidOperationException("Active language marker could not be deserialized.");
}

internal sealed record LearnerStateDocument(
    string TenantId,
    string UserId,
    long Version,
    LearnerProfileDocument Profile,
    ActiveLearningPlanDocument ActivePlan,
    LessonCheckpointDocument CurrentLesson,
    IReadOnlyList<ReviewQueueItemDocument> ReviewQueue,
    IReadOnlyList<SessionSummaryDocument> RecentSessions)
{
    public static LearnerStateDocument FromDomain(LearnerState state)
    {
        return new LearnerStateDocument(
            state.TenantId.Value,
            state.UserId.Value,
            state.Version.Value,
            new LearnerProfileDocument(
                state.Profile.TargetLanguage,
                state.Profile.NativeLanguage,
                state.Profile.ProficiencyLevel,
                state.Profile.Goals,
                state.Profile.DailyMinutes),
            new ActiveLearningPlanDocument(
                state.ActivePlan.PlanId,
                state.ActivePlan.Title,
                state.ActivePlan.KnowledgeUnitIds),
            new LessonCheckpointDocument(
                state.CurrentLesson.LessonId,
                state.CurrentLesson.KnowledgeUnitId,
                state.CurrentLesson.StepIndex,
                state.CurrentLesson.UpdatedAt),
            state.ReviewQueue.Items
                .Select(item => new ReviewQueueItemDocument(item.KnowledgeUnitId, item.DueAt, item.Priority))
                .ToArray(),
            state.RecentSessions.Items
                .Select(item => new SessionSummaryDocument(item.SessionId, item.StartedAt, item.DurationSeconds, item.LessonId))
                .ToArray());
    }

    public LearnerState ToDomain()
    {
        var tenantId = Domain.Learners.TenantId.Create(TenantId);
        var userId = Domain.Learners.UserId.Create(UserId);
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(
                tenantId,
                userId,
                Profile.TargetLanguage,
                Profile.NativeLanguage,
                Profile.ProficiencyLevel,
                Profile.Goals ?? [],
                Profile.DailyMinutes ?? 15),
            new ActiveLearningPlan(
                ActivePlan.PlanId,
                ActivePlan.Title,
                ActivePlan.KnowledgeUnitIds),
            new LessonCheckpoint(
                CurrentLesson.LessonId,
                CurrentLesson.KnowledgeUnitId,
                CurrentLesson.StepIndex,
                CurrentLesson.UpdatedAt),
            new ReviewQueue(ReviewQueue
                .Select(item => new ReviewQueueItem(item.KnowledgeUnitId, item.DueAt, item.Priority))
                .ToArray()),
            new RecentSessionSummaries(RecentSessions
                .Select(item => new SessionSummary(item.SessionId, item.StartedAt, item.DurationSeconds, item.LessonId))
                .ToArray()))
            .WithVersion(LearnerStateVersion.Create(Version));
    }
}

internal sealed record LearnerProfileDocument(
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel,
    IReadOnlyList<string>? Goals,
    int? DailyMinutes);

internal sealed record ActiveLanguageDocument(string ActiveLanguageKey);

internal sealed record ActiveLearningPlanDocument(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds);

internal sealed record LessonCheckpointDocument(
    string LessonId,
    string KnowledgeUnitId,
    int StepIndex,
    DateTimeOffset UpdatedAt);

internal sealed record ReviewQueueItemDocument(
    string KnowledgeUnitId,
    DateTimeOffset DueAt,
    int Priority);

internal sealed record SessionSummaryDocument(
    string SessionId,
    DateTimeOffset StartedAt,
    int DurationSeconds,
    string? LessonId);

public sealed class InMemoryLearnerStateTable : ILearnerStateTable
{
    private readonly Lock gate = new();
    private readonly Dictionary<string, LearnerStateTableEntity> entities = new();

    public Task<LearnerStateTableEntity?> GetAsync(
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
        LearnerStateTableEntity entity,
        string? expectedETag,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            var key = Key(entity.PartitionKey, entity.RowKey);
            entities.TryGetValue(key, out var current);

            if (current?.ETag != expectedETag)
            {
                throw new InvalidOperationException("Learner state table entity changed before save.");
            }

            entities[key] = entity;
            return Task.CompletedTask;
        }
    }

    public Task DeleteAsync(string partitionKey, string rowKey, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            entities.Remove(Key(partitionKey, rowKey));
            return Task.CompletedTask;
        }
    }

    public Task<IReadOnlyList<LearnerStateTableEntity>> ListAsync(string partitionKey, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (gate)
        {
            IReadOnlyList<LearnerStateTableEntity> result = entities.Values
                .Where(entity => entity.PartitionKey == partitionKey)
                .ToArray();
            return Task.FromResult(result);
        }
    }

    private static string Key(string partitionKey, string rowKey) => $"{partitionKey}:{rowKey}";
}
