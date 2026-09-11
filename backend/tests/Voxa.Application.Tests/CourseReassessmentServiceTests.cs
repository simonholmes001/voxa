using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class CourseReassessmentServiceTests
{
    private static readonly TenantId Tenant = TenantId.Create("tenant-a");
    private static readonly UserId User = UserId.Create("user-a");

    [Fact]
    public async Task ReassessAsyncThrowsLearnerStateNotFoundWhenTheLearnerHasNoState()
    {
        var repository = new FakeRepository();
        var author = new FakeCourseAuthor((_, _) => throw new NotSupportedException());
        var service = new CourseReassessmentService(repository, author);

        await Assert.ThrowsAsync<LearnerStateNotFoundException>(() =>
            service.ReassessAsync(SampleCommand("more travel content"), CancellationToken.None));
    }

    [Fact]
    public async Task ReassessAsyncPassesCompletedLessonIdsAndCurrentPlanToTheAuthor()
    {
        // The author service's headline behaviour depends on receiving
        // the completed lesson list from the current plan — that's what
        // makes IDs and progress carry through the re-mint. Confirm the
        // reassessment service assembles that request correctly.
        var repository = new FakeRepository();
        repository.Seed(StateWithLessons(
            new PlannedLesson[]
            {
                new("l1", "Greetings", "…", 1, 10, PlannedLessonStatus.Completed),
                new("l2", "Cooking verbs", "…", 2, 15, PlannedLessonStatus.Current),
                new("l3", "Past tense", "…", 3, 15, PlannedLessonStatus.Pending),
            }));
        CourseAuthorRequest? capturedRequest = null;
        var author = new FakeCourseAuthor((request, _) =>
        {
            capturedRequest = request;
            return Task.FromResult(NewPlan(
                title: "Everyday German (revised)",
                lessons: [new PlannedLesson("l1", "Greetings", "…", 1, 10, PlannedLessonStatus.Completed)]));
        });
        var service = new CourseReassessmentService(repository, author);

        await service.ReassessAsync(SampleCommand("more speaking"), CancellationToken.None);

        Assert.NotNull(capturedRequest);
        Assert.Single(capturedRequest!.CompletedLessonIds);
        Assert.Equal("l1", capturedRequest.CompletedLessonIds[0]);
        Assert.NotNull(capturedRequest.ExistingCourse);
        Assert.Equal("more speaking", capturedRequest.ReassessmentRequest);
    }

    [Fact]
    public async Task ReassessAsyncWritesTheNewPlanBackToTheRepository()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithLessons(
            new PlannedLesson[]
            {
                new("l1", "Greetings", "…", 1, 10, PlannedLessonStatus.Completed),
            }));
        var newPlan = NewPlan(
            title: "Everyday German (revised)",
            lessons: [
                new PlannedLesson("l1", "Greetings", "…", 1, 10, PlannedLessonStatus.Completed),
                new PlannedLesson("l4", "New lesson", "…", 2, 15, PlannedLessonStatus.Current),
            ]);
        var author = new FakeCourseAuthor((_, _) => Task.FromResult(newPlan));
        var service = new CourseReassessmentService(repository, author);

        var result = await service.ReassessAsync(SampleCommand("something"), CancellationToken.None);

        Assert.Equal("Everyday German (revised)", result.Title);
        var saved = repository.Saved.Last();
        Assert.Equal("Everyday German (revised)", saved.ActivePlan.Title);
        Assert.Equal(2, saved.ActivePlan.Lessons.Count);
    }

    [Fact]
    public async Task ReassessAsyncRetriesOnStaleVersionConflictUpToConcurrencyLimit()
    {
        // A concurrent write from another endpoint (e.g. session
        // completion) could bump the version between our Get and Save.
        // The service reads fresh state and retries.
        var repository = new FakeRepository();
        repository.Seed(StateWithLessons([new PlannedLesson("l1", "T", "…", 1, 15, PlannedLessonStatus.Current)]));
        repository.FailNextSavesWithStaleVersion = 2;
        var author = new FakeCourseAuthor((_, _) => Task.FromResult(NewPlan("t", [])));
        var service = new CourseReassessmentService(repository, author);

        await service.ReassessAsync(SampleCommand(null), CancellationToken.None);

        Assert.Equal(3, repository.SaveAttempts);
    }

    [Fact]
    public async Task ReassessAsyncPropagatesCourseAuthorFailureSoTheEndpointCanReturn503()
    {
        var repository = new FakeRepository();
        repository.Seed(StateWithLessons([]));
        var author = new FakeCourseAuthor((_, _) => throw new CourseAuthorException("upstream"));
        var service = new CourseReassessmentService(repository, author);

        await Assert.ThrowsAsync<CourseAuthorException>(() =>
            service.ReassessAsync(SampleCommand("go"), CancellationToken.None));
    }

    // MARK: - Helpers

    private static CourseReassessmentCommand SampleCommand(string? request)
    {
        return new CourseReassessmentCommand(Tenant, User, CorrelationId.Create("corr"), request);
    }

    private static LearnerState StateWithLessons(IReadOnlyList<PlannedLesson> lessons)
    {
        return LearnerState.Create(
            Tenant,
            User,
            new LearnerProfile(Tenant, User, "de-DE", "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-x", "Current title", [], lessons),
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private static ActiveLearningPlan NewPlan(string title, IReadOnlyList<PlannedLesson> lessons)
    {
        return new ActiveLearningPlan("plan-x", title, [], lessons);
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

    private sealed class FakeRepository : ILearnerStateRepository
    {
        private readonly Dictionary<(string, string), LearnerState> store = new();
        public List<LearnerState> Saved { get; } = new();
        public int SaveAttempts { get; private set; }
        public int FailNextSavesWithStaleVersion { get; set; }

        public void Seed(LearnerState state)
        {
            store[(state.TenantId.Value, state.UserId.Value)] = state;
        }

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            store.TryGetValue((tenantId.Value, userId.Value), out var state);
            return Task.FromResult<LearnerState?>(state);
        }

        public Task<LearnerState> SaveAsync(LearnerState state, LearnerStateVersion? expectedVersion, CancellationToken cancellationToken)
        {
            SaveAttempts++;
            if (FailNextSavesWithStaleVersion > 0)
            {
                FailNextSavesWithStaleVersion--;
                throw new StaleLearnerStateVersionException(
                    state.TenantId,
                    state.UserId,
                    expectedVersion ?? state.Version,
                    state.Version);
            }

            var next = state.WithVersion(LearnerStateVersion.Create((expectedVersion ?? state.Version).Value + 1));
            store[(state.TenantId.Value, state.UserId.Value)] = next;
            Saved.Add(next);
            return Task.FromResult(next);
        }

        public Task DeleteAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
            => throw new NotSupportedException();
    }
}
