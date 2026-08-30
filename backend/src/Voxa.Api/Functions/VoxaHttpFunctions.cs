using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Infrastructure.Authentication;

namespace Voxa.Api.Functions;

public sealed class VoxaHttpFunctions(
    SignInWithAppleEndpoint signInWithApple,
    RefreshAppSessionEndpoint refreshSession,
    LogoutAppSessionEndpoint logout,
    RealtimeSessionEndpoint realtimeSession,
    ResumeSessionEndpoint resumeSession,
    IAppSessionTokenValidator tokenValidator,
    ISystemClock clock)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Function("auth-apple")]
    public async Task<HttpResponseData> SignInWithAppleAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/apple")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<SignInWithAppleHttpRequest>(request, cancellationToken)
            ?? new SignInWithAppleHttpRequest(null, null, null);
        return await WriteAsync(
            request,
            await signInWithApple.PostAsync(body, CorrelationId(request), cancellationToken),
            cancellationToken);
    }

    [Function("auth-refresh")]
    public async Task<HttpResponseData> RefreshSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/refresh")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<RefreshAppSessionHttpRequest>(request, cancellationToken)
            ?? new RefreshAppSessionHttpRequest(null);
        return await WriteAsync(
            request,
            await refreshSession.PostAsync(body, CorrelationId(request), cancellationToken),
            cancellationToken);
    }

    [Function("auth-logout")]
    public async Task<HttpResponseData> LogoutAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/logout")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<LogoutAppSessionHttpRequest>(request, cancellationToken)
            ?? new LogoutAppSessionHttpRequest(null);
        return await WriteAsync(
            request,
            await logout.PostAsync(body, CorrelationId(request), cancellationToken),
            cancellationToken);
    }

    [Function("realtime-session")]
    public async Task<HttpResponseData> IssueRealtimeSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "realtime/session")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<RealtimeSessionHttpRequest>(request, cancellationToken)
            ?? new RealtimeSessionHttpRequest(null, null, null);
        return await WriteAsync(
            request,
            await realtimeSession.PostAsync(Principal(request), body, CorrelationId(request), cancellationToken),
            cancellationToken);
    }

    [Function("session-resume")]
    public async Task<HttpResponseData> ResumeSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "session/resume")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var principal = Principal(request);
        if (principal is null)
        {
            var correlationId = Domain.Learners.CorrelationId.Create(CorrelationId(request));
            return await WriteAsync(
                request,
                ApiResponse<ResumeCheckpointResponse>.Failure(
                    401,
                    new ApiErrorResponse(
                        "app_session_required",
                        "An authenticated app session is required.",
                        correlationId.Value,
                        false)),
                cancellationToken);
        }

        return await WriteAsync(
            request,
            await resumeSession.GetAsync(
                principal.TenantId.Value,
                principal.UserId.Value,
                CorrelationId(request),
                cancellationToken),
            cancellationToken);
    }

    private AppSessionPrincipal? Principal(HttpRequestData request)
    {
        var authorization = request.Headers.TryGetValues("Authorization", out var values)
            ? values.FirstOrDefault()
            : null;

        const string bearerPrefix = "Bearer ";
        if (authorization is null || !authorization.StartsWith(bearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return tokenValidator.ValidateAccessToken(authorization[bearerPrefix.Length..].Trim(), clock.UtcNow);
    }

    private static string? CorrelationId(HttpRequestData request)
    {
        return request.Headers.TryGetValues("X-Correlation-Id", out var values)
            ? values.FirstOrDefault()
            : null;
    }

    private static async Task<T?> ReadJsonAsync<T>(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        try
        {
            return await JsonSerializer.DeserializeAsync<T>(request.Body, JsonOptions, cancellationToken);
        }
        catch (JsonException)
        {
            return default;
        }
    }

    private static async Task<HttpResponseData> WriteAsync<T>(
        HttpRequestData request,
        ApiResponse<T> result,
        CancellationToken cancellationToken)
    {
        var response = request.CreateResponse((HttpStatusCode)result.StatusCode);
        object? payload = result.Body is not null ? result.Body : result.Error;
        await JsonSerializer.SerializeAsync<object?>(
            response.Body,
            payload,
            JsonOptions,
            cancellationToken);
        return response;
    }
}
