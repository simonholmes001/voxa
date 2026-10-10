using System.Globalization;
using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Azure.Functions.Worker;
using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Onboarding;
using Voxa.Application.Security;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;

namespace Voxa.Api.Functions;

public sealed class VoxaHttpFunctions(
    SignInWithAppleEndpoint signInWithApple,
    RefreshAppSessionEndpoint refreshSession,
    LogoutAppSessionEndpoint logout,
    AccountDataEndpoint accountData,
    RealtimeSessionEndpoint realtimeSession,
    RealtimeDebriefEndpoint realtimeDebrief,
    LearnerPlanEndpoint learnerPlan,
    LearnerCourseEndpoint learnerCourse,
    CourseReassessmentEndpoint courseReassessment,
    LearningSessionCompletionEndpoint learningSessionCompletion,
    ResumeSessionEndpoint resumeSession,
    LanguageProfilesEndpoint languageProfiles,
    PracticeLanguageToolEndpoint practiceLanguageTools,
    OnboardingSubmitEndpoint onboardingSubmit,
    DevResetEndpoint devReset,
    IAppSessionTokenValidator tokenValidator,
    ISystemClock clock,
    IApiRequestBudget requestBudget)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Function("auth-apple")]
    public async Task<HttpResponseData> SignInWithAppleAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/apple")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var body = await ReadJsonAsync<SignInWithAppleHttpRequest>(request, cancellationToken);
        if (body.TooLarge)
        {
            return await WritePayloadTooLargeAsync(request, cancellationToken);
        }

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
        if (body.TooLarge)
        {
            return await WritePayloadTooLargeAsync(request, cancellationToken);
        }

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
        if (body.TooLarge)
        {
            return await WritePayloadTooLargeAsync(request, cancellationToken);
        }

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

    [Function("account-export")]
    public async Task<HttpResponseData> ExportAccountDataAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "account/export")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await accountData.ExportAsync(
                    principal,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("account-delete")]
    public async Task<HttpResponseData> DeleteAccountAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "delete", Route = "account")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await accountData.DeleteAsync(
                    principal,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("onboarding-submit")]
    public async Task<HttpResponseData> SubmitOnboardingAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "onboarding")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<OnboardingSubmitHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            var expectedVersion = ParseExpectedVersion(request);
            if (expectedVersion.IsPresent && !expectedVersion.IsValid)
            {
                return await WriteInvalidIfMatchAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await onboardingSubmit.PostAsync(
                    body.Value ?? new OnboardingSubmitHttpRequest(null, null, null, null, null),
                    principal.TenantId,
                    principal.UserId,
                    CorrelationId(request),
                    expectedVersion.Value,
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("realtime-session")]
    public async Task<HttpResponseData> IssueRealtimeSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "realtime/session")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<RealtimeSessionHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await realtimeSession.PostAsync(
                    principal,
                    body.Value ?? new RealtimeSessionHttpRequest(null, null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("realtime-debrief")]
    public async Task<HttpResponseData> GenerateRealtimeDebriefAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "realtime/debrief")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<SessionDebriefHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await realtimeDebrief.PostAsync(
                    principal,
                    body.Value ?? new SessionDebriefHttpRequest(null, null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("learner-plan")]
    public async Task<HttpResponseData> GetLearnerPlanAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "learner/plan")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await learnerPlan.GetAsync(
                    principal,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("learner-course")]
    public async Task<HttpResponseData> GetLearnerCourseAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "learner/course")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await learnerCourse.GetAsync(
                    principal,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("learner-course-reassess")]
    public async Task<HttpResponseData> ReassessLearnerCourseAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "learner/course/reassess")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<CourseReassessmentHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await courseReassessment.PostAsync(
                    principal,
                    body.Value,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("session-resume")]
    public async Task<HttpResponseData> ResumeSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "session/resume")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await resumeSession.GetAsync(
                    principal.TenantId.Value,
                    principal.UserId.Value,
                    CorrelationId(request),
                cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("session-complete")]
    public async Task<HttpResponseData> CompleteSessionAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "session/complete")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<LearningSessionCompletionHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await learningSessionCompletion.PostAsync(
                    principal,
                    body.Value ?? new LearningSessionCompletionHttpRequest(null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("language-profiles-list")]
    public async Task<HttpResponseData> ListLanguageProfilesAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "language-profiles")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await languageProfiles.GetAsync(
                    principal.TenantId,
                    principal.UserId,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("language-profile-select")]
    public async Task<HttpResponseData> SelectLanguageProfileAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "language-profiles/{languageKey}/select")] HttpRequestData request,
        string languageKey,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await languageProfiles.SelectAsync(
                    languageKey,
                    principal.TenantId,
                    principal.UserId,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("language-profile-delete")]
    public async Task<HttpResponseData> DeleteLanguageProfileAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "delete", Route = "language-profiles/{languageKey}")] HttpRequestData request,
        string languageKey,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await languageProfiles.DeleteAsync(
                    languageKey,
                    principal.TenantId,
                    principal.UserId,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    [Function("practice-vocabulary-quiz")]
    public async Task<HttpResponseData> CreateVocabularyQuizAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "practice/vocabulary-quiz")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<VocabularyQuizHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await practiceLanguageTools.VocabularyQuizAsync(
                    principal,
                    body.Value ?? new VocabularyQuizHttpRequest(null, null, null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("language-tools-ask")]
    public async Task<HttpResponseData> AskLanguageToolAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "language-tools/ask")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<AskAnythingHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await practiceLanguageTools.AskAsync(
                    principal,
                    body.Value ?? new AskAnythingHttpRequest(null, null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("language-tools-translate")]
    public async Task<HttpResponseData> TranslateLanguageToolAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "language-tools/translate")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<TranslationHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await practiceLanguageTools.TranslateAsync(
                    principal,
                    body.Value ?? new TranslationHttpRequest(null, null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
    }

    [Function("language-tools-translate-image")]
    public async Task<HttpResponseData> TranslateImageLanguageToolAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "language-tools/translate-image")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            var body = await ReadJsonAsync<ImageTranslationHttpRequest>(request, cancellationToken);
            if (body.TooLarge)
            {
                return await WritePayloadTooLargeAsync(request, cancellationToken);
            }

            if (body.Malformed)
            {
                return await WriteInvalidJsonAsync(request, cancellationToken);
            }

            return await WriteAsync(
                request,
                await practiceLanguageTools.TranslateImageAsync(
                    principal,
                    body.Value ?? new ImageTranslationHttpRequest(null, null, null, null),
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: true);
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

    [Function("dev-reset-learner-state")]
    public async Task<HttpResponseData> ResetLearnerStateAsync(
        [HttpTrigger(AuthorizationLevel.Anonymous, "delete", Route = "dev/learner-state")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return await AuthenticatedAsync(request, cancellationToken, async principal =>
        {
            return await WriteAsync(
                request,
                await devReset.DeleteAsync(
                    principal,
                    CorrelationId(request),
                    cancellationToken),
                cancellationToken);
        }, chargeBudget: false);
    }

    private async Task<HttpResponseData> AuthenticatedAsync(
        HttpRequestData request,
        CancellationToken cancellationToken,
        Func<AppSessionPrincipal, Task<HttpResponseData>> handler,
        bool chargeBudget)
    {
        var principal = Principal(request);
        if (principal is null)
        {
            return await UnauthorizedAsync<object>(request, cancellationToken);
        }

        if (chargeBudget)
        {
            var rejection = await BudgetRejectionAsync(request, principal, cancellationToken);
            if (rejection is not null) return rejection;
        }

        return await handler(principal);
    }

    private async Task<HttpResponseData?> BudgetRejectionAsync(
        HttpRequestData request,
        AppSessionPrincipal principal,
        CancellationToken cancellationToken)
    {
        try
        {
            await requestBudget.EnsureAllowedAsync(principal.TenantId, principal.UserId, cancellationToken);
            return null;
        }
        catch (ApiRequestBudgetExceededException exception)
        {
            return await WriteAsync(request, ApiResponse<object>.Failure(429,
                new ApiErrorResponse(exception.Code, "API request budget exceeded.",
                    Domain.Learners.CorrelationId.Create(CorrelationId(request)).Value,
                    exception.Code == "api_request_rate_limited")), cancellationToken);
        }
    }

    private AppSessionPrincipal? Principal(HttpRequestData request)
    {
        if (!request.Headers.TryGetValues("Authorization", out var values))
        {
            return null;
        }

        var headers = values.ToArray();
        if (headers.Length != 1)
        {
            return null;
        }

        var authorization = headers[0];

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

    private static ExpectedVersionResult ParseExpectedVersion(HttpRequestData request)
    {
        if (!request.Headers.TryGetValues("If-Match", out var values))
        {
            return ExpectedVersionResult.Absent;
        }

        var headers = values.ToArray();
        if (headers.Length != 1)
        {
            return ExpectedVersionResult.Invalid;
        }

        var value = headers[0].Trim();
        if (value.Length >= 2 && value[0] == '"' && value[^1] == '"')
        {
            value = value[1..^1];
        }

        return long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var version) && version >= 0
            ? new ExpectedVersionResult(true, LearnerStateVersion.Create(version), true)
            : ExpectedVersionResult.Invalid;
    }

    private static async Task<JsonReadResult<T>> ReadJsonAsync<T>(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        try
        {
            // Bound allocation before JSON parsing, including streams without Content-Length.
            var limit = typeof(T) == typeof(ImageTranslationHttpRequest) ? 8 * 1024 * 1024 : 64 * 1024;
            await using var buffer = new MemoryStream();
            var chunk = new byte[16 * 1024];
            while (true)
            {
                var read = await request.Body.ReadAsync(chunk.AsMemory(0, Math.Min(chunk.Length, limit + 1 - (int)buffer.Length)), cancellationToken);
                if (read == 0) break;
                await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
                if (buffer.Length > limit) return JsonReadResult<T>.Oversized();
            }

            buffer.Position = 0;
            return JsonReadResult<T>.Ok(await JsonSerializer.DeserializeAsync<T>(
                buffer,
                JsonOptions,
                cancellationToken));
        }
        catch (JsonException)
        {
            return JsonReadResult<T>.Invalid();
        }
    }

    private static Task<HttpResponseData> WritePayloadTooLargeAsync(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        return WriteAsync(request, ApiResponse<object>.Failure(413,
            new ApiErrorResponse("request_body_too_large", "Request body exceeds the allowed size.",
                Domain.Learners.CorrelationId.Create(CorrelationId(request)).Value, false)), cancellationToken);
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

    private static Task<HttpResponseData> WriteInvalidIfMatchAsync(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var correlationId = Domain.Learners.CorrelationId.Create(CorrelationId(request));
        return WriteAsync(
            request,
            ApiResponse<object>.Failure(
                400,
                new ApiErrorResponse(
                    "invalid_if_match",
                    "If-Match must contain exactly one non-negative numeric version token.",
                    correlationId.Value,
                    false)),
            cancellationToken);
    }

    private static Task<HttpResponseData> UnauthorizedAsync<T>(
        HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var correlationId = Domain.Learners.CorrelationId.Create(CorrelationId(request));
        return WriteAsync(
            request,
            ApiResponse<T>.Failure(
                401,
                new ApiErrorResponse(
                    "app_session_required",
                    "An authenticated app session is required.",
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

    private sealed record JsonReadResult<T>(T? Value, bool Malformed, bool TooLarge)
    {
        public static JsonReadResult<T> Ok(T? value) => new(value, false, false);

        public static JsonReadResult<T> Invalid() => new(default, true, false);

        public static JsonReadResult<T> Oversized() => new(default, false, true);
    }

    private sealed record ExpectedVersionResult(
        bool IsPresent,
        LearnerStateVersion? Value,
        bool IsValid)
    {
        public static ExpectedVersionResult Absent { get; } = new(false, null, true);

        public static ExpectedVersionResult Invalid { get; } = new(true, null, false);
    }

    private sealed record DeploymentMarkerResponse(
        string? Sha,
        string? RunId,
        string? RunAttempt,
        string? Error);
}
