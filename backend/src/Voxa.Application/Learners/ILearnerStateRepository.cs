using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

public interface ILearnerStateRepository
{
    Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken);

    Task<LearnerState?> GetAsync(
        TenantId tenantId,
        UserId userId,
        string targetLanguage,
        CancellationToken cancellationToken) =>
        GetAsync(tenantId, userId, cancellationToken);

    async Task<IReadOnlyList<LearnerState>> ListAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken)
    {
        var state = await GetAsync(tenantId, userId, cancellationToken);
        return state is null ? Array.Empty<LearnerState>() : [state];
    }

    Task<string?> GetActiveLanguageAsync(
        TenantId tenantId,
        UserId userId,
        CancellationToken cancellationToken) =>
        Task.FromResult<string?>(null);

    Task SetActiveLanguageAsync(
        TenantId tenantId,
        UserId userId,
        string targetLanguage,
        CancellationToken cancellationToken) =>
        Task.CompletedTask;

    Task<LearnerState> SaveAsync(
        LearnerState state,
        LearnerStateVersion? expectedVersion,
        CancellationToken cancellationToken);

    Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken);
}
