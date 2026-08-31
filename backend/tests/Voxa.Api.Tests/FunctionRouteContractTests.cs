using System.Reflection;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Voxa.Api.Functions;

namespace Voxa.Api.Tests;

public sealed class FunctionRouteContractTests
{
    [Theory]
    [InlineData(nameof(VoxaHttpFunctions.SignInWithAppleAsync), "auth/apple", "post")]
    [InlineData(nameof(VoxaHttpFunctions.RefreshSessionAsync), "auth/refresh", "post")]
    [InlineData(nameof(VoxaHttpFunctions.LogoutAsync), "auth/logout", "post")]
    [InlineData(nameof(VoxaHttpFunctions.IssueRealtimeSessionAsync), "realtime/session", "post")]
    [InlineData(nameof(VoxaHttpFunctions.ResumeSessionAsync), "session/resume", "get")]
    [InlineData(nameof(VoxaHttpFunctions.DeploymentHealthAsync), "health/deployment", "get")]
    public void FunctionRoutesMatchMobileApiContract(string methodName, string route, string method)
    {
        var methodInfo = typeof(VoxaHttpFunctions).GetMethod(methodName);

        Assert.NotNull(methodInfo);
        Assert.NotNull(methodInfo.GetCustomAttribute<FunctionAttribute>());
        var trigger = methodInfo
            .GetParameters()
            .Select(parameter => parameter.GetCustomAttribute<HttpTriggerAttribute>())
            .Single(attribute => attribute is not null);

        Assert.NotNull(trigger);
        Assert.Equal(route, trigger.Route);
        Assert.NotNull(trigger.Methods);
        Assert.Contains(method, trigger.Methods);
    }
}
