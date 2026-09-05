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
        var existing = await repository.GetAsync(
            command.TenantId,
            command.UserId,
            command.TargetLanguage,
            cancellationToken);
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
            var expectedVersion = command.ExpectedVersion ?? existing.Version;
            var savedUpdate = await repository.SaveAsync(updated, expectedVersion, cancellationToken);

            await repository.SetActiveLanguageAsync(
                command.TenantId,
                command.UserId,
                savedUpdate.Profile.TargetLanguage,
                cancellationToken);

            return new OnboardingSubmitResponse(
                command.CorrelationId.Value,
                new OnboardingLearnerProfileContract(
                    savedUpdate.Profile.TargetLanguage,
                    savedUpdate.Profile.NativeLanguage,
                    savedUpdate.Profile.ProficiencyLevel,
                    savedUpdate.Profile.Goals,
                    savedUpdate.Profile.DailyMinutes),
                new ActiveLearningPlanContract(
                    savedUpdate.ActivePlan.PlanId,
                    savedUpdate.ActivePlan.Title,
                    savedUpdate.ActivePlan.KnowledgeUnitIds),
                savedUpdate.Version.Value);
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

        // A new language profile has no prior version to compare with. Any
        // client token belongs to another profile and must not gate creation.
        var saved = await repository.SaveAsync(state, expectedVersion: null, cancellationToken);

        await repository.SetActiveLanguageAsync(
            command.TenantId,
            command.UserId,
            saved.Profile.TargetLanguage,
            cancellationToken);

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
