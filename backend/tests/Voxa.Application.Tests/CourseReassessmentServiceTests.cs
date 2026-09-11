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
        // The service reads fresh state and retries the SAVE — but
        // never re-authors the course, because the OpenAI call is
        // expensive and non-idempotent; re-running it under contention
        // could silently swap one accepted plan for a different one.
        var repository = new FakeRepository();
        repository.Seed(StateWithLessons([new PlannedLesson("l1", "T", "…", 1, 15, PlannedLessonStatus.Current)]));
        repository.FailNextSavesWithStaleVersion = 2;
        var authorInvocationCount = 0;
        var author = new FakeCourseAuthor((_, _) =>
        {
            authorInvocationCount++;
            return Task.FromResult(NewPlan("t", [new PlannedLesson("l1", "T", "…", 1, 15, PlannedLessonStatus.Current)]));
        });
        var service = new CourseReassessmentService(repository, author);

        await service.ReassessAsync(SampleCommand(null), CancellationToken.None);

        Assert.Equal(3, repository.SaveAttempts);
        // Non-idempotent model call runs exactly once even under
        // contended saves. The retry loop remaps completion statuses
        // locally instead of re-authoring.
        Assert.Equal(1, authorInvocationCount);
    }

    [Fact]
    public async Task ReassessAsyncRemapsCompletedLessonStatusesFromFreshStateOnRetry()
    {
        // Between the initial mint and the (retried) save, another write
        // (e.g. a guided-lesson completion) marks lesson "l2" as
        // Completed. The retry path must reflect that fresh completion
        // in the saved plan without re-authoring — the model call is
        // hoisted out of the loop.
        var repository = new FakeRepository();
        repository.Seed(StateWithLessons([
            new PlannedLesson("l1", "One", "…", 1, 15, PlannedLessonStatus.Completed),
            new PlannedLesson("l2", "Two", "…", 2, 15, PlannedLessonStatus.Current),
            new PlannedLesson("l3", "Three", "…", 3, 15, PlannedLessonStatus.Pending),
        ]));
        var mintedPlanLessons = new PlannedLesson[]
        {
            new("l1", "One", "…", 1, 15, PlannedLessonStatus.Completed),
            new("l2", "Two", "…", 2, 15, PlannedLessonStatus.Current),
            new("l3", "Three", "…", 3, 15, PlannedLessonStatus.Pending),
        };
        var author = new FakeCourseAuthor((_, _) => Task.FromResult(NewPlan("Revised", mintedPlanLessons)));
        // First save conflicts; between the first and second attempts the
        // Seed changes so a re-read sees "l2" also completed.
        repository.FailNextSavesWithStaleVersion = 1;
        repository.OnStaleReSeed = () => StateWithLessons([
            new PlannedLesson("l1", "One", "…", 1, 15, PlannedLessonStatus.Completed),
            new PlannedLesson("l2", "Two", "…", 2, 15, PlannedLessonStatus.Completed),
            new PlannedLesson("l3", "Three", "…", 3, 15, PlannedLessonStatus.Current),
        ]);
        var service = new CourseReassessmentService(repository, author);

        var result = await service.ReassessAsync(SampleCommand(null), CancellationToken.None);

        // Both l1 and l2 land as Completed; l3 becomes Current.
        Assert.Equal(PlannedLessonStatus.Completed, result.Lessons.First(l => l.LessonId == "l1").Status);
        Assert.Equal(PlannedLessonStatus.Completed, result.Lessons.First(l => l.LessonId == "l2").Status);
        Assert.Equal(PlannedLessonStatus.Current, result.Lessons.First(l => l.LessonId == "l3").Status);
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
        /// <summary>
        /// Optional hook: when a save fails with a stale-version conflict,
        /// this factory runs and replaces the seeded state — modeling a
        /// concurrent write from another endpoint (e.g. a guided-lesson
        /// completion that lands between our mint and our save).
        /// </summary>
        public Func<LearnerState>? OnStaleReSeed { get; set; }

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
                if (OnStaleReSeed is not null)
                {
                    Seed(OnStaleReSeed());
                }
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
