namespace Voxa.Api.Configuration;

public sealed record VoxaBackendOptions(
    string? OpenAiApiKey,
    string? LearnerStateStorageName,
    string? AppSessionSigningKey = null,
    string? AppleClientId = null,
    string? AppleTenantId = null,
    string? AppleTeamId = null,
    string? AppleKeyId = null,
    string? ApplePrivateKey = null)
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

        if (string.IsNullOrWhiteSpace(AppleClientId))
        {
            errors.Add("APPLE_CLIENT_ID is required.");
        }

        if (string.IsNullOrWhiteSpace(AppleTeamId))
        {
            errors.Add("APPLE_TEAM_ID is required.");
        }

        if (string.IsNullOrWhiteSpace(AppleKeyId))
        {
            errors.Add("APPLE_KEY_ID is required.");
        }

        if (string.IsNullOrWhiteSpace(ApplePrivateKey))
        {
            errors.Add("APPLE_PRIVATE_KEY is required.");
        }

        return errors;
    }
}
