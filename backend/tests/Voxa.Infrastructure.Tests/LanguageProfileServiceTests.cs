using Voxa.Application.Learners;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Infrastructure.Tests;

public sealed class LanguageProfileServiceTests
{
    [Fact]
    public async Task ListReturnsProfilesForOnlyTheCurrentLearnerAndActiveLanguage()
    {
        var repository = new InMemoryLearnerStateRepository();
        var tenant = TenantId.Create("tenant-a");
        var user = UserId.Create("user-a");
        var otherUser = UserId.Create("user-b");
        await repository.SaveAsync(CreateState(tenant, user, "fr-FR"), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(tenant, user, "es-ES"), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(tenant, otherUser, "de-DE"), null, CancellationToken.None);
        await repository.SetActiveLanguageAsync(tenant, user, "ES-es", CancellationToken.None);

        var response = await new LanguageProfileService(repository).ListAsync(
            tenant, user, CorrelationId.Create("corr-1"), CancellationToken.None);

        Assert.Equal("es-ES", response.ActiveLanguageKey);
        Assert.Equal(["es-ES", "fr-FR"], response.Profiles.Select(profile => profile.LanguageKey));
    }

    [Fact]
    public async Task SelectChangesActiveLanguageWithoutChangingProfileState()
    {
        var repository = new InMemoryLearnerStateRepository();
        var tenant = TenantId.Create("tenant-a");
        var user = UserId.Create("user-a");
        var french = await repository.SaveAsync(CreateState(tenant, user, "fr-FR"), null, CancellationToken.None);
        await repository.SaveAsync(CreateState(tenant, user, "es-ES"), null, CancellationToken.None);

        var response = await new LanguageProfileService(repository).SelectAsync(
            tenant, user, "fr-fr", CorrelationId.Create("corr-2"), CancellationToken.None);

        Assert.Equal("fr-FR", response.ActiveLanguageKey);
        var active = await repository.GetAsync(tenant, user, CancellationToken.None);
        Assert.Equal(french.Profile, active!.Profile);
        Assert.Equal(french.Version, active.Version);
    }

    private static LearnerState CreateState(TenantId tenant, UserId user, string language) =>
        LearnerState.Create(
            tenant,
            user,
            new LearnerProfile(tenant, user, language, "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlan($"plan-{language}", language, ["greetings"]),
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
}
