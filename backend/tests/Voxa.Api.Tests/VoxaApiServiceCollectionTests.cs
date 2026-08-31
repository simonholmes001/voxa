using Microsoft.Extensions.DependencyInjection;
using Voxa.Api.Configuration;
using Voxa.Api.Functions;
using Voxa.Api.Http;
using Voxa.Application.Ai;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Realtime;

namespace Voxa.Api.Tests;

public sealed class VoxaApiServiceCollectionTests
{
    [Fact]
    public void AddVoxaBackendServicesResolvesFunctionDependencyGraph()
    {
        using var environment = ProductionEnvironment.ForTest();
        var services = new ServiceCollection();

        services.AddVoxaBackendServices();
        using var provider = services.BuildServiceProvider(new ServiceProviderOptions
        {
            ValidateOnBuild = true,
            ValidateScopes = true
        });

        Assert.NotNull(provider.GetRequiredService<IAppleIdentityVerifier>());
        Assert.NotNull(provider.GetRequiredService<IAppSessionService>());
        Assert.NotNull(provider.GetRequiredService<ILearnerSessionQueries>());
        Assert.NotNull(provider.GetRequiredService<IModelRouter>());
        Assert.NotNull(provider.GetRequiredService<IPromptRegistry>());
        Assert.NotNull(provider.GetRequiredService<IRealtimeSessionService>());
        Assert.NotNull(provider.GetRequiredService<SignInWithAppleEndpoint>());
        Assert.NotNull(provider.GetRequiredService<RefreshAppSessionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<LogoutAppSessionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<RealtimeSessionEndpoint>());
        Assert.NotNull(provider.GetRequiredService<ResumeSessionEndpoint>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<VoxaHttpFunctions>(provider));
    }

    private sealed class ProductionEnvironment : IDisposable
    {
        private readonly Dictionary<string, string?> previousValues;

        private ProductionEnvironment(Dictionary<string, string?> previousValues)
        {
            this.previousValues = previousValues;
        }

        public static ProductionEnvironment ForTest()
        {
            var values = new Dictionary<string, string?>
            {
                ["OPENAI_API_KEY"] = "test-openai-api-key",
                ["LEARNER_STATE_STORAGE_NAME"] = "voxadurabletest",
                ["APP_SESSION_SIGNING_KEY"] = "test-signing-key-that-is-long-enough-for-hmac",
                ["APPLE_CLIENT_ID"] = "com.simonholmes.voxa",
                ["APPLE_TENANT_ID"] = "tenant-default",
                ["APPLE_TEAM_ID"] = "2PA85SU4UQ",
                ["APPLE_KEY_ID"] = "APPLEKEYID1",
                ["APPLE_PRIVATE_KEY"] = "-----BEGIN PRIVATE KEY-----\\ntest\\n-----END PRIVATE KEY-----"
            };
            var previous = values.ToDictionary(pair => pair.Key, pair => Environment.GetEnvironmentVariable(pair.Key));

            foreach (var pair in values)
            {
                Environment.SetEnvironmentVariable(pair.Key, pair.Value);
            }

            return new ProductionEnvironment(previous);
        }

        public void Dispose()
        {
            foreach (var pair in previousValues)
            {
                Environment.SetEnvironmentVariable(pair.Key, pair.Value);
            }
        }
    }
}
