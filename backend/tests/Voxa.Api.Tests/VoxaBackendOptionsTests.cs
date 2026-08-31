using Voxa.Api.Configuration;

namespace Voxa.Api.Tests;

public sealed class VoxaBackendOptionsTests
{
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
            ApplePrivateKey: "");

        var errors = options.Validate();

        Assert.Contains("OPENAI_API_KEY is required.", errors);
        Assert.Contains("LEARNER_STATE_STORAGE_NAME is required.", errors);
        Assert.Contains("APP_SESSION_SIGNING_KEY is required.", errors);
        Assert.Contains("APPLE_CLIENT_ID is required.", errors);
        Assert.Contains("APPLE_TEAM_ID is required.", errors);
        Assert.Contains("APPLE_KEY_ID is required.", errors);
        Assert.Contains("APPLE_PRIVATE_KEY is required.", errors);
    }

    [Fact]
    public void ValidateAcceptsCompleteSettings()
    {
        var options = new VoxaBackendOptions(
            OpenAiApiKey: "configured-server-side",
            LearnerStateStorageName: "learner-state",
            AppSessionSigningKey: "session-signing-key",
            AppleClientId: "com.simonholmes.voxa",
            AppleTeamId: "2PA85SU4UQ",
            AppleKeyId: "apple-key-id",
            ApplePrivateKey: "apple-private-key");

        Assert.Empty(options.Validate());
    }
}
