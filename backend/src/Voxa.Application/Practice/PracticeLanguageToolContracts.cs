using Voxa.Domain.Learners;

namespace Voxa.Application.Practice;

public sealed record AskAnythingCommand(
    string TargetLanguage,
    string? NativeLanguage,
    string Question,
    CorrelationId CorrelationId);

public sealed record TranslationCommand(
    string? SourceLanguage,
    string TargetLanguage,
    string Text,
    CorrelationId CorrelationId);

public sealed record ImageTranslationCommand(
    string? SourceLanguage,
    string TargetLanguage,
    string ImageBase64,
    string MimeType,
    CorrelationId CorrelationId);

public sealed record VocabularyQuizCommand(
    string TargetLanguage,
    string ProficiencyBand,
    string? Focus,
    int Count,
    CorrelationId CorrelationId);

public sealed record AskAnythingResult(
    string Answer,
    IReadOnlyList<PhraseExample> Examples);

public sealed record PhraseExample(
    string Source,
    string Target,
    string Note);

public sealed record TranslationResult(
    string SourceLanguage,
    string TargetLanguage,
    string TranslatedText,
    string Notes);

public sealed record ImageTranslationResult(
    string DetectedText,
    string SourceLanguage,
    string TargetLanguage,
    string TranslatedText,
    string Notes);

public sealed record VocabularyQuizResult(
    IReadOnlyList<VocabularyQuizItem> Items);

public sealed record VocabularyQuizItem(
    string Prompt,
    IReadOnlyList<string> Choices,
    int CorrectChoiceIndex,
    string Explanation);

public interface IPracticeLanguageToolService
{
    Task<AskAnythingResult> AskAnythingAsync(AskAnythingCommand command, CancellationToken cancellationToken);

    Task<TranslationResult> TranslateAsync(TranslationCommand command, CancellationToken cancellationToken);

    Task<ImageTranslationResult> TranslateImageAsync(ImageTranslationCommand command, CancellationToken cancellationToken);

    Task<VocabularyQuizResult> CreateVocabularyQuizAsync(VocabularyQuizCommand command, CancellationToken cancellationToken);
}

public sealed class PracticeLanguageToolException(string message) : Exception(message);
