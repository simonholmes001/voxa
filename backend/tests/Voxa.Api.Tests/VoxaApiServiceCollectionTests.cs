using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Voxa.Api.Configuration;
using Voxa.Api.Functions;
using Voxa.Api.Http;
using Voxa.Application.Ai;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Practice;
using Voxa.Application.Realtime;

namespace Voxa.Api.Tests;

public sealed class VoxaApiServiceCollectionTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void AzureEnvironmentStorageFallbackSupportsStartup(bool explicitLearnerStorage)
    {
        var values = ConfigurationValues();
        if (!explicitLearnerStorage) values.Remove("LEARNER_STATE_STORAGE_NAME");
        values["AzureWebJobsStorage__accountName"] = "voxaazurestorage";
        var prefix = $"VOXA_TEST_{Guid.NewGuid():N}_";
        try
        {
            foreach (var (name, value) in values)
                Environment.SetEnvironmentVariable(prefix + name, value);
            var configuration = new ConfigurationBuilder().AddEnvironmentVariables(prefix).Build();
            var services = new ServiceCollection();

            services.AddVoxaBackendServices(configuration);
            using var provider = services.BuildServiceProvider(new ServiceProviderOptions
            {
                ValidateOnBuild = true,
                ValidateScopes = true
            });

            Assert.Equal(explicitLearnerStorage ? "voxadurabletest" : "voxaazurestorage",
                provider.GetRequiredService<VoxaBackendOptions>().LearnerStateStorageName);
            Assert.NotNull(ActivatorUtilities.CreateInstance<VoxaHttpFunctions>(provider));
        }
        finally
        {
            foreach (var name in values.Keys)
                Environment.SetEnvironmentVariable(prefix + name, null);
        }
    }

    [Fact]
    public void AddVoxaBackendServicesResolvesFunctionDependencyGraph()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(ConfigurationValues()).Build();
        var services = new ServiceCollection();

        services.AddVoxaBackendServices(configuration);
        using var provider = services.BuildServiceProvider(new ServiceProviderOptions
        {
            ValidateOnBuild = true,
            ValidateScopes = true
        });

        Assert.NotNull(provider.GetRequiredService<IAppleIdentityVerifier>());
        Assert.NotNull(provider.GetRequiredService<IAppSessionService>());
        Assert.NotNull(provider.GetRequiredService<ILearnerSessionQueries>());
        Assert.NotNull(provider.GetRequiredService<ILearningSessionCompletionService>());
        Assert.NotNull(provider.GetRequiredService<IModelRouter>());
        Assert.NotNull(provider.GetRequiredService<IPromptRegistry>());
        Assert.NotNull(provider.GetRequiredService<IRealtimeSessionService>());
        Assert.NotNull(provider.GetRequiredService<IPracticeLanguageToolService>());
        Assert.NotNull(provider.GetRequiredService<SignInWithAppleEndpoint>());
        Assert.NotNull(provider.GetRequiredService<RefreshAppSessionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<LogoutAppSessionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<RealtimeSessionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<PracticeLanguageToolEndpoint>());
        Assert.NotNull(provider.GetRequiredService<LearningSessionCompletionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<ResumeSessionEndpoint>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<VoxaHttpFunctions>(provider));
    }

    [Theory]
    [InlineData("REALTIME_SESSION_RATE_LIMIT_PER_WINDOW", "0")]
    [InlineData("REALTIME_SESSION_MONTHLY_USER_LIMIT", "-1")]
    [InlineData("REALTIME_SESSION_MONTHLY_TENANT_LIMIT", "invalid")]
    [InlineData("APP_ENABLE_DEV_RESET", "invalid")]
    [InlineData("API_REQUEST_RATE_LIMIT_PER_WINDOW", "0")]
    [InlineData("API_REQUEST_MONTHLY_USER_LIMIT", "-1")]
    [InlineData("API_REQUEST_MONTHLY_TENANT_LIMIT", "invalid")]
    public void InvalidConfiguredLimitsAndFlagsFailStartup(string name, string value)
    {
        var values = ConfigurationValues();
        values[name] = value;
        var configuration = new Microsoft.Extensions.Configuration.ConfigurationBuilder()
            .AddInMemoryCollection(values).Build();

        var error = Assert.Throws<InvalidOperationException>(() => new ServiceCollection().AddVoxaBackendServices(configuration));

        Assert.Contains(name, error.Message);
        Assert.DoesNotContain("test-openai-api-key", error.Message);
    }

    private static Dictionary<string, string?> ConfigurationValues() => new()
    {
        ["OPENAI_API_KEY"] = "test-openai-api-key",
        ["LEARNER_STATE_STORAGE_NAME"] = "voxadurabletest",
        ["APP_SESSION_SIGNING_KEY"] = "test-signing-key-that-is-long-enough-for-hmac",
        ["APPLE_CLIENT_ID"] = "com.simonholmes.voxa",
        ["APPLE_TENANT_ID"] = "tenant-default",
        ["APPLE_TEAM_ID"] = "2PA85SU4UQ",
        ["APPLE_KEY_ID"] = "APPLEKEYID1",
        ["APPLE_PRIVATE_KEY"] = "-----BEGIN PRIVATE KEY-----\\ntest\\n-----END PRIVATE KEY-----",
        ["VOXA_ENVIRONMENT"] = "test"
    };
}
