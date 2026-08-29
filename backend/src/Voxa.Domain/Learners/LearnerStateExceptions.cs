namespace Voxa.Domain.Learners;

public sealed class LearnerStateNotFoundException(TenantId tenantId, UserId userId)
    : InvalidOperationException($"Learner state was not found for tenant '{tenantId.Value}' and user '{userId.Value}'.")
{
    public TenantId TenantId { get; } = tenantId;

    public UserId UserId { get; } = userId;
}

public sealed class StaleLearnerStateVersionException(
    TenantId tenantId,
    UserId userId,
    LearnerStateVersion? expectedVersion,
    LearnerStateVersion actualVersion)
    : InvalidOperationException(
        $"Learner state for tenant '{tenantId.Value}' and user '{userId.Value}' has version {actualVersion.Value}, not {expectedVersion?.Value.ToString() ?? "null"}.")
{
    public TenantId TenantId { get; } = tenantId;

    public UserId UserId { get; } = userId;

    public LearnerStateVersion? ExpectedVersion { get; } = expectedVersion;

    public LearnerStateVersion ActualVersion { get; } = actualVersion;
}
