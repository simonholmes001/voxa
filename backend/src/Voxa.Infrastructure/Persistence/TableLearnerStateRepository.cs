using System.Text.Json;
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
        var entity = await table.GetAsync(PartitionKey(tenantId), RowKey(userId), cancellationToken);
        return entity is null
            ? null
            : Deserialize(entity.PayloadJson).WithVersion(LearnerStateVersion.Create(entity.Version));
    }

    public async Task<LearnerState> SaveAsync(
        LearnerState state,
        LearnerStateVersion? expectedVersion,
        CancellationToken cancellationToken)
    {
        var partitionKey = PartitionKey(state.TenantId);
        var rowKey = RowKey(state.UserId);
        var current = await table.GetAsync(partitionKey, rowKey, cancellationToken);

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
        return saved;
    }

    private static LearnerState Deserialize(string payloadJson)
    {
        var document = JsonSerializer.Deserialize<LearnerStateDocument>(payloadJson, JsonOptions)
            ?? throw new InvalidOperationException("Learner state payload could not be deserialized.");
        return document.ToDomain();
    }

    private static string PartitionKey(TenantId tenantId) => tenantId.Value;

    private static string RowKey(UserId userId) => userId.Value;
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
                state.Profile.ProficiencyLevel),
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
                Profile.ProficiencyLevel),
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
    string ProficiencyLevel);

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

    private static string Key(string partitionKey, string rowKey) => $"{partitionKey}:{rowKey}";
}
