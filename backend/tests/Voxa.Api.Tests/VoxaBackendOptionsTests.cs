using Voxa.Api.Configuration;

namespace Voxa.Api.Tests;

public sealed class VoxaBackendOptionsTests
{
    [Theory]
    [InlineData("short")]
    [InlineData("1234567890123456789012345678901")]
    public void ValidateRejectsSigningKeysShorterThan32Bytes(string key)
    {
        var options = new VoxaBackendOptions("openai", "storage", AppSessionSigningKey: key);

        Assert.Contains("APP_SESSION_SIGNING_KEY must contain at least 32 UTF-8 bytes.", options.Validate());
    }

    [Fact]
    public void ValidateReturnsClearErrorsForMissingRequiredSettings()
    {
        var options = new VoxaBackendOptions(
            OpenAiApiKey: "",
            LearnerStateStorageName: null,
            AppSessionSigningKey: "",
            AppleClientId: "",
            AppleTeamId: "",
            AppleKeyId: "",
            ApplePrivateKey: "",
            EnvironmentName: null);

        var errors = options.Validate();

        Assert.Contains("OPENAI_API_KEY is required.", errors);
        Assert.Contains("LEARNER_STATE_STORAGE_NAME is required.", errors);
        Assert.Contains("APP_SESSION_SIGNING_KEY is required.", errors);
        Assert.Contains("APPLE_CLIENT_ID is required.", errors);
        Assert.Contains("APPLE_TEAM_ID is required.", errors);
        Assert.Contains("APPLE_KEY_ID is required.", errors);
        Assert.Contains("APPLE_PRIVATE_KEY is required.", errors);
        Assert.Contains("VOXA_ENVIRONMENT is required.", errors);
    }

    [Fact]
    public void ValidateAcceptsCompleteSettings()
    {
        var options = new VoxaBackendOptions(
            OpenAiApiKey: "configured-server-side",
            LearnerStateStorageName: "learner-state",
            AppSessionSigningKey: "test-signing-key-that-is-long-enough-for-hmac",
            AppleClientId: "com.simonholmes.voxa",
            AppleTeamId: "2PA85SU4UQ",
            AppleKeyId: "apple-key-id",
            ApplePrivateKey: "apple-private-key",
            EnvironmentName: "dev");

        Assert.Empty(options.Validate());
    }

    [Fact]
    public void ValidateRejectsDeveloperResetOutsideDevelopment()
    {
        var options = new VoxaBackendOptions(
            OpenAiApiKey: "configured-server-side",
            LearnerStateStorageName: "learner-state",
            AppSessionSigningKey: "test-signing-key-that-is-long-enough-for-hmac",
            AppleClientId: "com.simonholmes.voxa",
            AppleTeamId: "2PA85SU4UQ",
            AppleKeyId: "apple-key-id",
            ApplePrivateKey: "apple-private-key",
            EnvironmentName: "production",
            DevResetEnabled: true);

        Assert.Contains(
            "APP_ENABLE_DEV_RESET may only be enabled when VOXA_ENVIRONMENT is dev.",
            options.Validate());
    }
}
