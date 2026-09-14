using System.Net;
using System.Text;
using Microsoft.Extensions.Logging;
using Voxa.Application.Ai;
using Voxa.Application.Practice;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiPracticeLanguageToolServiceTests
{
    [Fact]
    public async Task AskAnythingWrapsTransportFailureAsPracticeLanguageToolException()
    {
        var service = CreateService(new ThrowingHttpMessageHandler(new HttpRequestException("network down")));

        await Assert.ThrowsAsync<PracticeLanguageToolException>(
            () => service.AskAnythingAsync(SampleAskCommand(), CancellationToken.None));
    }

    [Fact]
    public async Task AskAnythingWrapsClientTimeoutAsPracticeLanguageToolException()
    {
        var service = CreateService(new ThrowingHttpMessageHandler(new TaskCanceledException("client timeout")));

        await Assert.ThrowsAsync<PracticeLanguageToolException>(
            () => service.AskAnythingAsync(SampleAskCommand(), CancellationToken.None));
    }

    [Fact]
    public async Task AskAnythingPreservesCallerCancellation()
    {
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();
        var service = CreateService(new CancellationAwareHttpMessageHandler());

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => service.AskAnythingAsync(SampleAskCommand(), cancellation.Token));
    }

    [Fact]
    public async Task AskAnythingWrapsMalformedOpenAiEnvelopeAsPracticeLanguageToolException()
    {
        var service = CreateService(new RecordingHttpMessageHandler("not-json"));

        await Assert.ThrowsAsync<PracticeLanguageToolException>(
            () => service.AskAnythingAsync(SampleAskCommand(), CancellationToken.None));
    }

    [Fact]
    public async Task UpstreamFailureLogsStatusAndCorrelationIdWithoutRawBody()
    {
        var logger = new CapturingLogger<OpenAiPracticeLanguageToolService>();
        var service = CreateService(
            new RecordingHttpMessageHandler("sensitive learner phrase", HttpStatusCode.TooManyRequests),
            logger);

        await Assert.ThrowsAsync<PracticeLanguageToolException>(
            () => service.AskAnythingAsync(SampleAskCommand(), CancellationToken.None));

        var entry = Assert.Single(logger.Entries);
        Assert.Contains("status=429", entry.Message, StringComparison.Ordinal);
        Assert.Contains("model=gpt-test", entry.Message, StringComparison.Ordinal);
        Assert.Contains("correlationId=corr-practice", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("sensitive learner phrase", entry.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task InvalidModelJsonLogsCorrelationIdWithoutRawModelOutput()
    {
        var logger = new CapturingLogger<OpenAiPracticeLanguageToolService>();
        var service = CreateService(
            new RecordingHttpMessageHandler("""{"output_text":"sensitive translated learner text"}"""),
            logger);

        await Assert.ThrowsAsync<PracticeLanguageToolException>(
            () => service.AskAnythingAsync(SampleAskCommand(), CancellationToken.None));

        var entry = Assert.Single(logger.Entries);
        Assert.Contains("model=gpt-test", entry.Message, StringComparison.Ordinal);
        Assert.Contains("correlationId=corr-practice", entry.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("sensitive translated learner text", entry.Message, StringComparison.Ordinal);
    }

    private static OpenAiPracticeLanguageToolService CreateService(
        HttpMessageHandler handler,
        ILogger<OpenAiPracticeLanguageToolService>? logger = null)
    {
        return new OpenAiPracticeLanguageToolService(
            new HttpClient(handler) { BaseAddress = new Uri("https://api.openai.example/") },
            new OpenAiRealtimeOptions("server-api-key"),
            new StubModelRouter(new ModelRoute(
                AiCapability.UtilityModel,
                "gpt-test",
                "minimal",
                ModelRouteSource.ConfigDefault,
                null)),
            logger ?? new CapturingLogger<OpenAiPracticeLanguageToolService>());
    }

    private static AskAnythingCommand SampleAskCommand()
    {
        return new AskAnythingCommand(
            "French",
            "English",
            "How do I say something private?",
            CorrelationId.Create("corr-practice"));
    }

    private sealed class RecordingHttpMessageHandler(
        string responseBody,
        HttpStatusCode statusCode = HttpStatusCode.OK) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json"),
            });
        }
    }

    private sealed class ThrowingHttpMessageHandler(Exception exception) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            return Task.FromException<HttpResponseMessage>(exception);
        }
    }

    private sealed class CancellationAwareHttpMessageHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
        }
    }

    private sealed class StubModelRouter(ModelRoute route) : IModelRouter
    {
        public ModelRoute Resolve(ModelRouteRequest request) => route;
    }

    private sealed class CapturingLogger<T> : ILogger<T>
    {
        public List<LogEntry> Entries { get; } = [];

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Entries.Add(new LogEntry(logLevel, eventId, formatter(state, exception)));
        }
    }

    private sealed record LogEntry(LogLevel Level, EventId EventId, string Message);
}
