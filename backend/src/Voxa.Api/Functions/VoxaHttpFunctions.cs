using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Onboarding;
using Voxa.Infrastructure.Authentication;

namespace Voxa.Api.Functions;

public sealed class VoxaHttpFunctions(
    SignInWithAppleEndpoint signInWithApple,
    RefreshAppSessionEndpoint refreshSession,
    LogoutAppSessionEndpoint logout,
    RealtimeSessionEndpoint realtimeSession,
    ResumeSessionEndpoint resumeSession,
    OnboardingSubmitEndpoint onboardingSubmit,
    IAppSessionTokenValidator tokenValidator,
    ISystemClock clock)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Function("auth-apple")]
    public async Task<HttpResponseData> SignInWithAppleAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/apple")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<SignInWithAppleHttpRequest>(request, cancellationToken);
        if (body.Malformed)
        {
            return await WriteInvalidJsonAsync(request, cancellationToken);
        }

        return await WriteAsync(
            request,
            await signInWithApple.PostAsync(
                body.Value ?? new SignInWithAppleHttpRequest(null, null, null),
                CorrelationId(request),
                cancellationToken),
            cancellationToken);
    }

    [Function("auth-refresh")]
    public async Task<HttpResponseData> RefreshSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/refresh")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<RefreshAppSessionHttpRequest>(request, cancellationToken);
        if (body.Malformed)
        {
            return await WriteInvalidJsonAsync(request, cancellationToken);
        }

        return await WriteAsync(
            request,
            await refreshSession.PostAsync(
                body.Value ?? new RefreshAppSessionHttpRequest(null),
                CorrelationId(request),
                cancellationToken),
            cancellationToken);
    }

    [Function("auth-logout")]
    public async Task<HttpResponseData> LogoutAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/logout")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<LogoutAppSessionHttpRequest>(request, cancellationToken);
        if (body.Malformed)
        {
            return await WriteInvalidJsonAsync(request, cancellationToken);
        }

        return await WriteAsync(
            request,
            await logout.PostAsync(
                body.Value ?? new LogoutAppSessionHttpRequest(null),
                CorrelationId(request),
                cancellationToken),
            cancellationToken);
    }

    [Function("onboarding-submit")]
    public async Task<HttpResponseData> SubmitOnboardingAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "onboarding")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var principal = Principal(request);
        if (principal is null)
        {
            var correlationId = Domain.Learners.CorrelationId.Create(CorrelationId(request));
            return await WriteAsync(
                request,
                ApiResponse<OnboardingSubmitHttpResponse>.Failure(
                    401,
                    new ApiErrorResponse(
                        "app_session_required",
                        "An authenticated app session is required.",
                        correlationId.Value,
                        false)),
                cancellationToken);
        }

        var body = await ReadJsonAsync<OnboardingSubmitHttpRequest>(request, cancellationToken);
        if (body.Malformed)
        {
            return await WriteInvalidJsonAsync(request, cancellationToken);
        }

        return await WriteAsync(
            request,
            await onboardingSubmit.PostAsync(
                body.Value ?? new OnboardingSubmitHttpRequest(null, null, null, null, null),
                principal.TenantId,
                principal.UserId,
                CorrelationId(request),
                cancellationToken),
            cancellationToken);
    }

    [Function("realtime-session")]
    public async Task<HttpResponseData> IssueRealtimeSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "realtime/session")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<RealtimeSessionHttpRequest>(request, cancellationToken);
        if (body.Malformed)
        {
            return await WriteInvalidJsonAsync(request, cancellationToken);
        }

        return await WriteAsync(
            request,
            await realtimeSession.PostAsync(
                Principal(request),
                body.Value ?? new RealtimeSessionHttpRequest(null, null, null),
                CorrelationId(request),
                cancellationToken),
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

    [Function("health-deployment")]
    public async Task<HttpResponseData> DeploymentHealthAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health/deployment")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var markerPath = Environment.GetEnvironmentVariable("VOXA_DEPLOYMENT_MARKER_PATH")
            ?? Path.Combine(AppContext.BaseDirectory, "deployment-marker.json");

        if (!File.Exists(markerPath))
        {
            var response = request.CreateResponse(HttpStatusCode.ServiceUnavailable);
            await JsonSerializer.SerializeAsync(
                response.Body,
                new DeploymentMarkerResponse(null, null, null, "deployment_marker_missing"),
                JsonOptions,
                cancellationToken);
            return response;
        }

        await using var markerStream = File.OpenRead(markerPath);
        var marker = await JsonSerializer.DeserializeAsync<DeploymentMarkerResponse>(
            markerStream,
            JsonOptions,
            cancellationToken);

        var ok = request.CreateResponse(HttpStatusCode.OK);
        await JsonSerializer.SerializeAsync(
            ok.Body,
            marker ?? new DeploymentMarkerResponse(null, null, null, "deployment_marker_invalid"),
            JsonOptions,
            cancellationToken);
        return ok;
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

    private static async Task<JsonReadResult<T>> ReadJsonAsync<T>(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        try
        {
            return JsonReadResult<T>.Ok(await JsonSerializer.DeserializeAsync<T>(
                request.Body,
                JsonOptions,
                cancellationToken));
        }
        catch (JsonException)
        {
            return JsonReadResult<T>.Invalid();
        }
    }

    private static Task<HttpResponseData> WriteInvalidJsonAsync(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var correlationId = Domain.Learners.CorrelationId.Create(CorrelationId(request));
        return WriteAsync(
            request,
            ApiResponse<object>.Failure(
                400,
                new ApiErrorResponse(
                    "invalid_json",
                    "Request body is not valid JSON.",
                    correlationId.Value,
                    false)),
            cancellationToken);
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

    private sealed record JsonReadResult<T>(T? Value, bool Malformed)
    {
        public static JsonReadResult<T> Ok(T? value) => new(value, false);

        public static JsonReadResult<T> Invalid() => new(default, true);
    }

    private sealed record DeploymentMarkerResponse(
        string? Sha,
        string? RunId,
        string? RunAttempt,
        string? Error);
}
