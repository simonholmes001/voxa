using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Voxa.Application.Learners;
using Voxa.Domain.Learners;

namespace Voxa.Application.Onboarding;

public sealed class OnboardingService(
    ILearnerStateRepository repository,
    ICourseAuthorService? courseAuthor = null,
    ILogger<OnboardingService>? logger = null)
{
    private readonly ILogger<OnboardingService> logger = logger ?? NullLogger<OnboardingService>.Instance;

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

        // Attempt to mint a personalised course from the learner's profile
        // synchronously so onboarding completes with a real course visible
        // on Home. The learner has been kept on a "Building your course…"
        // progress screen through the call. Failure is non-fatal: we fall
        // back to the placeholder plan below so onboarding always succeeds.
        var mintedPlan = await TryMintInitialCourseAsync(command, profile, activePlan, cancellationToken);
        var planForState = mintedPlan ?? activePlan;

        var state = LearnerState.Create(
            command.TenantId,
            command.UserId,
            profile,
            planForState,
            CreateInitialLessonCheckpoint(planForState),
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

    private async Task<ActiveLearningPlan?> TryMintInitialCourseAsync(
        OnboardingSubmitCommand command,
        LearnerProfile profile,
        ActiveLearningPlan fallbackPlan,
        CancellationToken cancellationToken)
    {
        if (courseAuthor is null)
        {
            return null;
        }
        try
        {
            return await courseAuthor.AuthorCourseAsync(
                new CourseAuthorRequest(
                    command.TenantId,
                    command.UserId,
                    command.CorrelationId,
                    profile,
                    ExistingCourse: null,
                    CompletedLessonIds: [],
                    RecentDebriefs: [],
                    ReassessmentRequest: null),
                cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // The Voxa.Api caller cancelled — bubble so cooperative
            // cancellation semantics reach the HTTP layer.
            throw;
        }
        catch (Exception ex)
        {
            // Non-fatal: onboarding succeeds with the placeholder plan
            // and Home shows the "Generate my course" recovery card. We
            // catch anything the author boundary didn't wrap
            // (CourseAuthorException is the intended type, but the
            // synchronous first-run path is critical enough to defend
            // against surprises — a rogue HttpRequestException,
            // TaskCanceledException from a client timeout, JsonException,
            // configuration InvalidOperationException, etc. must not
            // strand a brand-new learner). Log with correlation id +
            // language so operators can diagnose which mints are failing
            // and why.
            logger.LogWarning(
                ex,
                "course.mint.failed correlationId={CorrelationId} targetLanguage={TargetLanguage} nativeLanguage={NativeLanguage} proficiency={Proficiency} exceptionType={ExceptionType}",
                command.CorrelationId.Value,
                profile.TargetLanguage,
                profile.NativeLanguage,
                profile.ProficiencyLevel,
                ex.GetType().Name);
            _ = fallbackPlan;
            return null;
        }
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

    private static LessonCheckpoint CreateInitialLessonCheckpoint(ActiveLearningPlan activePlan)
    {
        var firstUnitId = activePlan.KnowledgeUnitIds.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(firstUnitId))
        {
            return LessonCheckpoint.None;
        }

        return new LessonCheckpoint(
            $"lesson-{firstUnitId}",
            firstUnitId,
            0,
            DateTimeOffset.UtcNow);
    }
}
