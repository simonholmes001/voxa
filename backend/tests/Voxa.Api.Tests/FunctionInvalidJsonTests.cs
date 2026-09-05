using System.Net;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging.Abstractions;
using Voxa.Api.Functions;
using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Onboarding;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;

namespace Voxa.Api.Tests;

public sealed class FunctionInvalidJsonTests
{
    [Fact]
    public async Task DeploymentHealthReturnsPackagedDeploymentMarker()
    {
        var markerPath = Path.Combine(Path.GetTempPath(), $"voxa-marker-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(
            markerPath,
            """
            {
              "sha": "abc123",
              "runId": "456",
              "runAttempt": "2"
            }
            """);
        Environment.SetEnvironmentVariable("VOXA_DEPLOYMENT_MARKER_PATH", markerPath);

        try
        {
            var functions = CreateFunctions();
            var request = new TestHttpRequestData("", method: "GET", route: "health/deployment");

            var response = await functions.DeploymentHealthAsync(request, CancellationToken.None);

            response.Body.Position = 0;
            using var document = await JsonDocument.ParseAsync(response.Body);

            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.Equal("abc123", document.RootElement.GetProperty("sha").GetString());
            Assert.Equal("456", document.RootElement.GetProperty("runId").GetString());
            Assert.Equal("2", document.RootElement.GetProperty("runAttempt").GetString());
        }
        finally
        {
            Environment.SetEnvironmentVariable("VOXA_DEPLOYMENT_MARKER_PATH", null);
            File.Delete(markerPath);
        }
    }

    [Fact]
    public async Task RealtimeSessionReturnsUnauthorizedWhenAuthorizationHeaderIsMissing()
    {
        var functions = CreateFunctions();
        var request = new TestHttpRequestData(
            """
            {
              "coachingMode": "tutor",
              "proficiencyBand": "B1-B2",
              "targetLanguage": "fr-FR"
            }
            """,
            method: "POST",
            route: "realtime/session");

        var response = await functions.IssueRealtimeSessionAsync(request, CancellationToken.None);

        response.Body.Position = 0;
        using var document = await JsonDocument.ParseAsync(response.Body);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal("app_session_required", document.RootElement.GetProperty("code").GetString());
    }

    [Theory]
    [InlineData("auth/apple")]
    [InlineData("auth/refresh")]
    [InlineData("auth/logout")]
    [InlineData("onboarding")]
    [InlineData("realtime/session")]
    public async Task PostFunctionsReturnInvalidJsonForMalformedBodies(string route)
    {
        var tokenIssuer = CreateTokenIssuer();
        var functions = CreateFunctions(tokenIssuer);
        var request = new TestHttpRequestData("{not-json", method: "POST", route);
        if (route == "onboarding")
        {
            request.Headers.Add(
                "Authorization",
                $"Bearer {ValidAccessToken(tokenIssuer, TenantId.Create("tenant-default"), UserId.Create("user-a"))}");
        }

        var response = route switch
        {
            "auth/apple" => await functions.SignInWithAppleAsync(request, CancellationToken.None),
            "auth/refresh" => await functions.RefreshSessionAsync(request, CancellationToken.None),
            "auth/logout" => await functions.LogoutAsync(request, CancellationToken.None),
            "onboarding" => await functions.SubmitOnboardingAsync(request, CancellationToken.None),
            "realtime/session" => await functions.IssueRealtimeSessionAsync(request, CancellationToken.None),
            _ => throw new ArgumentOutOfRangeException(nameof(route), route, null)
        };

        response.Body.Position = 0;
        using var document = await JsonDocument.ParseAsync(response.Body);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("invalid_json", document.RootElement.GetProperty("code").GetString());
    }

    private static VoxaHttpFunctions CreateFunctions()
    {
        return CreateFunctions(CreateTokenIssuer());
    }

