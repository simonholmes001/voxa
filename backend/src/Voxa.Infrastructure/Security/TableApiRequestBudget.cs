using Voxa.Application.Realtime;
using Voxa.Application.Security;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.Persistence;
using Voxa.Infrastructure.Realtime;

namespace Voxa.Infrastructure.Security;

public sealed record ApiRequestBudgetOptions(int MaxRequests, int MonthlyUserLimit, int MonthlyTenantLimit);

public sealed class TableApiRequestBudget(
    IRealtimeSessionRateLimitTable table,
    ISystemClock clock,
    ApiRequestBudgetOptions options) : IApiRequestBudget
{
    // Use the existing ETag-backed reservation engine, with a separate partition namespace.
    private readonly TableRealtimeSessionRateLimiter limiter = new(table, clock,
        new RealtimeSessionRateLimitOptions(options.MaxRequests, TimeSpan.FromMinutes(1),
            options.MonthlyUserLimit, options.MonthlyTenantLimit), partitionPrefix: "api:");

    public async Task EnsureAllowedAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
    {
        try
        {
            await limiter.EnsureAllowedAsync(tenantId, userId, cancellationToken);
        }
        catch (RealtimeSessionRateLimitException exception)
        {
            throw new ApiRequestBudgetExceededException(exception.Code == "realtime_session_rate_limited"
                ? "api_request_rate_limited" : "api_request_budget_exhausted");
        }
    }

    public Task DeleteForSubjectAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        => limiter.DeleteForSubjectAsync(tenantId, userId, cancellationToken);
}
