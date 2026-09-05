using System.Globalization;
using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

public sealed class LanguageProfileService(ILearnerStateRepository repository)
{
    public async Task<LanguageProfilesResponse> ListAsync(
        TenantId tenantId,
        UserId userId,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var states = await repository.ListAsync(tenantId, userId, cancellationToken);
        var activeLanguage = await repository.GetActiveLanguageAsync(tenantId, userId, cancellationToken)
            ?? states.FirstOrDefault()?.Profile.TargetLanguage;

        return new LanguageProfilesResponse(
            correlationId.Value,
            activeLanguage,
            states.Select(ToContract).ToArray());
    }

    public async Task<SelectLanguageProfileResponse> SelectAsync(
        TenantId tenantId,
        UserId userId,
        string targetLanguage,
        CorrelationId correlationId,
        CancellationToken cancellationToken)
    {
        var state = await repository.GetAsync(tenantId, userId, targetLanguage, cancellationToken)
            ?? throw new LearnerStateNotFoundException(tenantId, userId);

        await repository.SetActiveLanguageAsync(
            tenantId,
            userId,
            state.Profile.TargetLanguage,
            cancellationToken);

        return new SelectLanguageProfileResponse(correlationId.Value, state.Profile.TargetLanguage);
    }

    private static LanguageProfileContract ToContract(LearnerState state)
    {
        var profile = new LearnerProfileContract(
            state.Profile.TargetLanguage,
            state.Profile.NativeLanguage,
            state.Profile.ProficiencyLevel,
            state.Profile.Goals,
            state.Profile.DailyMinutes);

        return new LanguageProfileContract(
            state.Profile.TargetLanguage,
            DisplayName(state.Profile.TargetLanguage),
            IsComplete(state.Profile),
            profile,
            state.Version.Value);
    }

    private static bool IsComplete(LearnerProfile profile) =>
        !string.IsNullOrWhiteSpace(profile.TargetLanguage)
        && !string.IsNullOrWhiteSpace(profile.NativeLanguage)
        && !string.IsNullOrWhiteSpace(profile.ProficiencyLevel)
        && profile.Goals.Count > 0
        && profile.DailyMinutes > 0;

    private static string DisplayName(string languageKey)
    {
        try
        {
            return System.Globalization.CultureInfo.GetCultureInfo(languageKey).DisplayName;
        }
        catch (CultureNotFoundException)
        {
            return languageKey;
        }
    }
}
