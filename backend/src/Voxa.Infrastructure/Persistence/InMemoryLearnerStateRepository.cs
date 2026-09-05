using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.Persistence;

public sealed class InMemoryLearnerStateRepository : ILearnerStateRepository
{
    private readonly Lock gate = new();
    private readonly Dictionary<string, LearnerState> states = new();
    private readonly Dictionary<string, string> activeLanguages = new();

    public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            activeLanguages.TryGetValue(ScopeKey(tenantId, userId), out var activeLanguage);
            states.TryGetValue(Key(tenantId, userId, activeLanguage), out var state);
            state ??= states.Values.FirstOrDefault(candidate =>
                candidate.TenantId == tenantId && candidate.UserId == userId);
            return Task.FromResult(state);
        }
    }

    public Task<LearnerState?> GetAsync(
        TenantId tenantId,
        UserId userId,
        string targetLanguage,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (gate)
        {
            states.TryGetValue(Key(tenantId, userId, targetLanguage), out var state);
            return Task.FromResult(state);
        }
    }

    public Task<IReadOnlyList<LearnerState>> ListAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (gate)
        {
            IReadOnlyList<LearnerState> result = states.Values
                .Where(state => state.TenantId == tenantId && state.UserId == userId)
                .OrderBy(state => state.Profile.TargetLanguage, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            return Task.FromResult(result);
        }
    }

    public Task<string?> GetActiveLanguageAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (gate)
        {
            activeLanguages.TryGetValue(ScopeKey(tenantId, userId), out var language);
            return Task.FromResult(language);
        }
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

        lock (gate)
        {
            activeLanguages[ScopeKey(tenantId, userId)] = state.Profile.TargetLanguage;
        }
    }

    public Task<LearnerState> SaveAsync(
        LearnerState state,
        LearnerStateVersion? expectedVersion,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            var key = Key(state.TenantId, state.UserId, state.Profile.TargetLanguage);
            states.TryGetValue(key, out var current);

            if (current is not null && expectedVersion != current.Version)
            {
                throw new StaleLearnerStateVersionException(
                    state.TenantId,
                    state.UserId,
                    expectedVersion,
                    current.Version);
            }

            if (current is null && expectedVersion is not null)
            {
                throw new StaleLearnerStateVersionException(
                    state.TenantId,
                    state.UserId,
                    expectedVersion,
                    LearnerStateVersion.Create(0));
            }

            var nextVersion = current is null ? LearnerStateVersion.Create(1) : current.Version.Next();
            var saved = state.WithVersion(nextVersion);
            states[key] = saved;
            return Task.FromResult(saved);
        }
    }

    public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            foreach (var key in states.Keys
                         .Where(key => key.StartsWith(ScopeKey(tenantId, userId) + ":", StringComparison.Ordinal))
                         .ToArray())
            {
                states.Remove(key);
            }
            activeLanguages.Remove(ScopeKey(tenantId, userId));
            return Task.CompletedTask;
        }
    }

    private static string ScopeKey(TenantId tenantId, UserId userId) => $"{tenantId.Value}:{userId.Value}";

    private static string Key(TenantId tenantId, UserId userId, string? targetLanguage) =>
        $"{ScopeKey(tenantId, userId)}:{targetLanguage?.Trim().ToLowerInvariant() ?? "legacy"}";
}
