using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class AccountDataServiceTests
{
    [Fact]
    public async Task ExportAsyncReturnsPortableLearnerDataForAuthenticatedSubject()
    {
        var tenant = TenantId.Create("tenant-default");
        var user = UserId.Create("user-a");
        var learnerStates = new RecordingLearnerStateRepository();
        await learnerStates.SaveAsync(CreateState(tenant, user, "fr-FR"), null, CancellationToken.None);
        await learnerStates.SaveAsync(CreateState(tenant, user, "de-DE"), null, CancellationToken.None);
        var service = new AccountDataService(
            learnerStates,
            new RecordingRefreshSessionStore(),
            new RecordingRealtimeSessionAuditLog(),
            new RecordingRealtimeSessionRateLimiter());

        var export = await service.ExportAsync(
            new AppSessionPrincipal(tenant, user),
            CorrelationId.Create("corr-export"),
            CancellationToken.None);

        Assert.Equal("corr-export", export.CorrelationId);
        Assert.Equal("tenant-default", export.TenantId);
        Assert.Equal("user-a", export.UserId);
        Assert.Equal("2026-09-15", export.SchemaVersion);
        Assert.Equal(["de-DE", "fr-FR"], export.LanguageProfiles.Select(profile => profile.LanguageKey));
        Assert.All(export.LanguageProfiles, profile => Assert.NotEmpty(profile.ActivePlan.Lessons));
    }

    [Fact]
    public async Task DeleteAsyncRemovesLearnerStateAndAllRefreshSessionsForSubject()
    {
        var tenant = TenantId.Create("tenant-default");
        var user = UserId.Create("user-a");
        var learnerStates = new RecordingLearnerStateRepository();
        await learnerStates.SaveAsync(CreateState(tenant, user, "fr-FR"), null, CancellationToken.None);
        await learnerStates.SaveAsync(CreateState(tenant, user, "es-ES"), null, CancellationToken.None);
        var refreshSessions = new RecordingRefreshSessionStore();
        var auditLog = new RecordingRealtimeSessionAuditLog();
        var rateLimiter = new RecordingRealtimeSessionRateLimiter();
        var service = new AccountDataService(learnerStates, refreshSessions, auditLog, rateLimiter);

        var result = await service.DeleteAsync(
            new AppSessionPrincipal(tenant, user),
            CorrelationId.Create("corr-delete"),
            CancellationToken.None);

        Assert.True(result.Deleted);
        Assert.Equal(2, result.DeletedLanguageProfileCount);
        Assert.Empty(await learnerStates.ListAsync(tenant, user, CancellationToken.None));
        Assert.Equal(new VerifiedAppSessionSubject(tenant, user), refreshSessions.RevokedSubject);
        Assert.Equal((tenant, user), auditLog.DeletedSubject);
        Assert.Equal((tenant, user), rateLimiter.DeletedSubject);
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId, string targetLanguage)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, targetLanguage, "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlan(
                $"plan-{targetLanguage}",
                $"Survival {targetLanguage}",
                ["greetings"],
                [new PlannedLesson("lesson-1", "Basics", "Say hello", 1, 10, PlannedLessonStatus.Current)]),
            new LessonCheckpoint("lesson-1", "unit-1", 0, DateTimeOffset.Parse("2026-09-15T08:00:00Z")),
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private sealed class RecordingRefreshSessionStore : IRefreshSessionStore
    {
        public VerifiedAppSessionSubject? RevokedSubject { get; private set; }

        public Task StoreAsync(
            string refreshToken,
            VerifiedAppSessionSubject subject,
            DateTimeOffset expiresAt,
            CancellationToken cancellationToken) => Task.CompletedTask;

        public Task<VerifiedAppSessionSubject?> GetAsync(
            string refreshToken,
            CancellationToken cancellationToken) => Task.FromResult<VerifiedAppSessionSubject?>(null);

        public Task RevokeAsync(string refreshToken, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task RevokeAllAsync(
            VerifiedAppSessionSubject subject,
            CancellationToken cancellationToken)
        {
            RevokedSubject = subject;
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        private readonly List<LearnerState> states = [];

        public Task<LearnerState?> GetAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(states.FirstOrDefault(state =>
                state.TenantId == tenantId && state.UserId == userId));
        }

        public Task<IReadOnlyList<LearnerState>> ListAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken)
        {
            IReadOnlyList<LearnerState> result = states
                .Where(state => state.TenantId == tenantId && state.UserId == userId)
                .OrderBy(state => state.Profile.TargetLanguage, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            return Task.FromResult(result);
        }

        public Task<LearnerState> SaveAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            states.RemoveAll(existing =>
                existing.TenantId == state.TenantId
                && existing.UserId == state.UserId
                && string.Equals(
                    existing.Profile.TargetLanguage,
                    state.Profile.TargetLanguage,
                    StringComparison.OrdinalIgnoreCase));
            states.Add(state);
            return Task.FromResult(state);
        }

        public Task DeleteAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken)
        {
            states.RemoveAll(state => state.TenantId == tenantId && state.UserId == userId);
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingRealtimeSessionAuditLog : IRealtimeSessionAuditLog
    {
        public (TenantId TenantId, UserId UserId)? DeletedSubject { get; private set; }

        public Task RecordAsync(
            RealtimeSessionAuditEvent auditEvent,
            CancellationToken cancellationToken) => Task.CompletedTask;

        public Task DeleteForSubjectAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken)
        {
            DeletedSubject = (tenantId, userId);
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingRealtimeSessionRateLimiter : IRealtimeSessionRateLimiter
    {
        public (TenantId TenantId, UserId UserId)? DeletedSubject { get; private set; }

        public Task EnsureAllowedAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken) => Task.CompletedTask;

        public Task DeleteForSubjectAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken)
        {
            DeletedSubject = (tenantId, userId);
            return Task.CompletedTask;
        }
    }
}
