using Voxa.Api.Http;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class OnboardingSubmitEndpointTests
{
    [Fact]
    public async Task PostReturnsProfileFieldsRequiredByMobileClient()
    {
        var endpoint = new OnboardingSubmitEndpoint(new Application.Onboarding.OnboardingService(new RecordingLearnerStateRepository()));

        var response = await endpoint.PostAsync(
            new OnboardingSubmitHttpRequest(
                "French",
                "English",
                "B1",
                ["travel"],
                20),
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.NotNull(response.Body);
        Assert.Equal("French", response.Body.Profile.TargetLanguage);
        Assert.Equal("English", response.Body.Profile.NativeLanguage);
        Assert.Equal("B1", response.Body.Profile.ProficiencyLevel);
        Assert.Equal(["travel"], response.Body.Profile.Goals);
        Assert.Equal(20, response.Body.Profile.DailyMinutes);
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            return Task.FromResult<LearnerState?>(null);
        }

        public Task<LearnerState> SaveAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(state);
        }

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            throw new NotSupportedException();
        }
    }
}
