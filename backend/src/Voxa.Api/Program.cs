using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Voxa.Api.Configuration;
using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Learners;
using Voxa.Application.Realtime;
using Voxa.Infrastructure.Authentication;
using Voxa.Infrastructure.OpenAI;
using Voxa.Infrastructure.Persistence;
using Voxa.Infrastructure.Realtime;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        var openAiApiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY") ?? "";
        var storageAccountName = Environment.GetEnvironmentVariable("LEARNER_STATE_STORAGE_NAME")
            ?? Environment.GetEnvironmentVariable("AzureWebJobsStorage__accountName")
            ?? "";
        var appTokenSigningKey = Environment.GetEnvironmentVariable("APP_SESSION_SIGNING_KEY") ?? "";
        var appleClientId = Environment.GetEnvironmentVariable("APPLE_CLIENT_ID") ?? "";
        var appleTenantId = Environment.GetEnvironmentVariable("APPLE_TENANT_ID") ?? "tenant-default";

        var options = new VoxaBackendOptions(
            openAiApiKey,
            storageAccountName,
            appTokenSigningKey,
            appleClientId,
            appleTenantId);
        var validationErrors = options.Validate();
        if (validationErrors.Count > 0)
        {
            throw new InvalidOperationException(string.Join(" ", validationErrors));
        }

        services.AddSingleton<ISystemClock, SystemClock>();
        services.AddSingleton(new AppSessionTokenOptions(
            appTokenSigningKey,
            TimeSpan.FromMinutes(15),
            TimeSpan.FromDays(30)));
        services.AddSingleton<HmacAppSessionTokenIssuer>();
        services.AddSingleton<IAppSessionTokenIssuer>(provider => provider.GetRequiredService<HmacAppSessionTokenIssuer>());
        services.AddSingleton<IAppSessionTokenValidator>(provider => provider.GetRequiredService<HmacAppSessionTokenIssuer>());
        services.AddSingleton(new AppleJwksIdentityVerifierOptions(
            appleClientId,
            appleTenantId,
            new Uri("https://appleid.apple.com/auth/keys")));
        services.AddHttpClient<IAppleIdentityVerifier, AppleJwksIdentityVerifier>();
        services.AddSingleton<ILearnerStateTable>(_ => AzureTableStorageFactory.CreateLearnerStateTable(storageAccountName));
        services.AddSingleton<IRefreshSessionTable>(_ => AzureTableStorageFactory.CreateRefreshSessionTable(storageAccountName));
        services.AddSingleton<IRealtimeSessionAuditTable>(_ => AzureTableStorageFactory.CreateRealtimeSessionAuditTable(storageAccountName));
        services.AddSingleton<IRealtimeSessionRateLimitTable>(_ => AzureTableStorageFactory.CreateRealtimeSessionRateLimitTable(storageAccountName));
        services.AddSingleton<ILearnerStateRepository, TableLearnerStateRepository>();
        services.AddSingleton<IRefreshSessionStore, TableRefreshSessionStore>();
        services.AddSingleton<ILearnerSessionQueries, LearnerSessionService>();
        services.AddSingleton<IAppSessionService, AppSessionService>();
        services.AddSingleton(new RealtimeSessionRateLimitOptions(12, TimeSpan.FromMinutes(1)));
        services.AddSingleton<IRealtimeSessionRateLimiter, TableRealtimeSessionRateLimiter>();
        services.AddSingleton<IRealtimeSessionAuditLog, TableRealtimeSessionAuditLog>();
        services.AddSingleton<IRealtimeSessionService, RealtimeSessionService>();
        services.AddHttpClient<IRealtimeClientSecretIssuer, OpenAiRealtimeClientSecretIssuer>(client =>
        {
            client.BaseAddress = new Uri("https://api.openai.com/");
        });
        services.AddSingleton(new OpenAiRealtimeOptions(openAiApiKey, "gpt-realtime-2.1", "low"));
        services.AddSingleton<SignInWithAppleEndpoint>();
        services.AddSingleton<RefreshAppSessionEndpoint>();
        services.AddSingleton<LogoutAppSessionEndpoint>();
        services.AddSingleton<RealtimeSessionEndpoint>();
        services.AddSingleton<ResumeSessionEndpoint>();
    })
    .Build();

await host.RunAsync();
