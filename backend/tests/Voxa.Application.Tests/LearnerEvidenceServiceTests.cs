using Voxa.Application.Learners;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Application.Tests;

public sealed class LearnerEvidenceServiceTests
{
    private static readonly TenantId Tenant = TenantId.Create("tenant-a");
    private static readonly UserId User = UserId.Create("user-a");

    [Fact]
    public async Task RecordDebriefAsyncSilentlyDropsWhenLearnerStateDoesNotExist()
    {
        // Guard against orphaned debriefs. If for any reason the learner has
        // no persistent state (e.g. never onboarded), don't crash — just
        // don't persist. The client has already seen its debrief.
        var repository = new FakeRepository();
        var service = new LearnerEvidenceService(repository);

        await service.RecordDebriefAsync(Tenant, User, SampleDebrief("d1"), CancellationToken.None);

        Assert.Empty(repository.Saved);
    }

    [Fact]
    public async Task RecordDebriefAsyncPrependsNewDebriefAtHeadOfTutorEvidence()
    {
        // Newest first — matches how the C2 planner will want to weight the
        // most recent session most heavily.
        var repository = new FakeRepository();
        repository.Seed(BaseState(Tenant, User));
        var service = new LearnerEvidenceService(repository);

        await service.RecordDebriefAsync(Tenant, User, SampleDebrief("d1"), CancellationToken.None);
        await service.RecordDebriefAsync(Tenant, User, SampleDebrief("d2"), CancellationToken.None);

        var saved = repository.Saved.Last();
        Assert.Equal(2, saved.TutorEvidence.RecentDebriefs.Count);
        Assert.Equal("d2", saved.TutorEvidence.RecentDebriefs[0].CorrelationId);
        Assert.Equal("d1", saved.TutorEvidence.RecentDebriefs[1].CorrelationId);
    }

    [Fact]
    public async Task RecordDebriefAsyncStopsAppendingBeyondTheRetentionCap()
    {
        // TutorEvidence.MaxRecentDebriefs (20) is the ceiling. Older debriefs
        // roll off the tail so the JSON blob stays small and reads stay fast.
        var repository = new FakeRepository();
        repository.Seed(BaseState(Tenant, User));
        var service = new LearnerEvidenceService(repository);

        for (var i = 0; i < TutorEvidence.MaxRecentDebriefs + 5; i++)
        {
            await service.RecordDebriefAsync(Tenant, User, SampleDebrief($"d{i}"), CancellationToken.None);
        }

        var saved = repository.Saved.Last();
        Assert.Equal(TutorEvidence.MaxRecentDebriefs, saved.TutorEvidence.RecentDebriefs.Count);
        // Newest survives (last one appended = "d24").
        Assert.Equal("d24", saved.TutorEvidence.RecentDebriefs[0].CorrelationId);
        // Oldest that survives is d5 (d0..d4 rolled off).
        Assert.Equal("d5", saved.TutorEvidence.RecentDebriefs[^1].CorrelationId);
    }

    [Fact]
    public async Task RecordDebriefAsyncIsIdempotentAcrossRetriedPostsWithTheSameCorrelationId()
    {
        // A retried POST — client saw a network glitch and re-sent — must
        // not double-append the same debrief.
        var repository = new FakeRepository();
        repository.Seed(BaseState(Tenant, User));
        var service = new LearnerEvidenceService(repository);

        await service.RecordDebriefAsync(Tenant, User, SampleDebrief("d1"), CancellationToken.None);
        await service.RecordDebriefAsync(Tenant, User, SampleDebrief("d1"), CancellationToken.None);

        var saved = repository.Saved.Last();
        Assert.Single(saved.TutorEvidence.RecentDebriefs);
        Assert.Equal("d1", saved.TutorEvidence.RecentDebriefs[0].CorrelationId);
    }

    [Fact]
    public async Task RecordDebriefAsyncRetriesOnStaleVersionConflictUpToConcurrencyLimit()
    {
        // A concurrent write from another endpoint (e.g. session complete)
        // could bump the version between our Get and Save. The service reads
        // fresh state and retries.
        var repository = new FakeRepository();
        repository.Seed(BaseState(Tenant, User));
        repository.FailNextSavesWithStaleVersion = 2;
        var service = new LearnerEvidenceService(repository);

        await service.RecordDebriefAsync(Tenant, User, SampleDebrief("d1"), CancellationToken.None);

        // Two failed attempts + one succeeding attempt = 3 SaveAsync calls.
        Assert.Equal(3, repository.SaveAttempts);
        var saved = repository.Saved.Last();
        Assert.Single(saved.TutorEvidence.RecentDebriefs);
    }

    [Fact]
    public async Task RecordDebriefAsyncThrowsAfterExceedingConcurrencyRetries()
    {
        var repository = new FakeRepository();
        repository.Seed(BaseState(Tenant, User));
        repository.FailNextSavesWithStaleVersion = int.MaxValue;
        var service = new LearnerEvidenceService(repository);

        await Assert.ThrowsAsync<StaleLearnerStateVersionException>(() =>
            service.RecordDebriefAsync(Tenant, User, SampleDebrief("d1"), CancellationToken.None));
    }

    [Fact]
    public async Task RecordDebriefAsyncPreservesAllFieldsOfTheDebriefWhenPersisting()
    {
        var repository = new FakeRepository();
        repository.Seed(BaseState(Tenant, User));
        var service = new LearnerEvidenceService(repository);

        var debrief = new SessionDebrief(
            "corr-full",
            "You practised past tense.",
            [
                new DebriefRecurringMistake("past participle", "I have ate", "medium"),
                new DebriefRecurringMistake("word order", "The book blue", "low"),
            ],
            ["How's it going?", "See you later"],
            ["'th' needs more tongue-tip contact"],
            new DebriefRecommendedDrill("pronunciation_drill", "English th", "you tripped on 'th' twice."));

        await service.RecordDebriefAsync(Tenant, User, debrief, CancellationToken.None);

        var recorded = repository.Saved.Last().TutorEvidence.RecentDebriefs[0];
        Assert.Equal("corr-full", recorded.CorrelationId);
        Assert.Equal("You practised past tense.", recorded.Summary);
        Assert.Equal(2, recorded.RecurringMistakes.Count);
        Assert.Equal("past participle", recorded.RecurringMistakes[0].Pattern);
        Assert.Equal("medium", recorded.RecurringMistakes[0].Severity);
        Assert.Equal(2, recorded.UsefulPhrases.Count);
        Assert.Single(recorded.PronunciationNotes);
        Assert.Equal("pronunciation_drill", recorded.RecommendedNextDrill.ActivityIntent);
        Assert.Equal("English th", recorded.RecommendedNextDrill.FocusTitle);
    }

    // MARK: - Helpers

    private static LearnerState BaseState(TenantId tenant, UserId user)
    {
        return LearnerState.Create(
            tenant,
            user,
            new LearnerProfile(tenant, user, "fr-FR", "en-US", "A1", ["travel"], 15),
            ActiveLearningPlan.Empty,
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);
    }

    private static SessionDebrief SampleDebrief(string correlationId)
    {
        return new SessionDebrief(
            correlationId,
            "summary",
            [],
            [],
            [],
            new DebriefRecommendedDrill("open_practice", "", ""));
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
        {
            throw new NotSupportedException();
        }
    }
}
