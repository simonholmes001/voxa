namespace Voxa.Application.Realtime;

public sealed class RealtimeSessionService(
    IRealtimeClientSecretIssuer clientSecretIssuer,
    IRealtimeSessionRateLimiter rateLimiter,
    IRealtimeSessionAuditLog auditLog) : IRealtimeSessionService
{
    private static readonly HashSet<string> SupportedCoachingModes = new(StringComparer.OrdinalIgnoreCase)
    {
        "tutor"
    };

    public async Task<RealtimeSessionCredential> IssueClientSecretAsync(
        RealtimeSessionCommand command,
        CancellationToken cancellationToken)
    {
        if (!SupportedCoachingModes.Contains(command.CoachingMode))
        {
            throw new ArgumentException("Unsupported coaching mode for Realtime MVP.", nameof(command));
        }

        var settings = new RealtimeSessionSettingsContract(
            command.CoachingMode,
            command.ProficiencyBand,
            command.TargetLanguage);

        try
        {
            await rateLimiter.EnsureAllowedAsync(command.TenantId, command.UserId, cancellationToken);
        }
        catch (RealtimeSessionRateLimitException exception)
        {
            await RecordAsync(command, settings, "rate_limited", cancellationToken);
            throw new RealtimeSessionIssueException(exception.Message);
        }

        var credential = await clientSecretIssuer.IssueAsync(
            new RealtimeSessionRequest(
                command.TenantId,
                command.UserId,
                command.CorrelationId,
                settings),
            cancellationToken);
        await RecordAsync(command, settings, "issued", cancellationToken);
        return credential;
    }

    private Task RecordAsync(
        RealtimeSessionCommand command,
        RealtimeSessionSettingsContract settings,
        string outcome,
        CancellationToken cancellationToken)
    {
        return auditLog.RecordAsync(
            new RealtimeSessionAuditEvent(
                command.CorrelationId.Value,
                command.TenantId.Value,
                command.UserId.Value,
                outcome,
                settings.CoachingMode,
                settings.TargetLanguage),
            cancellationToken);
    }
}
