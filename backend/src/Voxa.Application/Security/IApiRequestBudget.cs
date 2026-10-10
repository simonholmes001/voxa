using Voxa.Domain.Learners;

namespace Voxa.Application.Security;

public interface IApiRequestBudget
{
    Task EnsureAllowedAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken);
    Task DeleteForSubjectAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken);
}

public sealed class ApiRequestBudgetExceededException(string code) : Exception("API request budget exceeded.")
{
    public string Code { get; } = code;
}
