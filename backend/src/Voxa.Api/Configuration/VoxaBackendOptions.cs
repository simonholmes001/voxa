namespace Voxa.Api.Configuration;

public sealed record VoxaBackendOptions(
    string? OpenAiApiKey,
    string? LearnerStateStorageName,
    string? AppSessionSigningKey = null,
    string? AppleClientId = null,
    string? AppleTenantId = null)
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

        if (string.IsNullOrWhiteSpace(AppSessionSigningKey))
        {
            errors.Add("APP_SESSION_SIGNING_KEY is required.");
        }

        return errors;
    }
}
