using Voxa.Application.Realtime;
using Voxa.Application.Security;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.Persistence;
using Voxa.Infrastructure.Realtime;
using Voxa.Infrastructure.Security;

namespace Voxa.Infrastructure.Tests;

public sealed class TableApiRequestBudgetTests
{
    private static readonly TenantId Tenant = TenantId.Create("tenant-a");
    private static readonly UserId User = UserId.Create("user-a");
    private static readonly ISystemClock Clock = new FixedClock();

    [Theory]
    [InlineData(2, 100, "api_request_rate_limited")]
    [InlineData(100, 2, "api_request_budget_exhausted")]
    public async Task ParallelRequestsCannotExceedBurstOrMonthlyBudget(int burst, int monthly, string code)
    {
        var table = new AtomicTable();
        var budget = new TableApiRequestBudget(table, Clock, new(burst, monthly, 100));
        var results = await Task.WhenAll(Enumerable.Range(0, 10).Select(async _ =>
        {
            try { await budget.EnsureAllowedAsync(Tenant, User, CancellationToken.None); return true; }
            catch (ApiRequestBudgetExceededException error) { Assert.Equal(code, error.Code); return false; }
        }));

        Assert.Equal(2, results.Count(allowed => allowed));
        Assert.All(table.Counts.Values, count => Assert.Equal(2, count));
    }

    [Fact]
    public async Task ApiBudgetDoesNotConsumeRealtimeBudget()
    {
        var table = new AtomicTable();
        var budget = new TableApiRequestBudget(table, Clock, new(1, 1, 100));
        var realtime = new TableRealtimeSessionRateLimiter(table, Clock, new(1, TimeSpan.FromMinutes(1), 1, 100));

        await budget.EnsureAllowedAsync(Tenant, User, CancellationToken.None);
        await realtime.EnsureAllowedAsync(Tenant, User, CancellationToken.None);

        await Assert.ThrowsAsync<ApiRequestBudgetExceededException>(() => budget.EnsureAllowedAsync(Tenant, User, CancellationToken.None));
        await Assert.ThrowsAsync<RealtimeSessionRateLimitException>(() => realtime.EnsureAllowedAsync(Tenant, User, CancellationToken.None));
        Assert.Contains(table.Counts.Keys, key => key.Partition == "api:tenant:tenant-a");
        Assert.Contains(table.Counts.Keys, key => key.Partition == "tenant:tenant-a");
    }

    [Fact]
    public async Task CleanupAndLimitsAreScopedToTenantAndUser()
    {
        var table = new AtomicTable();
        var budget = new TableApiRequestBudget(table, Clock, new(1, 1, 100));
        var otherUser = UserId.Create("user-b");
        var otherTenant = TenantId.Create("tenant-b");
        await budget.EnsureAllowedAsync(Tenant, User, CancellationToken.None);
        await budget.EnsureAllowedAsync(Tenant, otherUser, CancellationToken.None);
        await budget.EnsureAllowedAsync(otherTenant, User, CancellationToken.None);

        await budget.DeleteForSubjectAsync(Tenant, User, CancellationToken.None);

        await budget.EnsureAllowedAsync(Tenant, User, CancellationToken.None);
        await Assert.ThrowsAsync<ApiRequestBudgetExceededException>(() => budget.EnsureAllowedAsync(Tenant, otherUser, CancellationToken.None));
        await Assert.ThrowsAsync<ApiRequestBudgetExceededException>(() => budget.EnsureAllowedAsync(otherTenant, User, CancellationToken.None));
    }

    [Fact]
    public async Task TenantBudgetIsSharedAcrossUsers()
    {
        var budget = new TableApiRequestBudget(new AtomicTable(), Clock, new(100, 100, 1));
        await budget.EnsureAllowedAsync(Tenant, User, CancellationToken.None);

        var error = await Assert.ThrowsAsync<ApiRequestBudgetExceededException>(() =>
            budget.EnsureAllowedAsync(Tenant, UserId.Create("user-b"), CancellationToken.None));

        Assert.Equal("api_request_budget_exhausted", error.Code);
    }

    private sealed class FixedClock : ISystemClock
    {
        public DateTimeOffset UtcNow => DateTimeOffset.Parse("2026-10-10T10:00:00Z");
    }

    private sealed class AtomicTable : IRealtimeSessionRateLimitTable
    {
        private readonly object gate = new();
        public Dictionary<(string Partition, string Row), int> Counts { get; } = [];

        public async Task<RealtimeSessionRateLimitReservationResult> TryReserveAsync(string partitionKey,
            RealtimeSessionRateLimitReservation reservation, CancellationToken cancellationToken)
        {
            await Task.Yield();
            cancellationToken.ThrowIfCancellationRequested();
            lock (gate)
            {
                var key = (partitionKey, reservation.RowKey);
                var count = Counts.GetValueOrDefault(key);
                if (count >= reservation.MaxRequests) return RealtimeSessionRateLimitReservationResult.Rejected(reservation.RowKey);
                Counts[key] = count + 1;
                return RealtimeSessionRateLimitReservationResult.Success;
            }
        }

        public Task ReleaseAsync(string partitionKey, string rowKey, CancellationToken cancellationToken)
        {
            lock (gate) Counts[(partitionKey, rowKey)]--;
            return Task.CompletedTask;
        }

        public Task DeleteRowsWithPrefixAsync(string partitionKey, string rowKeyPrefix, CancellationToken cancellationToken)
        {
            lock (gate)
                foreach (var key in Counts.Keys.Where(key => key.Partition == partitionKey && key.Row.StartsWith(rowKeyPrefix, StringComparison.Ordinal)).ToArray())
                    Counts.Remove(key);
            return Task.CompletedTask;
        }
    }
}
