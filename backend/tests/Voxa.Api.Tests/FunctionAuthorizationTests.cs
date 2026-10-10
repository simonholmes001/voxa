using System.Net;
using System.Reflection;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Voxa.Api.Functions;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Api.Tests;

public sealed partial class FunctionInvalidJsonTests
{
    [Theory]
    [InlineData(nameof(VoxaHttpFunctions.ExportAccountDataAsync))]
    [InlineData(nameof(VoxaHttpFunctions.GenerateRealtimeDebriefAsync))]
    [InlineData(nameof(VoxaHttpFunctions.GetLearnerPlanAsync))]
    [InlineData(nameof(VoxaHttpFunctions.ReassessLearnerCourseAsync))]
    [InlineData(nameof(VoxaHttpFunctions.CreateVocabularyQuizAsync))]
    [InlineData(nameof(VoxaHttpFunctions.AskLanguageToolAsync))]
    [InlineData(nameof(VoxaHttpFunctions.TranslateLanguageToolAsync))]
    [InlineData(nameof(VoxaHttpFunctions.TranslateImageLanguageToolAsync))]
    public async Task ExpensiveFunctionsRejectExhaustedBudgetBeforeCallingProviders(string methodName)
    {
        var issuer = CreateTokenIssuer();
        var functions = CreateFunctions(issuer, new InMemoryLearnerStateRepository(), new StubRequestBudget(exhausted: true));
        var request = new TestHttpRequestData("{not-json", "POST", "test");
        request.Headers.Add("Authorization", $"Bearer {ValidAccessToken(issuer, TenantId.Create("tenant-a"), UserId.Create("user-a"))}");

        var response = await (Task<HttpResponseData>)typeof(VoxaHttpFunctions).GetMethod(methodName)!
            .Invoke(functions, [request, CancellationToken.None])!;

        Assert.Equal(HttpStatusCode.TooManyRequests, response.StatusCode);
        Assert.Equal(0, request.Body.Position);
        response.Body.Position = 0;
        using var document = await JsonDocument.ParseAsync(response.Body);
        Assert.Equal("api_request_budget_exhausted", document.RootElement.GetProperty("code").GetString());
        Assert.False(document.RootElement.GetProperty("retryable").GetBoolean());
    }

    [Theory]
    [InlineData("auth/apple", false)]
    [InlineData("language-tools/ask", true)]
    public async Task JsonBodiesOver64KiBAreRejectedBeforeDeserialization(string route, bool authenticated)
    {
        var issuer = CreateTokenIssuer();
        var functions = CreateFunctions(issuer);
        var request = new TestHttpRequestData(new string(' ', 65_537), "POST", route);
        if (authenticated)
            request.Headers.Add("Authorization", $"Bearer {ValidAccessToken(issuer, TenantId.Create("tenant-a"), UserId.Create("user-a"))}");

        var response = authenticated
            ? await functions.AskLanguageToolAsync(request, CancellationToken.None)
            : await functions.SignInWithAppleAsync(request, CancellationToken.None);

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        response.Body.Position = 0;
        using var document = await JsonDocument.ParseAsync(response.Body);
        Assert.Equal("request_body_too_large", document.RootElement.GetProperty("code").GetString());
    }

    public static IEnumerable<object[]> ProtectedFunctions()
    {
        string[] publicFunctions = ["auth-apple", "auth-refresh", "auth-logout", "health-deployment"];
        foreach (var method in typeof(VoxaHttpFunctions).GetMethods())
        {
            var function = method.GetCustomAttribute<FunctionAttribute>();
            if (function is null || publicFunctions.Contains(function.Name)) continue;
            foreach (var credential in new[] { "missing", "malformed", "expired", "forged", "wrong-scheme", "duplicate" })
            {
                yield return [method.Name, credential];
            }
        }
    }

