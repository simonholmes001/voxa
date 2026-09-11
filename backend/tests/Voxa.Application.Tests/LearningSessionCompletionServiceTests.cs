using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class LearningSessionCompletionServiceTests
{
    [Fact]
    public async Task CompleteAsyncRecordsRecentSessionAndQueuesCurrentLessonReview()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-123",
                lessonId: null,
                knowledgeUnitId: null,
                durationSeconds: 540,
                sessionIntent: "lesson",
                correlationId: "corr-complete"),
            CancellationToken.None);

        Assert.Equal("corr-complete", checkpoint.CorrelationId);
        Assert.Equal(2, checkpoint.Version);
        Assert.Equal("lesson-1", checkpoint.CurrentLesson.LessonId);
        Assert.Equal(2, checkpoint.CurrentLesson.StepIndex);
        Assert.Equal("greetings", checkpoint.ReviewQueue.First().KnowledgeUnitId);
        Assert.Equal(1, checkpoint.ReviewQueue.First().Priority);
        Assert.Equal("session-123", checkpoint.RecentSessions.First().SessionId);
        Assert.Equal(540, checkpoint.RecentSessions.First().DurationSeconds);
        Assert.Equal("lesson-1", checkpoint.RecentSessions.First().LessonId);
    }

    [Fact]
    public async Task CompleteAsyncIsIdempotentForSameSessionId()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var command = CompleteLearningSessionCommand.Create(
            tenantId.Value,
            userId.Value,
            "session-123",
            lessonId: "lesson-1",
            knowledgeUnitId: "greetings",
            durationSeconds: 300,
            sessionIntent: "lesson",
            correlationId: "corr-complete");

        await service.CompleteAsync(command, CancellationToken.None);
        var checkpoint = await service.CompleteAsync(command, CancellationToken.None);

        Assert.Equal(2, checkpoint.Version);
        Assert.Equal(2, checkpoint.CurrentLesson.StepIndex);
        Assert.Single(checkpoint.RecentSessions);
        Assert.Single(checkpoint.ReviewQueue);
    }

    [Fact]
    public async Task CompleteAsyncRequiresExistingLearnerState()
    {
        var service = new LearningSessionCompletionService(new RecordingLearnerStateRepository());

        await Assert.ThrowsAsync<LearnerStateNotFoundException>(() =>
            service.CompleteAsync(
                CompleteLearningSessionCommand.Create(
                    "tenant-a",
                    "user-a",
                    "session-123",
                    lessonId: null,
                    knowledgeUnitId: null,
                    durationSeconds: 60,
                    sessionIntent: "practice",
                    correlationId: "corr-complete"),
                CancellationToken.None));
    }

    [Fact]
    public async Task CompleteAsyncReturnsRecordedSessionWhenSaveBecomesStale()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository
        {
            RecordSessionOnNextStaleSave = "session-123"
        };
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-123",
                lessonId: "lesson-1",
                knowledgeUnitId: "greetings",
                durationSeconds: 300,
                sessionIntent: "lesson",
                correlationId: "corr-complete"),
            CancellationToken.None);

        Assert.Equal(2, checkpoint.Version);
        Assert.Single(checkpoint.RecentSessions);
        Assert.Equal("session-123", checkpoint.RecentSessions.First().SessionId);
    }

    [Fact]
    public async Task CompleteAsyncDoesNotReplaceCurrentLessonForReviewFocus()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "review-123",
                lessonId: "different-lesson",
                knowledgeUnitId: "different-unit",
                durationSeconds: 120,
                sessionIntent: "review",
                correlationId: "corr-review"),
            CancellationToken.None);

        Assert.Equal("lesson-1", checkpoint.CurrentLesson.LessonId);
        Assert.Equal("greetings", checkpoint.CurrentLesson.KnowledgeUnitId);
        Assert.Equal(1, checkpoint.CurrentLesson.StepIndex);
        Assert.Equal("different-unit", checkpoint.ReviewQueue.First().KnowledgeUnitId);
    }

    [Fact]
    public async Task CompleteAsyncAdvancesActivePlanOnGuidedLesson()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(
            CreateStateWithPlannedLessons(tenantId, userId),
            expectedVersion: null,
            CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        var checkpoint = await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-guided-1",
                lessonId: null,
                knowledgeUnitId: null,
                durationSeconds: 900,
                sessionIntent: "guided_lesson",
                correlationId: "corr-guided"),
            CancellationToken.None);

        Assert.Equal("corr-guided", checkpoint.CorrelationId);
        // The planned lessons are exposed via ActivePlan.CurrentLesson which
        // now points at lesson-2; lesson-1 flipped to Completed.
        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);
        Assert.NotNull(saved);
        var lessons = saved!.ActivePlan.Lessons.OrderBy(l => l.Order).ToArray();
        Assert.Equal(PlannedLessonStatus.Completed, lessons[0].Status);
        Assert.Equal(PlannedLessonStatus.Current, lessons[1].Status);
        Assert.Equal(PlannedLessonStatus.Pending, lessons[2].Status);
    }

    [Fact]
    public async Task CompleteAsyncGuidedLessonRespectsClientSuppliedLessonId()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(
            CreateStateWithPlannedLessons(tenantId, userId),
            expectedVersion: null,
            CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        // Client says the learner was on lesson-2 (out-of-order review),
        // even though lesson-1 is Current server-side.
        await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-guided-2",
                lessonId: "lesson-2",
                knowledgeUnitId: null,
                durationSeconds: 600,
                sessionIntent: "guided_lesson",
                correlationId: "corr-guided"),
            CancellationToken.None);

        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);
        Assert.NotNull(saved);
        var lessons = saved!.ActivePlan.Lessons.OrderBy(l => l.Order).ToArray();
        // lesson-1 stays Current (still on the arc), lesson-2 is Completed,
        // lesson-3 stays Pending (advancement doesn't leapfrog the arc).
        Assert.Equal(PlannedLessonStatus.Current, lessons[0].Status);
        Assert.Equal(PlannedLessonStatus.Completed, lessons[1].Status);
        Assert.Equal(PlannedLessonStatus.Pending, lessons[2].Status);
    }

    [Fact]
    public async Task CompleteAsyncGuidedLessonLeavesPlanUnchangedWhenNoLessons()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        await repository.SaveAsync(CreateState(tenantId, userId), expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-guided-empty",
                lessonId: null,
                knowledgeUnitId: null,
                durationSeconds: 600,
                sessionIntent: "guided_lesson",
                correlationId: "corr-guided"),
            CancellationToken.None);

        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);
        Assert.NotNull(saved);
        Assert.Empty(saved!.ActivePlan.Lessons);
    }

    [Fact]
    public async Task CompleteAsyncGuidedLessonLeavesLastCurrentAlreadyCompleted()
    {
        var tenantId = TenantId.Create("tenant-a");
        var userId = UserId.Create("user-a");
        var repository = new RecordingLearnerStateRepository();
        // A plan with lessons 1 and 2 completed, 3 current, none pending.
        var state = CreateStateWithPlannedLessons(tenantId, userId, currentOrder: 3);
        state = state with
        {
            ActivePlan = state.ActivePlan with
            {
                Lessons = new[]
                {
                    new PlannedLesson("lesson-1", "One", "…", 1, 15, PlannedLessonStatus.Completed),
                    new PlannedLesson("lesson-2", "Two", "…", 2, 15, PlannedLessonStatus.Completed),
                    new PlannedLesson("lesson-3", "Three", "…", 3, 15, PlannedLessonStatus.Current),
                }
            }
        };
        await repository.SaveAsync(state, expectedVersion: null, CancellationToken.None);
        var service = new LearningSessionCompletionService(repository);

        await service.CompleteAsync(
            CompleteLearningSessionCommand.Create(
                tenantId.Value,
                userId.Value,
                "session-guided-last",
                lessonId: null,
                knowledgeUnitId: null,
                durationSeconds: 600,
                sessionIntent: "guided_lesson",
                correlationId: "corr-guided"),
            CancellationToken.None);

        var saved = await repository.GetAsync(tenantId, userId, CancellationToken.None);
        Assert.NotNull(saved);
        Assert.All(saved!.ActivePlan.Lessons, l => Assert.Equal(PlannedLessonStatus.Completed, l.Status));
        Assert.Null(saved.ActivePlan.CurrentLesson);
    }

    private static LearnerState CreateState(TenantId tenantId, UserId userId)
    {
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "fr-FR", "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-1", "Beginner Foundations", ["greetings"]),
            new LessonCheckpoint("lesson-1", "greetings", 1, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private static LearnerState CreateStateWithPlannedLessons(
        TenantId tenantId,
        UserId userId,
        int currentOrder = 1)
    {
        var lessons = new PlannedLesson[]
        {
            new("lesson-1", "Greetings", "Say hello", 1, 15,
                currentOrder == 1 ? PlannedLessonStatus.Current : PlannedLessonStatus.Pending),
            new("lesson-2", "Ordering food", "Order a meal", 2, 15,
                currentOrder == 2 ? PlannedLessonStatus.Current : PlannedLessonStatus.Pending),
            new("lesson-3", "Small talk", "Chat about the weather", 3, 15,
                currentOrder == 3 ? PlannedLessonStatus.Current : PlannedLessonStatus.Pending),
        };
        return LearnerState.Create(
            tenantId,
            userId,
            new LearnerProfile(tenantId, userId, "de-DE", "en-US", "A1", ["travel"], 15),
            new ActiveLearningPlan("plan-1", "Everyday German — A1", ["greetings"], lessons),
            new LessonCheckpoint("lesson-1", "greetings", 1, DateTimeOffset.Parse("2026-08-29T07:00:00Z")),
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private sealed class RecordingLearnerStateRepository : ILearnerStateRepository
    {
        private readonly Dictionary<string, LearnerState> states = new();

        public string? RecordSessionOnNextStaleSave { get; init; }

        private bool hasRecordedSessionOnStaleSave;

        public Task<LearnerState?> GetAsync(TenantId tenantId, UserId userId, CancellationToken cancellationToken)
        {
            states.TryGetValue(Key(tenantId, userId), out var state);
            return Task.FromResult(state);
        }

        public Task<LearnerState> SaveAsync(
            LearnerState state,
            LearnerStateVersion? expectedVersion,
            CancellationToken cancellationToken)
        {
            var key = Key(state.TenantId, state.UserId);
            states.TryGetValue(key, out var current);
            if (current is not null && RecordSessionOnNextStaleSave is not null && !hasRecordedSessionOnStaleSave)
            {
                hasRecordedSessionOnStaleSave = true;
                var concurrentState = current with
                {
                    RecentSessions = new RecentSessionSummaries(
                    [new SessionSummary(RecordSessionOnNextStaleSave, DateTimeOffset.UtcNow, 300, "lesson-1")])
                };
                states[key] = concurrentState.WithVersion(current.Version.Next());
                throw new StaleLearnerStateVersionException(
                    state.TenantId,
                    state.UserId,
                    expectedVersion,
                    states[key].Version);
            }
            if (current is not null && expectedVersion != current.Version)
            {
                throw new StaleLearnerStateVersionException(state.TenantId, state.UserId, expectedVersion, current.Version);
            }

            var saved = state.WithVersion(current?.Version.Next() ?? LearnerStateVersion.Create(1));
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
