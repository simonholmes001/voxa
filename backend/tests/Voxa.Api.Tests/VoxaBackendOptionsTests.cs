using Voxa.Api.Configuration;

namespace Voxa.Api.Tests;

public sealed class VoxaBackendOptionsTests
{
    [Fact]
    public void ValidateReturnsClearErrorsForMissingRequiredSettings()
    {
        var options = new VoxaBackendOptions(OpenAiApiKey: "", LearnerStateStorageName: null);

        var errors = options.Validate();

        Assert.Contains("OPENAI_API_KEY is required.", errors);
        Assert.Contains("LEARNER_STATE_STORAGE_NAME is required.", errors);
    }

    [Fact]
    public void ValidateAcceptsCompleteSettings()
    {
        var options = new VoxaBackendOptions(
            OpenAiApiKey: "configured-server-side",
            LearnerStateStorageName: "learner-state");

        Assert.Empty(options.Validate());
    }
}
