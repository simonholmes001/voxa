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
            new ImageTranslationHttpRequest(null, "French", ValidPngBase64(), "image/gif"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
    }

    [Fact]
    public async Task TranslateImageRejectsInvalidBase64()
    {
        var service = new StubPracticeLanguageToolService();
        var endpoint = new PracticeLanguageToolEndpoint(service);

        var response = await endpoint.TranslateImageAsync(
            Principal(),
            new ImageTranslationHttpRequest(null, "French", "not-base64", "image/png"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
        Assert.Null(service.ImageCommand);
    }

    [Fact]
    public async Task TranslateImageRejectsDecodedImagesOverLimit()
    {
        var service = new StubPracticeLanguageToolService();
        var endpoint = new PracticeLanguageToolEndpoint(service);
        var bytes = new byte[5_000_001];
        bytes[0] = 0x89;
        bytes[1] = 0x50;
        bytes[2] = 0x4E;
        bytes[3] = 0x47;
        bytes[4] = 0x0D;
        bytes[5] = 0x0A;
        bytes[6] = 0x1A;
        bytes[7] = 0x0A;

        var response = await endpoint.TranslateImageAsync(
            Principal(),
            new ImageTranslationHttpRequest(null, "French", Convert.ToBase64String(bytes), "image/png"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
        Assert.Null(service.ImageCommand);
    }

    [Fact]
    public async Task TranslateImageRejectsMimeTypeThatDoesNotMatchImageBytes()
    {
        var service = new StubPracticeLanguageToolService();
        var endpoint = new PracticeLanguageToolEndpoint(service);

        var response = await endpoint.TranslateImageAsync(
            Principal(),
            new ImageTranslationHttpRequest(null, "French", ValidPngBase64(), "image/jpeg"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(400, response.StatusCode);
        Assert.Equal("validation_error", response.Error?.Code);
        Assert.Null(service.ImageCommand);
    }

    [Fact]
    public async Task TranslateImageForwardsOnlyValidatedNormalizedImagePayload()
    {
        var service = new StubPracticeLanguageToolService();
        var endpoint = new PracticeLanguageToolEndpoint(service);

        var response = await endpoint.TranslateImageAsync(
            Principal(),
            new ImageTranslationHttpRequest(null, "French", ValidPngBase64(), "IMAGE/PNG"),
            "corr-123",
            CancellationToken.None);

        Assert.Equal(200, response.StatusCode);
        Assert.Equal(ValidPngBase64(), service.ImageCommand?.ImageBase64);
        Assert.Equal("image/png", service.ImageCommand?.MimeType);
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

    private static string ValidPngBase64()
    {
        return Convert.ToBase64String(new byte[]
        {
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x00,
        });
    }

    private sealed class StubPracticeLanguageToolService : IPracticeLanguageToolService
    {
        public AskAnythingCommand? AskCommand { get; private set; }
        public ImageTranslationCommand? ImageCommand { get; private set; }
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
            ImageCommand = command;
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
