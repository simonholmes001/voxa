namespace Voxa.Api.Configuration;

public sealed record VoxaBackendOptions(
    string? OpenAiApiKey,
    string? LearnerStateStorageName)
{
    public IReadOnlyList<string> Validate()
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(OpenAiApiKey))
        {
            errors.Add("OPENAI_API_KEY is required.");
        }

        if (string.IsNullOrWhiteSpace(LearnerStateStorageName))
        {
            errors.Add("LEARNER_STATE_STORAGE_NAME is required.");
        }

        return errors;
    }
}
