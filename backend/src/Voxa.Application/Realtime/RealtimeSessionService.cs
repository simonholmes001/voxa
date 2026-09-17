namespace Voxa.Application.Realtime;

public sealed class RealtimeSessionService(
    IRealtimeClientSecretIssuer clientSecretIssuer,
    IRealtimeSessionRateLimiter rateLimiter,
    IRealtimeSessionAuditLog auditLog) : IRealtimeSessionService
{
    public async Task<RealtimeSessionCredential> IssueClientSecretAsync(
        RealtimeSessionCommand command,
        CancellationToken cancellationToken)
    {
        var settings = new RealtimeSessionSettingsContract(
            command.CoachingMode,
            command.ProficiencyBand,
            command.TargetLanguage,
            command.SessionIntent,
            command.FocusTitle,
            command.DueReviewCount,
            command.NativeLanguage,
            command.Voice ?? RealtimeSessionCommand.DefaultVoice,
            command.VoiceSpeed ?? 1.0,
            command.VoiceInstructions);

        try
        {
            await rateLimiter.EnsureAllowedAsync(command.TenantId, command.UserId, cancellationToken);
        }
        catch (RealtimeSessionRateLimitException exception)
        {
            await RecordAsync(command, settings, exception.Code, cancellationToken);
            throw new RealtimeSessionIssueException(
                exception.Message,
                exception.Code,
                statusCode: 429,
                retryable: true);
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
