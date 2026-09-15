using Voxa.Application.Authentication;
using Voxa.Application.Practice;
using Voxa.Domain.Learners;

namespace Voxa.Api.Http;

public sealed class PracticeLanguageToolEndpoint(IPracticeLanguageToolService service)
{
    private const int MaxTextLength = 2_000;
    private const int MaxPromptLabelLength = 128;
    private const int MaxFocusLength = 256;
    private const int MaxImageDecodedBytes = 5_000_000;
    private const int MaxImageBase64Length = ((MaxImageDecodedBytes + 2) / 3) * 4;

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
        var nativeLanguage = NormalizeOptional(request.NativeLanguage);
        var question = NormalizeRequired(request.Question);
        if (targetLanguage is null ||
            question is null ||
            !WithinLimit(targetLanguage, MaxPromptLabelLength) ||
            !WithinLimit(nativeLanguage, MaxPromptLabelLength) ||
            !WithinLimit(question, MaxTextLength))
        {
            return Validation<AskAnythingHttpResponse>(
                "Ask anything requires a target language under 128 characters, an optional native language under 128 characters, and a question under 2,000 characters.",
                correlationId);
        }

        try
        {
            var result = await service.AskAnythingAsync(
                new AskAnythingCommand(
                    targetLanguage,
                    nativeLanguage,
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
        var sourceLanguage = NormalizeOptional(request.SourceLanguage);
        var text = NormalizeRequired(request.Text);
        if (targetLanguage is null ||
            text is null ||
            !WithinLimit(sourceLanguage, MaxPromptLabelLength) ||
            !WithinLimit(targetLanguage, MaxPromptLabelLength) ||
            !WithinLimit(text, MaxTextLength))
        {
            return Validation<TranslationHttpResponse>(
                "Translation requires source and target languages under 128 characters and text under 2,000 characters.",
                correlationId);
        }

        try
        {
            var result = await service.TranslateAsync(
                new TranslationCommand(
                    sourceLanguage,
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
        var sourceLanguage = NormalizeOptional(request.SourceLanguage);
        var imageBase64 = NormalizeRequired(request.ImageBase64);
        var mimeType = NormalizeRequired(request.MimeType);
        var validatedImage = imageBase64 is null || mimeType is null
            ? null
            : ValidateImagePayload(imageBase64, mimeType);
        if (targetLanguage is null ||
            imageBase64 is null ||
            mimeType is null ||
            !WithinLimit(sourceLanguage, MaxPromptLabelLength) ||
            !WithinLimit(targetLanguage, MaxPromptLabelLength) ||
            validatedImage is null)
        {
            return Validation<ImageTranslationHttpResponse>(
                "Image translation requires source and target languages under 128 characters and a png, jpeg, or webp image under the upload limit.",
                correlationId);
        }

        try
        {
            var result = await service.TranslateImageAsync(
                new ImageTranslationCommand(
                    sourceLanguage,
                    targetLanguage,
                    validatedImage.Value.Base64,
                    validatedImage.Value.MimeType,
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
        var focus = NormalizeOptional(request.Focus);
        var count = Math.Clamp(request.Count ?? 5, 3, 10);
        if (targetLanguage is null ||
            proficiencyBand is null ||
            !WithinLimit(targetLanguage, MaxPromptLabelLength) ||
            !WithinLimit(proficiencyBand, MaxPromptLabelLength) ||
            !WithinLimit(focus, MaxFocusLength))
        {
            return Validation<VocabularyQuizHttpResponse>(
                "Vocabulary quiz requires a target language and proficiency band under 128 characters, and an optional focus under 256 characters.",
                correlationId);
        }

        try
        {
            var result = await service.CreateVocabularyQuizAsync(
                new VocabularyQuizCommand(
                    targetLanguage,
                    proficiencyBand,
                    focus,
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

    private static bool WithinLimit(string? value, int maxLength)
    {
        return value is null || value.Length <= maxLength;
    }

    private static ValidatedImagePayload? ValidateImagePayload(string imageBase64, string mimeType)
    {
        if (!AllowedImageMimeTypes.Contains(mimeType) || imageBase64.Length > MaxImageBase64Length)
        {
            return null;
        }

        var buffer = new byte[MaxDecodedByteCount(imageBase64.Length)];
        if (!Convert.TryFromBase64String(imageBase64, buffer, out var bytesWritten) ||
            bytesWritten == 0 ||
            bytesWritten > MaxImageDecodedBytes)
        {
            return null;
        }

        var bytes = buffer.AsSpan(0, bytesWritten);
        if (!MatchesDeclaredMimeType(bytes, mimeType))
        {
            return null;
        }

        return new ValidatedImagePayload(Convert.ToBase64String(bytes), mimeType.ToLowerInvariant());
    }

    private static int MaxDecodedByteCount(int base64Length)
    {
        return ((base64Length + 3) / 4) * 3;
    }

    private static bool MatchesDeclaredMimeType(ReadOnlySpan<byte> bytes, string mimeType)
    {
        return mimeType.ToLowerInvariant() switch
        {
            "image/jpeg" => IsJpeg(bytes),
            "image/png" => IsPng(bytes),
            "image/webp" => IsWebP(bytes),
            _ => false,
        };
    }

    private static bool IsJpeg(ReadOnlySpan<byte> bytes)
    {
        return bytes.Length >= 3 &&
               bytes[0] == 0xFF &&
               bytes[1] == 0xD8 &&
               bytes[2] == 0xFF;
    }

    private static bool IsPng(ReadOnlySpan<byte> bytes)
    {
        ReadOnlySpan<byte> signature = stackalloc byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        return bytes.StartsWith(signature);
    }

    private static bool IsWebP(ReadOnlySpan<byte> bytes)
    {
        ReadOnlySpan<byte> riff = stackalloc byte[] { 0x52, 0x49, 0x46, 0x46 };
        ReadOnlySpan<byte> webp = stackalloc byte[] { 0x57, 0x45, 0x42, 0x50 };
        return bytes.Length >= 12 &&
               bytes[..4].SequenceEqual(riff) &&
               bytes[8..12].SequenceEqual(webp);
    }

    private static readonly HashSet<string> AllowedImageMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/png",
        "image/webp",
    };

    private readonly record struct ValidatedImagePayload(string Base64, string MimeType);
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
