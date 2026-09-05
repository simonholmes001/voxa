using Voxa.Domain.Learners;

namespace Voxa.Application.Onboarding;

public sealed record OnboardingSubmitCommand(
    TenantId TenantId,
    UserId UserId,
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel,
    IReadOnlyList<string> Goals,
    int DailyMinutes,
    CorrelationId CorrelationId,
    LearnerStateVersion? ExpectedVersion = null);

public sealed record OnboardingSubmitResponse(
    string CorrelationId,
    OnboardingLearnerProfileContract Profile,
    ActiveLearningPlanContract ActivePlan,
    long Version);

public sealed record OnboardingLearnerProfileContract(
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel,
    IReadOnlyList<string> Goals,
    int DailyMinutes);

public sealed record ActiveLearningPlanContract(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds);
