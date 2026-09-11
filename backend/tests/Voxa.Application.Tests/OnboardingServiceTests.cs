using Voxa.Application.Learners;
using Voxa.Application.Onboarding;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class OnboardingServiceTests
{
    [Fact]
    public async Task SubmitAsyncReturnsSavedVersionWhenUpdatingExistingLearner()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var existing = await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new OnboardingService(repository);

        var response = await service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A2",
                ["travel", "conversation"],
                20,
                CorrelationId.Create("corr-123")),
            CancellationToken.None);

        Assert.Equal(existing.Version.Next().Value, response.Version);
        Assert.Equal("Spanish", response.Profile.TargetLanguage);
        Assert.Equal(["travel", "conversation"], response.Profile.Goals);
        Assert.Equal(20, response.Profile.DailyMinutes);
    }

    [Fact]
    public async Task SubmitAsyncRejectsAStaleClientVersion()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new OnboardingService(repository);

        await Assert.ThrowsAsync<StaleLearnerStateVersionException>(() => service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A2",
                ["travel"],
                20,
                CorrelationId.Create("corr-stale"),
                LearnerStateVersion.Create(0)),
            CancellationToken.None));
    }

    [Fact]
    public async Task SubmitAsyncDoesNotApplyVersionTokenWhenCreatingNewLanguageProfile()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var service = new OnboardingService(repository);

        var response = await service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A1",
                ["travel"],
                15,
                CorrelationId.Create("corr-new-language"),
                LearnerStateVersion.Create(99)),
            CancellationToken.None);

        Assert.Equal(1, response.Version);
        Assert.Null(repository.LastExpectedVersion);
    }

    [Fact]
    public async Task SubmitAsyncSeedsFirstLessonCheckpointForNewLanguageProfile()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var service = new OnboardingService(repository);

        await service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A1",
                ["travel"],
                15,
                CorrelationId.Create("corr-new-language")),
            CancellationToken.None);

        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);

        Assert.NotNull(saved);
        Assert.Equal("lesson-greetings", saved.CurrentLesson.LessonId);
        Assert.Equal("greetings", saved.CurrentLesson.KnowledgeUnitId);
        Assert.Equal(0, saved.CurrentLesson.StepIndex);
        Assert.True(saved.CurrentLesson.UpdatedAt > DateTimeOffset.UnixEpoch);
    }

    [Fact]
    public async Task SubmitAsyncMintsAPersonalisedCourseWhenTheAuthorServiceIsAvailable()
    {
        // C3 headline behaviour: after a new-language onboarding submits,
        // the persisted plan is the CurriculumModel-authored course, not
        // the pre-C3 placeholder.
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var author = new FakeCourseAuthor((_, _) => Task.FromResult(
            new ActiveLearningPlan(
                "plan-authored",
                "Everyday Spanish",
                [],
                new PlannedLesson[]
                {
                    new("l1", "Greetings", "You'll say hello.", 1, 10, PlannedLessonStatus.Current),
                    new("l2", "Numbers 1–20", "You'll count.", 2, 10, PlannedLessonStatus.Pending),
                })));
        var service = new OnboardingService(repository, author);

        await service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A1",
                ["travel"],
                15,
                CorrelationId.Create("corr-mint")),
            CancellationToken.None);

        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);
        Assert.NotNull(saved);
        Assert.Equal("Everyday Spanish", saved.ActivePlan.Title);
        Assert.Equal(2, saved.ActivePlan.Lessons.Count);
        Assert.Equal("l1", saved.ActivePlan.CurrentLesson?.LessonId);
    }

    [Fact]
    public async Task SubmitAsyncFallsBackToPlaceholderPlanWhenCourseAuthorFails()
    {
        // Non-fatal by design: onboarding always succeeds even if the
        // author service is temporarily down. The learner can request a
        // reassessment later from the Home surface.
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        var author = new FakeCourseAuthor((_, _) =>
            Task.FromException<ActiveLearningPlan>(new CourseAuthorException("upstream")));
        var service = new OnboardingService(repository, author);

        await service.SubmitAsync(
            new OnboardingSubmitCommand(
                tenantId,
                userId,
                "Spanish",
                "English",
                "A1",
                ["travel"],
                15,
                CorrelationId.Create("corr-fail")),
            CancellationToken.None);

        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);
        Assert.NotNull(saved);
        // Placeholder plan from the pre-C3 GenerateInitialPlan path.
        Assert.Equal("Beginner Foundations", saved.ActivePlan.Title);
        Assert.Empty(saved.ActivePlan.Lessons);
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "French", "English", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-a1", "Beginner Foundations", ["greetings"]),
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private sealed class FakeCourseAuthor(
        Func<CourseAuthorRequest, CancellationToken, Task<ActiveLearningPlan>> handler) : ICourseAuthorService
    {
        public Task<ActiveLearningPlan> AuthorCourseAsync(
            CourseAuthorRequest request,
            CancellationToken cancellationToken)
        {
            return handler(request, cancellationToken);
        }
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        private readonly Dictionary<string, LearnerState> states = new();

        public LearnerStateVersion? LastExpectedVersion { get; private set; }

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.TryGetValue(Key(tenantId, userId), out var state);
            return Task.FromResult(state);
        }

        public Task<LearnerState> SaveAsync(LearnerState state, LearnerStateVersion? expectedVersion, CancellationToken cancellationToken)
        {
            LastExpectedVersion = expectedVersion;
            var key = Key(state.TenantId, state.UserId);
            states.TryGetValue(key, out var current);

            if (current is not null && expectedVersion != current.Version)
            {
                throw new StaleLearnerStateVersionException(state.TenantId, state.UserId, expectedVersion, current.Version);
            }

            var nextVersion = current is null ? LearnerStateVersion.Create(1) : current.Version.Next();
            var saved = state.WithVersion(nextVersion);
            states[key] = saved;
            return Task.FromResult(saved);
        }

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.Remove(Key(tenantId, userId));
            return Task.CompletedTask;
        }

        private static string Key(TenantId tenantId, UserId userId) => $"{tenantId.Value}:{userId.Value}";
    }
}