    private static VoxaHttpFunctions CreateFunctions(HmacAppSessionTokenIssuer tokenIssuer)
    {
        return new VoxaHttpFunctions(
            new SignInWithAppleEndpoint(new StubAppSessionService(), NullLogger<SignInWithAppleEndpoint>.Instance),
            new RefreshAppSessionEndpoint(new StubAppSessionService()),
            new LogoutAppSessionEndpoint(new StubAppSessionService()),
            new RealtimeSessionEndpoint(new StubRealtimeSessionService()),
            new ResumeSessionEndpoint(new StubLearnerSessionQueries()),
            new LanguageProfilesEndpoint(new LanguageProfileService(new StubLearnerStateRepository())),
            new OnboardingSubmitEndpoint(new OnboardingService(new StubLearnerStateRepository())),
            new DevResetEndpoint(new StubLearnerStateRepository(), enabled: true),
            tokenIssuer,
            new FixedClock(DateTimeOffset.Parse("2026-08-31T08:00:00Z")));
    }

    private static HmacAppSessionTokenIssuer CreateTokenIssuer()
    {
        return new HmacAppSessionTokenIssuer(
            new AppSessionTokenOptions(
                "test-signing-key-that-is-long-enough-for-hmac",
                TimeSpan.FromMinutes(15),
                TimeSpan.FromDays(30)),
            new FixedClock(DateTimeOffset.Parse("2026-08-31T08:00:00Z")));
    }

    private static string ValidAccessToken(HmacAppSessionTokenIssuer tokenIssuer, TenantId tenantId, UserId userId)
    {
        return tokenIssuer.IssueTokenPair(
            new VerifiedAppSessionSubject(tenantId, userId),
            CorrelationId.Create("corr-123")).AccessToken;
    }

    private sealed class TestHttpRequestData : HttpRequestData
    {
        private readonly string method;
        private readonly Uri url;

        public TestHttpRequestData(string body, string method, string route)
            : base(new TestFunctionContext())
        {
            this.method = method;
            url = new Uri($"https://api.voxa.example/api/{route}");
            Body = new MemoryStream(Encoding.UTF8.GetBytes(body));
            Headers = new HttpHeadersCollection();
        }

        public override Stream Body { get; }

        public override HttpHeadersCollection Headers { get; }

        public override IReadOnlyCollection<IHttpCookie> Cookies { get; } = [];

        public override Uri Url => url;

        public override IEnumerable<ClaimsIdentity> Identities { get; } = [];

        public override string Method => method;

        public override HttpResponseData CreateResponse()
        {
            return new TestHttpResponseData(FunctionContext);
        }
    }

    private sealed class TestHttpResponseData(FunctionContext functionContext) : HttpResponseData(functionContext)
    {
        public override HttpStatusCode StatusCode { get; set; }

        public override HttpHeadersCollection Headers { get; set; } = [];

        public override Stream Body { get; set; } = new MemoryStream();

        public override HttpCookies Cookies { get; } = null!;
    }

    private sealed class TestFunctionContext : FunctionContext
    {
        public override string InvocationId => "test-invocation";

        public override string FunctionId => "test-function";

        public override TraceContext TraceContext { get; } = null!;

        public override BindingContext BindingContext { get; } = null!;

        public override RetryContext RetryContext { get; } = null!;

        public override IServiceProvider InstanceServices { get; set; } = null!;

        public override FunctionDefinition FunctionDefinition { get; } = null!;

        public override IDictionary<object, object> Items { get; set; } = new Dictionary<object, object>();

        public override IInvocationFeatures Features { get; } = null!;
    }

    private sealed class StubAppSessionService : IAppSessionService
    {
        public Task<AppSessionTokenPair> SignInWithAppleAsync(
            SignInWithAppleCommand command,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }

        public Task<AppSessionTokenPair> RefreshAsync(
            RefreshAppSessionCommand command,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }

        public Task RevokeRefreshTokenAsync(
            LogoutAppSessionCommand command,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }
    }

    private sealed class StubRealtimeSessionService : IRealtimeSessionService
    {
        public Task<RealtimeSessionCredential> IssueClientSecretAsync(
            RealtimeSessionCommand command,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }
    }

    private sealed class StubLearnerSessionQueries : ILearnerSessionQueries
    {
        public Task<ResumeCheckpointResponse> GetResumeCheckpointAsync(
            ResumeCheckpointQuery query,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }

        public Task<LearnerState> SaveLearnerStateAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }
    }

    private sealed class StubLearnerStateRepository : ILearnerStateRepository
    {
        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }

        public Task<LearnerState> SaveAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }
    }

    private sealed class FixedClock(DateTimeOffset utcNow) : ISystemClock
    {
        public DateTimeOffset UtcNow => utcNow;
    }
}
