using Voxa.Api.Http;
using Voxa.Application.Authentication;
using Voxa.Application.Practice;
using Voxa.Domain.Learners;

namespace Voxa.Api.Tests;

public sealed class PracticeLanguageToolEndpointTests
{
    [Fact]
    public async Task AskReturnsUnauthorizedWithoutAppSession()
    {
        var endpoint = new PracticeLanguageToolEndpoint(new StubPracticeLanguageToolService());

        var response = await endpoint.AskAsync(
            null,
            new AskAnythingHttpRequest("French", null, "How do I say hello?"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(401, response.StatusCode);
        Assert.Equal("app_session_required", response.Error?.Code);
    }

    [Fact]
    public async Task AskForwardsQuestionToService()
    {
        var service = new StubPracticeLanguageToolService();
        var endpoint = new PracticeLanguageToolEndpoint(service);

        var response = await endpoint.AskAsync(
            Principal(),
            new AskAnythingHttpRequest("French", "English", "How do I say see you soon?"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.Equal("French", service.AskCommand?.TargetLanguage);
        Assert.Equal("English", service.AskCommand?.NativeLanguage);
        Assert.Equal("How do I say see you soon?", service.AskCommand?.Question);
        Assert.Equal("A bientot", response.Body?.Examples[0].Target);
    }

    [Fact]
    public async Task TranslateImageRejectsUnsupportedMimeType()
    {
        var endpoint = new PracticeLanguageToolEndpoint(new StubPracticeLanguageToolService());

        var response = await endpoint.TranslateImageAsync(
            Principal(),
            new ImageTranslationHttpRequest(null, "French", "abcd", "image/gif"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
    }

    [Fact]
    public async Task VocabularyQuizClampsQuestionCount()
    {
        var service = new StubPracticeLanguageToolService();
        var endpoint = new PracticeLanguageToolEndpoint(service);

        var response = await endpoint.VocabularyQuizAsync(
            Principal(),
            new VocabularyQuizHttpRequest("French", "A1-A2", "travel", 99),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.Equal(10, service.VocabularyCommand?.Count);
    }

    private static AppSessionPrincipal Principal()
    {
        return new AppSessionPrincipal(TenantId.Create("tenant-default"), UserId.Create("user-a"));
    }

    private sealed class StubPracticeLanguageToolService : IPracticeLanguageToolService
    {
        public AskAnythingCommand? AskCommand { get; private set; }
        public VocabularyQuizCommand? VocabularyCommand { get; private set; }

        public Task<AskAnythingResult> AskAnythingAsync(
            AskAnythingCommand command,
            CancellationToken cancellationToken)
        {
            AskCommand = command;
            return Task.FromResult(new AskAnythingResult(
                "Use A bientot.",
                new[] { new PhraseExample("See you soon", "A bientot", "Casual.") }));
        }

        public Task<TranslationResult> TranslateAsync(
            TranslationCommand command,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new TranslationResult(
                command.SourceLanguage ?? "English",
                command.TargetLanguage,
                "Bonjour",
                "Neutral."));
        }

        public Task<ImageTranslationResult> TranslateImageAsync(
            ImageTranslationCommand command,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new ImageTranslationResult(
                "Sortie",
                command.SourceLanguage ?? "French",
                command.TargetLanguage,
                "Exit",
                "Sign text."));
        }

        public Task<VocabularyQuizResult> CreateVocabularyQuizAsync(
            VocabularyQuizCommand command,
            CancellationToken cancellationToken)
        {
            VocabularyCommand = command;
            return Task.FromResult(new VocabularyQuizResult(
                new[]
                {
                    new VocabularyQuizItem(
                        "Choose the word for bread.",
                        new[] { "pain", "eau", "lait" },
                        0,
                        "Pain means bread."),
                }));
        }
    }
}
