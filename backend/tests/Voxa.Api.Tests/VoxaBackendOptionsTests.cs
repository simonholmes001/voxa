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
            AppSessionSigningKey: "");

        var errors = options.Validate();

        Assert.Contains("OPENAI_API_KEY is required.", errors);
        Assert.Contains("LEARNER_STATE_STORAGE_NAME is required.", errors);
        Assert.Contains("APP_SESSION_SIGNING_KEY is required.", errors);
    }

    [Fact]
    public void ValidateAcceptsCompleteSettings()
    {
        var options = new VoxaBackendOptions(
            OpenAiApiKey: "configured-server-side",
            LearnerStateStorageName: "learner-state",
            AppSessionSigningKey: "session-signing-key");

        Assert.Empty(options.Validate());
    }
}
