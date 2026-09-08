using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

public interface ILearningSessionCompletionService
{
    Task<ResumeCheckpointResponse> CompleteAsync(
        CompleteLearningSessionCommand command,
        CancellationToken cancellationToken);
}

public sealed record CompleteLearningSessionCommand(
    TenantId TenantId,
    UserId UserId,
    string SessionId,
    string? LessonId,
    string? KnowledgeUnitId,
    int DurationSeconds,
    string? SessionIntent,
    CorrelationId CorrelationId)
{
    public static CompleteLearningSessionCommand Create(
        string? tenantId,
        string? userId,
        string? sessionId,
        string? lessonId,
        string? knowledgeUnitId,
        int? durationSeconds,
        string? sessionIntent,
        string? correlationId)
    {
        return new CompleteLearningSessionCommand(
            TenantId.Create(tenantId ?? ""),
            UserId.Create(userId ?? ""),
            Required(sessionId, nameof(sessionId)),
            Optional(lessonId),
            Optional(knowledgeUnitId),
            Math.Max(0, durationSeconds ?? 0),
            Optional(sessionIntent),
            CorrelationId.Create(correlationId));
    }

    private static string Required(string? value, string name)
    {
        return string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException($"{name} is required.", name)
            : value.Trim();
    }

    private static string? Optional(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}

public sealed class LearningSessionCompletionService(ILearnerStateRepository repository) : ILearningSessionCompletionService
{
    private const int MaxRecentSessions = 20;
    private const int MaxReviewItems = 50;
    private const int MaxConcurrencyAttempts = 3;

    public async Task<ResumeCheckpointResponse> CompleteAsync(
        CompleteLearningSessionCommand command,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxConcurrencyAttempts; attempt++)
        {
            var state = await repository.GetAsync(command.TenantId, command.UserId, cancellationToken);
            if (state is null)
            {
                throw new LearnerStateNotFoundException(command.TenantId, command.UserId);
            }

            var sessionAlreadyRecorded = state.RecentSessions.Items.Any(
                item => string.Equals(item.SessionId, command.SessionId, StringComparison.OrdinalIgnoreCase));
            if (sessionAlreadyRecorded)
            {
                return state.ToResumeCheckpoint(command.CorrelationId);
            }

            var now = DateTimeOffset.UtcNow;
            var lessonId = command.LessonId ?? state.CurrentLesson.LessonId;
            var knowledgeUnitId = command.KnowledgeUnitId ?? state.CurrentLesson.KnowledgeUnitId;
            var isLessonSession = string.Equals(command.SessionIntent, "lesson", StringComparison.OrdinalIgnoreCase);

            var updated = state with
            {
                CurrentLesson = isLessonSession
                    ? NextLessonCheckpoint(state.CurrentLesson, lessonId, knowledgeUnitId, command.SessionIntent, now)
                    : state.CurrentLesson,
                ReviewQueue = NextReviewQueue(state.ReviewQueue, knowledgeUnitId, now),
                RecentSessions = NextRecentSessions(state.RecentSessions, command, lessonId, now)
            };

            try
            {
                var saved = await repository.SaveAsync(updated, state.Version, cancellationToken);
                return saved.ToResumeCheckpoint(command.CorrelationId);
            }
            catch (StaleLearnerStateVersionException)
            {
                if (attempt == MaxConcurrencyAttempts - 1)
                {
                    throw;
                }

                // Re-read and retry so a concurrent duplicate completion becomes idempotent.
            }
        }

        throw new InvalidOperationException("Session completion did not produce a result.");
    }

    private static LessonCheckpoint NextLessonCheckpoint(
        LessonCheckpoint current,
        string? lessonId,
        string? knowledgeUnitId,
        string? sessionIntent,
        DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(lessonId) || string.IsNullOrWhiteSpace(knowledgeUnitId))
        {
            return current;
        }

        var shouldAdvance = string.Equals(sessionIntent, "lesson", StringComparison.OrdinalIgnoreCase)
            && string.Equals(current.LessonId, lessonId, StringComparison.OrdinalIgnoreCase);

        return new LessonCheckpoint(
            lessonId,
            knowledgeUnitId,
            shouldAdvance ? current.StepIndex + 1 : current.StepIndex,
            now);
    }

    private static ReviewQueue NextReviewQueue(ReviewQueue current, string? knowledgeUnitId, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(knowledgeUnitId))
        {
            return current;
        }

        var nextItems = current.Items
            .Where(item => !string.Equals(item.KnowledgeUnitId, knowledgeUnitId, StringComparison.OrdinalIgnoreCase))
            .Prepend(new ReviewQueueItem(knowledgeUnitId, now.AddDays(1), 1))
            .Take(MaxReviewItems)
            .ToArray();

        return new ReviewQueue(nextItems);
    }

    private static RecentSessionSummaries NextRecentSessions(
        RecentSessionSummaries current,
        CompleteLearningSessionCommand command,
        string? lessonId,
        DateTimeOffset now)
    {
        var session = new SessionSummary(
            command.SessionId,
            now.AddSeconds(-command.DurationSeconds),
            command.DurationSeconds,
            string.IsNullOrWhiteSpace(lessonId) ? null : lessonId);

        var nextItems = current.Items
            .Where(item => !string.Equals(item.SessionId, command.SessionId, StringComparison.OrdinalIgnoreCase))
            .Prepend(session)
            .Take(MaxRecentSessions)
            .ToArray();

        return new RecentSessionSummaries(nextItems);
    }
}
