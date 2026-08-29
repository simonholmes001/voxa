namespace Voxa.Api.Http;

public sealed record ApiResponse<T>(
    int StatusCode,
    T? Body,
    ApiErrorResponse? Error)
{
    public static ApiResponse<T> Ok(T body) => new(200, body, null);

    public static ApiResponse<T> Failure(int statusCode, ApiErrorResponse error) => new(statusCode, default, error);
}

public sealed record ApiErrorResponse(
    string Code,
    string Message,
    string CorrelationId,
    bool Retryable);
