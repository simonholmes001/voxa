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
    CorrelationId CorrelationId);

public sealed record OnboardingSubmitResponse(
    string CorrelationId,
    LearnerProfileContract Profile,
    ActiveLearningPlanContract ActivePlan,
    long Version);

public sealed record LearnerProfileContract(
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel);

public sealed record ActiveLearningPlanContract(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds);
