using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

public interface ILearnerStateRepository
{
    Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken);

    Task<LearnerState> SaveAsync(
        LearnerState state,
        LearnerStateVersion? expectedVersion,
        CancellationToken cancellationToken);
}
