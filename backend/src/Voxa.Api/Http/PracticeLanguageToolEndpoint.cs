using Voxa.Application.Authentication;
using Voxa.Application.Practice;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class PracticeLanguageToolEndpoint(IPracticeLanguageToolService service)
{
    private const int MaxTextLength = 2_000;
    private const int MaxImageBase64Length = 7_500_000;

    public async Task<ApiResponse<AskAnythingHttpResponse>> AskAsync(
        AppSessionPrincipal? principal,
        AskAnythingHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        if (principal is null)
        {
            return Unauthorized<AskAnythingHttpResponse>(correlationId);
        }

        var targetLanguage = NormalizeRequired(request.TargetLanguage);
        var question = NormalizeRequired(request.Question);
        if (targetLanguage is null || question is null || question.Length > MaxTextLength)
        {
            return Validation<AskAnythingHttpResponse>("Ask anything requires a target language and a question under 2,000 characters.", correlationId);
        }

        try
        {
            var result = await service.AskAnythingAsync(
                new AskAnythingCommand(
                    targetLanguage,
                    NormalizeOptional(request.NativeLanguage),
                    question,
                    CorrelationId.Create(correlationId)),
                cancellationToken);
            return ApiResponse<AskAnythingHttpResponse>.Ok(new AskAnythingHttpResponse(
                result.Answer,
                result.Examples.Select(example => new PhraseExampleHttpResponse(example.Source, example.Target, example.Note)).ToArray()));
        }
        catch (PracticeLanguageToolException exception)
        {
            return ToolFailure<AskAnythingHttpResponse>(exception, correlationId);
        }
    }

    public async Task<ApiResponse<TranslationHttpResponse>> TranslateAsync(
        AppSessionPrincipal? principal,
        TranslationHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        if (principal is null)
        {
            return Unauthorized<TranslationHttpResponse>(correlationId);
        }

        var targetLanguage = NormalizeRequired(request.TargetLanguage);
        var text = NormalizeRequired(request.Text);
        if (targetLanguage is null || text is null || text.Length > MaxTextLength)
        {
            return Validation<TranslationHttpResponse>("Translation requires a target language and text under 2,000 characters.", correlationId);
        }

        try
        {
            var result = await service.TranslateAsync(
                new TranslationCommand(
                    NormalizeOptional(request.SourceLanguage),
                    targetLanguage,
                    text,
                    CorrelationId.Create(correlationId)),
                cancellationToken);
            return ApiResponse<TranslationHttpResponse>.Ok(new TranslationHttpResponse(
                result.SourceLanguage,
                result.TargetLanguage,
                result.TranslatedText,
                result.Notes));
        }
        catch (PracticeLanguageToolException exception)
        {
            return ToolFailure<TranslationHttpResponse>(exception, correlationId);
        }
    }

    public async Task<ApiResponse<ImageTranslationHttpResponse>> TranslateImageAsync(
        AppSessionPrincipal? principal,
        ImageTranslationHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        if (principal is null)
        {
            return Unauthorized<ImageTranslationHttpResponse>(correlationId);
        }

        var targetLanguage = NormalizeRequired(request.TargetLanguage);
        var imageBase64 = NormalizeRequired(request.ImageBase64);
        var mimeType = NormalizeRequired(request.MimeType);
        if (targetLanguage is null ||
            imageBase64 is null ||
            mimeType is null ||
            imageBase64.Length > MaxImageBase64Length ||
            !AllowedImageMimeTypes.Contains(mimeType))
        {
            return Validation<ImageTranslationHttpResponse>("Image translation requires a png, jpeg, or webp image under the upload limit.", correlationId);
        }

        try
        {
            var result = await service.TranslateImageAsync(
                new ImageTranslationCommand(
                    NormalizeOptional(request.SourceLanguage),
                    targetLanguage,
                    imageBase64,
                    mimeType,
                    CorrelationId.Create(correlationId)),
                cancellationToken);
            return ApiResponse<ImageTranslationHttpResponse>.Ok(new ImageTranslationHttpResponse(
                result.DetectedText,
                result.SourceLanguage,
                result.TargetLanguage,
                result.TranslatedText,
                result.Notes));
        }
        catch (PracticeLanguageToolException exception)
        {
            return ToolFailure<ImageTranslationHttpResponse>(exception, correlationId);
        }
    }

    public async Task<ApiResponse<VocabularyQuizHttpResponse>> VocabularyQuizAsync(
        AppSessionPrincipal? principal,
        VocabularyQuizHttpRequest request,
        string? correlationId,
        CancellationToken cancellationToken)
    {
        if (principal is null)
        {
            return Unauthorized<VocabularyQuizHttpResponse>(correlationId);
        }

        var targetLanguage = NormalizeRequired(request.TargetLanguage);
        var proficiencyBand = NormalizeRequired(request.ProficiencyBand);
        var count = Math.Clamp(request.Count ?? 5, 3, 10);
        if (targetLanguage is null || proficiencyBand is null)
        {
            return Validation<VocabularyQuizHttpResponse>("Vocabulary quiz requires a target language and proficiency band.", correlationId);
        }

        try
        {
            var result = await service.CreateVocabularyQuizAsync(
                new VocabularyQuizCommand(
                    targetLanguage,
                    proficiencyBand,
                    NormalizeOptional(request.Focus),
                    count,
                    CorrelationId.Create(correlationId)),
                cancellationToken);
            return ApiResponse<VocabularyQuizHttpResponse>.Ok(new VocabularyQuizHttpResponse(
                result.Items.Select(item => new VocabularyQuizItemHttpResponse(
                    item.Prompt,
                    item.Choices,
                    item.CorrectChoiceIndex,
                    item.Explanation)).ToArray()));
        }
        catch (PracticeLanguageToolException exception)
        {
            return ToolFailure<VocabularyQuizHttpResponse>(exception, correlationId);
        }
    }

    private static ApiResponse<T> Unauthorized<T>(string? correlationId)
    {
        return ApiResponse<T>.Failure(
            401,
            new ApiErrorResponse(
                "app_session_required",
                "An authenticated app session is required.",
                CorrelationId.Create(correlationId).Value,
                false));
    }

    private static ApiResponse<T> Validation<T>(string message, string? correlationId)
    {
        return ApiResponse<T>.Failure(
            400,
            new ApiErrorResponse(
                "validation_error",
                message,
                CorrelationId.Create(correlationId).Value,
                false));
    }

    private static ApiResponse<T> ToolFailure<T>(PracticeLanguageToolException exception, string? correlationId)
    {
        return ApiResponse<T>.Failure(
            502,
            new ApiErrorResponse(
                "language_tool_unavailable",
                exception.Message,
                CorrelationId.Create(correlationId).Value,
                true));
    }

    private static string? NormalizeRequired(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static string? NormalizeOptional(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static readonly HashSet<string> AllowedImageMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/png",
        "image/webp",
    };
}

public sealed record AskAnythingHttpRequest(
    string? TargetLanguage,
    string? NativeLanguage,
    string? Question);

public sealed record PhraseExampleHttpResponse(
    string Source,
    string Target,
    string Note);

public sealed record AskAnythingHttpResponse(
    string Answer,
    IReadOnlyList<PhraseExampleHttpResponse> Examples);

public sealed record TranslationHttpRequest(
    string? SourceLanguage,
    string? TargetLanguage,
    string? Text);

public sealed record TranslationHttpResponse(
    string SourceLanguage,
    string TargetLanguage,
    string TranslatedText,
    string Notes);

public sealed record ImageTranslationHttpRequest(
    string? SourceLanguage,
    string? TargetLanguage,
    string? ImageBase64,
    string? MimeType);

public sealed record ImageTranslationHttpResponse(
    string DetectedText,
    string SourceLanguage,
    string TargetLanguage,
    string TranslatedText,
    string Notes);

public sealed record VocabularyQuizHttpRequest(
    string? TargetLanguage,
    string? ProficiencyBand,
    string? Focus,
    int? Count);

public sealed record VocabularyQuizHttpResponse(
    IReadOnlyList<VocabularyQuizItemHttpResponse> Items);

public sealed record VocabularyQuizItemHttpResponse(
    string Prompt,
    IReadOnlyList<string> Choices,
    int CorrectChoiceIndex,
    string Explanation);
