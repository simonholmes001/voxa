using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Onboarding;

public sealed class OnboardingService(ILearnerStateRepository repository)
{
    public async Task<OnboardingSubmitResponse> SubmitAsync(
        OnboardingSubmitCommand command,
        CancellationToken cancellationToken)
    {
        // Check if learner state already exists
        var existing = await repository.GetAsync(command.TenantId, command.UserId, cancellationToken);
        if (existing is not null)
        {
            // Update existing profile (idempotent onboarding)
            var updatedProfile = existing.Profile with
            {
                TargetLanguage = command.TargetLanguage,
                NativeLanguage = command.NativeLanguage,
                ProficiencyLevel = command.ProficiencyLevel,
                Goals = command.Goals,
                DailyMinutes = command.DailyMinutes
            };
            var updated = existing with { Profile = updatedProfile };
            await repository.SaveAsync(updated, existing.Version, cancellationToken);

            return new OnboardingSubmitResponse(
                command.CorrelationId.Value,
                new OnboardingLearnerProfileContract(
                    updated.Profile.TargetLanguage,
                    updated.Profile.NativeLanguage,
                    updated.Profile.ProficiencyLevel,
                    updated.Profile.Goals,
                    updated.Profile.DailyMinutes),
                new ActiveLearningPlanContract(
                    updated.ActivePlan.PlanId,
                    updated.ActivePlan.Title,
                    updated.ActivePlan.KnowledgeUnitIds),
                updated.Version.Value);
        }

        // Create new learner state
        var profile = new LearnerProfile(
            command.TenantId,
            command.UserId,
            command.TargetLanguage,
            command.NativeLanguage,
            command.ProficiencyLevel,
            command.Goals,
            command.DailyMinutes);

        // Generate initial learning plan based on proficiency and goals
        var activePlan = GenerateInitialPlan(command.ProficiencyLevel, command.Goals);

        var state = LearnerState.Create(
            command.TenantId,
            command.UserId,
            profile,
            activePlan,
            LessonCheckpoint.None,
            ReviewQueue.Empty,
            RecentSessionSummaries.Empty);

        var saved = await repository.SaveAsync(state, null, cancellationToken);

        return new OnboardingSubmitResponse(
            command.CorrelationId.Value,
            new OnboardingLearnerProfileContract(
                saved.Profile.TargetLanguage,
                saved.Profile.NativeLanguage,
                saved.Profile.ProficiencyLevel,
                saved.Profile.Goals,
                saved.Profile.DailyMinutes),
            new ActiveLearningPlanContract(
                saved.ActivePlan.PlanId,
                saved.ActivePlan.Title,
                saved.ActivePlan.KnowledgeUnitIds),
            saved.Version.Value);
    }

    private static ActiveLearningPlan GenerateInitialPlan(string proficiencyLevel, IReadOnlyList<string> goals)
    {
        // MVP: Generate a simple plan based on proficiency level
        var planTitle = proficiencyLevel switch
        {
            "A1" => "Beginner Foundations",
            "A2" => "Elementary Progress",
            "B1" => "Intermediate Expansion",
            "B2" => "Upper Intermediate Mastery",
            "C1" => "Advanced Fluency",
            "C2" => "Near-Native Proficiency",
            _ => "Custom Learning Path"
        };

        // Initial knowledge units based on proficiency and goals
        var knowledgeUnits = proficiencyLevel switch
        {
            "A1" => new[] { "greetings", "numbers", "basic-questions" },
            "A2" => new[] { "daily-routines", "past-tense", "shopping" },
            "B1" => new[] { "opinions", "stories", "travel" },
            "B2" => new[] { "debates", "presentations", "complex-grammar" },
            "C1" => new[] { "idioms", "nuance", "professional" },
            "C2" => new[] { "mastery", "regional-variants", "literature" },
            _ => new[] { "assessment" }
        };

        return new ActiveLearningPlan(
            $"plan-{proficiencyLevel.ToLowerInvariant()}",
            planTitle,
            knowledgeUnits);
    }
}
