using Voxa.Application.Onboarding;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class OnboardingSubmitEndpoint(OnboardingService onboardingService)
{
    public async Task<ApiResponse<OnboardingSubmitHttpResponse>> PostAsync(
        OnboardingSubmitHttpRequest request,
        TenantId tenantId,
        UserId userId,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        var requestCorrelationId = CorrelationId.Create(correlationId);

        try
        {
            var command = new OnboardingSubmitCommand(
                tenantId,
                userId,
                ValidateRequired(request.TargetLanguage, "targetLanguage"),
                ValidateRequired(request.NativeLanguage, "nativeLanguage"),
                ValidateRequired(request.ProficiencyLevel, "proficiencyLevel"),
                request.Goals ?? Array.Empty<string>(),
                request.DailyMinutes ?? 15,
                requestCorrelationId);

            var response = await onboardingService.SubmitAsync(command, cancellationToken);

            return ApiResponse<OnboardingSubmitHttpResponse>.Ok(
                OnboardingSubmitHttpResponse.FromApplicationResponse(response));
        }
        catch (ArgumentException exception)
        {
            return Failure<OnboardingSubmitHttpResponse>(
                "validation_error",
                exception.Message,
                requestCorrelationId,
                400,
                retryable: false);
        }
    }

    private static string ValidateRequired(string? value, string fieldName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"{fieldName} is required.");
        }
        return value;
    }

    private static ApiResponse<T> Failure<T>(
        string code,
        string message,
        CorrelationId correlationId,
        int statusCode,
        bool retryable)
    {
        return ApiResponse<T>.Failure(
            statusCode,
            new ApiErrorResponse(code, message, correlationId.Value, retryable));
    }
}

public sealed record OnboardingSubmitHttpRequest(
    string? TargetLanguage,
    string? NativeLanguage,
    string? ProficiencyLevel,
    IReadOnlyList<string>? Goals,
    int? DailyMinutes);

public sealed record OnboardingSubmitHttpResponse(
    string CorrelationId,
    OnboardingProfileHttpResponse Profile,
    OnboardingActivePlanHttpResponse ActivePlan,
    long Version)
{
    public static OnboardingSubmitHttpResponse FromApplicationResponse(OnboardingSubmitResponse response)
    {
        return new OnboardingSubmitHttpResponse(
            response.CorrelationId,
            new OnboardingProfileHttpResponse(
                response.Profile.TargetLanguage,
                response.Profile.NativeLanguage,
                response.Profile.ProficiencyLevel,
                response.Profile.Goals,
                response.Profile.DailyMinutes),
            new OnboardingActivePlanHttpResponse(
                response.ActivePlan.PlanId,
                response.ActivePlan.Title,
                response.ActivePlan.KnowledgeUnitIds),
            response.Version);
    }
}

public sealed record OnboardingProfileHttpResponse(
    string TargetLanguage,
    string NativeLanguage,
    string ProficiencyLevel,
    IReadOnlyList<string> Goals,
    int DailyMinutes);

public sealed record OnboardingActivePlanHttpResponse(
    string PlanId,
    string Title,
    IReadOnlyList<string> KnowledgeUnitIds);
