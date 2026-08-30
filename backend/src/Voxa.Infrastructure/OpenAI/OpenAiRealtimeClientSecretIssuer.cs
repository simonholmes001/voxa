using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Voxa.Application.Realtime;

namespace Voxa.Infrastructure.OpenAI;

public sealed record OpenAiRealtimeOptions(
    string ApiKey,
    string DefaultRealtimeModel,
    string DefaultReasoningEffort);

public sealed class OpenAiRealtimeClientSecretIssuer(
    HttpClient httpClient,
    OpenAiRealtimeOptions options) : IRealtimeClientSecretIssuer
{
    public async Task<RealtimeSessionCredential> IssueAsync(
        RealtimeSessionRequest request,
        CancellationToken cancellationToken)
    {
        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "v1/realtime/client_secrets")
        {
            Content = JsonContent.Create(new OpenAiRealtimeClientSecretRequest(
                new OpenAiRealtimeSessionRequest(
                    "realtime",
                    options.DefaultRealtimeModel,
                    new OpenAiRealtimeReasoning(options.DefaultReasoningEffort),
                    new OpenAiRealtimeSessionMetadata(
                        request.CorrelationId.Value,
                        request.Settings.CoachingMode,
                        request.Settings.ProficiencyBand,
                        request.Settings.TargetLanguage))))
        };
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", options.ApiKey);

        using var response = await httpClient.SendAsync(httpRequest, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new RealtimeSessionIssueException("OpenAI Realtime client secret request failed.");
        }

        var body = await response.Content.ReadFromJsonAsync<OpenAiRealtimeClientSecretResponse>(
            cancellationToken);
        if (body?.ClientSecret?.Value is null)
        {
            throw new RealtimeSessionIssueException("OpenAI Realtime client secret response was invalid.");
        }

        return new RealtimeSessionCredential(
            request.CorrelationId.Value,
            body.ClientSecret.Value,
            body.Session?.Model ?? options.DefaultRealtimeModel,
            options.DefaultReasoningEffort,
            DateTimeOffset.FromUnixTimeSeconds(body.ClientSecret.ExpiresAt),
            request.Settings);
    }
}

internal sealed record OpenAiRealtimeClientSecretRequest(
    [property: JsonPropertyName("session")] OpenAiRealtimeSessionRequest Session);

internal sealed record OpenAiRealtimeSessionRequest(
    [property: JsonPropertyName("type")] string Type,
    [property: JsonPropertyName("model")] string Model,
    [property: JsonPropertyName("reasoning")] OpenAiRealtimeReasoning Reasoning,
    [property: JsonPropertyName("metadata")] OpenAiRealtimeSessionMetadata Metadata);

internal sealed record OpenAiRealtimeReasoning(
    [property: JsonPropertyName("effort")] string Effort);

internal sealed record OpenAiRealtimeSessionMetadata(
    [property: JsonPropertyName("correlation_id")] string CorrelationId,
    [property: JsonPropertyName("coaching_mode")] string CoachingMode,
    [property: JsonPropertyName("proficiency_band")] string ProficiencyBand,
    [property: JsonPropertyName("target_language")] string TargetLanguage);

internal sealed record OpenAiRealtimeClientSecretResponse(
    [property: JsonPropertyName("client_secret")] OpenAiRealtimeClientSecret? ClientSecret,
    [property: JsonPropertyName("session")] OpenAiRealtimeSession? Session);

internal sealed record OpenAiRealtimeClientSecret(
    [property: JsonPropertyName("value")] string? Value,
    [property: JsonPropertyName("expires_at")] long ExpiresAt);

internal sealed record OpenAiRealtimeSession(
    [property: JsonPropertyName("model")] string? Model);
