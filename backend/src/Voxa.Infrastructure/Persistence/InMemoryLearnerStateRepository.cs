using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Infrastructure.Persistence;

public sealed class InMemoryLearnerStateRepository : ILearnerStateRepository
{
    private readonly Lock gate = new();
    private readonly Dictionary<string, LearnerState> states = new();

    public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (gate)
        {
            states.TryGetValue(Key(tenantId, userId), out var state);
            return Task.FromResult(state);
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
            var key = Key(state.TenantId, state.UserId);
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
            states.Remove(Key(tenantId, userId));
            return Task.CompletedTask;
        }
    }

    private static string Key(TenantId tenantId, UserId userId) => $"{tenantId.Value}:{userId.Value}";
}
