using Voxa.Application.Realtime;
using Voxa.Domain.Learners;

namespace Voxa.Application.Learners;

/// <summary>
/// Writes post-session debrief evidence to durable learner state. The
/// <see cref="RealtimeDebriefEndpoint"/> calls this after
/// <see cref="IDebriefService.GenerateDebriefAsync"/> returns, so the
/// Phase C2 curriculum planner has accumulated evidence to plan against.
/// </summary>
public interface ILearnerEvidenceService
{
    Task RecordDebriefAsync(
        TenantId tenantId,
        UserId userId,
        SessionDebrief debrief,
        CancellationToken cancellationToken);
}

public sealed class LearnerEvidenceService(ILearnerStateRepository repository) : ILearnerEvidenceService
{
    private const int MaxConcurrencyAttempts = 3;

    public async Task RecordDebriefAsync(
        TenantId tenantId,
        UserId userId,
        SessionDebrief debrief,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxConcurrencyAttempts; attempt++)
        {
            var state = await repository.GetAsync(tenantId, userId, cancellationToken);
            if (state is null)
            {
                // Learner never onboarded — nothing to attach the debrief
                // to. Silently drop the evidence; the debrief itself has
                // already been returned to the client.
                return;
            }

            // Idempotency: a retried debrief POST (network glitch, etc.)
            // must not double-append. Correlation id is the natural key.
            if (state.TutorEvidence.RecentDebriefs.Any(existing =>
                string.Equals(existing.CorrelationId, debrief.CorrelationId, StringComparison.Ordinal)))
            {
                return;
            }

            var recorded = new RecordedDebrief(
                debrief.CorrelationId,
                DateTimeOffset.UtcNow,
                debrief.Summary,
                debrief.RecurringMistakes
                    .Select(mistake => new RecordedMistake(mistake.Pattern, mistake.Example, mistake.Severity))
                    .ToArray(),
                debrief.UsefulPhrases.ToArray(),
                debrief.PronunciationNotes.ToArray(),
                new RecommendedNextDrill(
                    debrief.RecommendedNextDrill.ActivityIntent,
                    debrief.RecommendedNextDrill.FocusTitle,
                    debrief.RecommendedNextDrill.Reason));

            var nextDebriefs = new[] { recorded }
                .Concat(state.TutorEvidence.RecentDebriefs)
                .Take(TutorEvidence.MaxRecentDebriefs)
                .ToArray();

            var updated = state with
            {
                TutorEvidence = new TutorEvidence(nextDebriefs),
            };

            try
            {
                await repository.SaveAsync(updated, state.Version, cancellationToken);
                return;
            }
            catch (StaleLearnerStateVersionException)
            {
                if (attempt == MaxConcurrencyAttempts - 1)
                {
                    throw;
                }
                // Read the latest, retry with the fresher version.
            }
        }
    }
}