    [Theory]
    [MemberData(nameof(ProtectedFunctions))]
    public async Task EveryProtectedFunctionRejectsInvalidSessionsBeforeReadingBody(string methodName, string credential)
    {
        var issuer = CreateTokenIssuer();
        var functions = CreateFunctions(issuer);
        var method = typeof(VoxaHttpFunctions).GetMethod(methodName)!;
        var trigger = method.GetParameters()[0].GetCustomAttribute<HttpTriggerAttribute>()!;
        var request = new TestHttpRequestData("{not-json", trigger.Methods!.First(), trigger.Route!);
        var valid = ValidAccessToken(issuer, TenantId.Create("tenant-a"), UserId.Create("user-a"));
        var expiredIssuer = new HmacAppSessionTokenIssuer(
            new AppSessionTokenOptions("test-signing-key-that-is-long-enough-for-hmac", TimeSpan.FromMinutes(15), TimeSpan.FromDays(30)),
            new FixedClock(DateTimeOffset.Parse("2026-08-30T08:00:00Z")));
        var header = credential switch
        {
            "missing" => null,
            "malformed" => "Bearer invalid",
            "expired" => $"Bearer {ValidAccessToken(expiredIssuer, TenantId.Create("tenant-a"), UserId.Create("user-a"))}",
            "forged" => $"Bearer {valid.Split('.')[0]}.invalid-signature",
            "wrong-scheme" => $"Basic {valid}",
            "duplicate" => $"Bearer {valid}",
            _ => throw new ArgumentOutOfRangeException(nameof(credential))
        };
        if (header is not null) request.Headers.Add("Authorization", header);
        if (credential == "duplicate") request.Headers.TryAddWithoutValidation("Authorization", "Bearer invalid");

        var arguments = method.GetParameters().Select(parameter => parameter.ParameterType == typeof(HttpRequestData)
            ? (object)request : parameter.ParameterType == typeof(CancellationToken) ? CancellationToken.None : (object)"fr-fr").ToArray();
        var response = await (Task<HttpResponseData>)method.Invoke(functions, arguments)!;

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.Equal(0, request.Body.Position);
        response.Body.Position = 0;
        using var document = await JsonDocument.ParseAsync(response.Body);
        Assert.Equal("app_session_required", document.RootElement.GetProperty("code").GetString());
    }

    [Theory]
    [InlineData("tenant-a", "user-b")]
    [InlineData("tenant-b", "user-a")]
    public async Task DeletingLanguageProfileCannotDeleteAnotherUsersOrTenantsState(string otherTenant, string otherUser)
    {
        var repository = new InMemoryLearnerStateRepository();
        var tenant = TenantId.Create("tenant-a");
        var user = UserId.Create("user-a");
        var otherTenantId = TenantId.Create(otherTenant);
        var otherUserId = UserId.Create(otherUser);
        foreach (var (t, u) in new[] { (tenant, user), (otherTenantId, otherUserId) })
        {
            await repository.SaveAsync(LearnerState.Create(t, u,
                new LearnerProfile(t, u, "fr-FR", "en-US", "A1", ["travel"], 15),
                ActiveLearningPlan.Empty, LessonCheckpoint.None, ReviewQueue.Empty, RecentSessionSummaries.Empty),
                null, CancellationToken.None);
        }
        var issuer = CreateTokenIssuer();
        var functions = CreateFunctions(issuer, repository);
        var request = new TestHttpRequestData("", "DELETE", "language-profiles/fr-fr");
        request.Headers.Add("Authorization", $"Bearer {ValidAccessToken(issuer, tenant, user)}");
        request.Headers.Add("X-Tenant-Id", otherTenant);
        request.Headers.Add("X-User-Id", otherUser);

        var response = await functions.DeleteLanguageProfileAsync(request, "fr-fr", CancellationToken.None);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(await repository.GetAsync(tenant, user, CancellationToken.None));
        Assert.NotNull(await repository.GetAsync(otherTenantId, otherUserId, CancellationToken.None));
    }
}
