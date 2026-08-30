using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class RealtimeSessionServiceTests
{
    [Fact]
    public async Task IssueClientSecretScopesApprovedSessionSettingsAndAuditsSuccess()
    {
        var issuer = new StubRealtimeClientSecretIssuer();
        var rateLimiter = new RecordingRealtimeSessionRateLimiter();
        var audit = new RecordingRealtimeSessionAuditLog();
        var service = new RealtimeSessionService(issuer, rateLimiter, audit);

        var credential = await service.IssueClientSecretAsync(CreateCommand(), CancellationToken.None);

        Assert.Equal("realtime-client-secret", credential.ClientSecret);
        Assert.Equal("gpt-realtime-2.1", credential.Model);
        Assert.Equal("low", credential.ReasoningEffort);
        Assert.Equal("tutor", issuer.Settings?.CoachingMode);
        Assert.Equal("B1-B2", issuer.Settings?.ProficiencyBand);
        Assert.Equal("fr-FR", issuer.Settings?.TargetLanguage);
        Assert.Equal("user-a", rateLimiter.CheckedUserId);
        Assert.Equal("issued", audit.Events.Single().Outcome);
    }

    [Fact]
    public async Task IssueClientSecretRejectsUnsupportedCoachingModeBeforeOpenAiCall()
    {
        var issuer = new StubRealtimeClientSecretIssuer();
        var service = new RealtimeSessionService(
            issuer,
            new RecordingRealtimeSessionRateLimiter(),
            new RecordingRealtimeSessionAuditLog());

        await Assert.ThrowsAsync<ArgumentException>(() =>
            service.IssueClientSecretAsync(CreateCommand(coachingMode: "strict"), CancellationToken.None));

        Assert.Null(issuer.Settings);
    }

    [Fact]
    public async Task IssueClientSecretAuditsAndRejectsWhenRateLimited()
    {
        var audit = new RecordingRealtimeSessionAuditLog();
        var service = new RealtimeSessionService(
            new StubRealtimeClientSecretIssuer(),
            new RecordingRealtimeSessionRateLimiter { Reject = true },
            audit);

        await Assert.ThrowsAsync<RealtimeSessionIssueException>(() =>
            service.IssueClientSecretAsync(CreateCommand(), CancellationToken.None));

        Assert.Equal("rate_limited", audit.Events.Single().Outcome);
    }

    private static RealtimeSessionCommand CreateCommand(string coachingMode = "tutor")
    {
        return RealtimeSessionCommand.Create(
            "tenant-default",
            "user-a",
            coachingMode,
            "B1-B2",
            "fr-FR",
            CorrelationId.Create("corr-123"));
    }

    private sealed class StubRealtimeClientSecretIssuer : IRealtimeClientSecretIssuer
    {
        public RealtimeSessionSettingsContract? Settings { get; private set; }

        public Task<RealtimeSessionCredential> IssueAsync(
            RealtimeSessionRequest request,
            CancellationToken cancellationToken)
        {
            Settings = request.Settings;
            return Task.FromResult(new RealtimeSessionCredential(
                request.CorrelationId.Value,
                "realtime-client-secret",
                "gpt-realtime-2.1",
                "low",
                DateTimeOffset.Parse("2026-08-29T08:20:00Z"),
                request.Settings));
        }
    }

    private sealed class RecordingRealtimeSessionRateLimiter : IRealtimeSessionRateLimiter
    {
        public bool Reject { get; init; }

        public string? CheckedUserId { get; private set; }

        public Task EnsureAllowedAsync(
            TenantId tenantId,
            UserId userId,
            CancellationToken cancellationToken)
        {
            CheckedUserId = userId.Value;
            if (Reject)
            {
                throw new RealtimeSessionRateLimitException("Rate limit exceeded.");
            }

            return Task.CompletedTask;
        }
    }

    private sealed class RecordingRealtimeSessionAuditLog : IRealtimeSessionAuditLog
    {
        public List<RealtimeSessionAuditEvent> Events { get; } = [];

        public Task RecordAsync(RealtimeSessionAuditEvent auditEvent, CancellationToken cancellationToken)
        {
            Events.Add(auditEvent);
            return Task.CompletedTask;
        }
    }
}
