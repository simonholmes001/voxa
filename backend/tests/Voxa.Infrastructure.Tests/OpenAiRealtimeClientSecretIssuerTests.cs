using System.Net;
using System.Text;
using Voxa.Application.Realtime;
using Voxa.Domain.Learners;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiRealtimeClientSecretIssuerTests
{
    [Fact]
    public async Task IssueAsyncSendsServerApiKeyOnlyInAuthorizationHeader()
    {
        var handler = new RecordingHttpMessageHandler("""
            {
              "client_secret": {
                "value": "client-secret-123",
                "expires_at": 1787991600
              },
              "session": {
                "model": "gpt-realtime-2.1"
              }
            }
            """);
        var client = new HttpClient(handler)
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key", "gpt-realtime-2.1", "low"));

        var credential = await issuer.IssueAsync(CreateRequest(), CancellationToken.None);

        Assert.Equal("client-secret-123", credential.ClientSecret);
        Assert.Equal("Bearer server-api-key", handler.Request?.Headers.Authorization?.ToString());
        Assert.DoesNotContain("server-api-key", handler.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("tenant-default", handler.Body, StringComparison.Ordinal);
        Assert.DoesNotContain("user-a", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"session\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("\"type\":\"realtime\"", handler.Body, StringComparison.Ordinal);
        Assert.Contains("gpt-realtime-2.1", handler.Body, StringComparison.Ordinal);
        Assert.Contains("fr-FR", handler.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task IssueAsyncMapsUpstreamFailureToRealtimeSessionIssueException()
    {
        var client = new HttpClient(new RecordingHttpMessageHandler("{}", HttpStatusCode.TooManyRequests))
        {
            BaseAddress = new Uri("https://api.openai.example/")
        };
        var issuer = new OpenAiRealtimeClientSecretIssuer(
            client,
            new OpenAiRealtimeOptions("server-api-key", "gpt-realtime-2.1", "low"));

        await Assert.ThrowsAsync<RealtimeSessionIssueException>(() =>
            issuer.IssueAsync(CreateRequest(), CancellationToken.None));
    }

    private static RealtimeSessionRequest CreateRequest()
    {
        return new RealtimeSessionRequest(
            TenantId.Create("tenant-default"),
            UserId.Create("user-a"),
            CorrelationId.Create("corr-123"),
            new RealtimeSessionSettingsContract("tutor", "B1-B2", "fr-FR"));
    }

    private sealed class RecordingHttpMessageHandler(
        string responseBody,
        HttpStatusCode statusCode = HttpStatusCode.OK) : HttpMessageHandler
    {
        public HttpRequestMessage? Request { get; private set; }

        public string Body { get; private set; } = "";

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Request = request;
            Body = request.Content is null
                ? ""
                : await request.Content.ReadAsStringAsync(cancellationToken);

            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json")
            };
        }
    }
}
