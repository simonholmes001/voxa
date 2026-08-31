namespace Voxa.Application.Ai;

public enum AiCapability
{
    RealtimeTutorModel,
    RealtimeTutorModelLite,
    TutorModel,
    CurriculumModel,
    AssessmentModel,
    UtilityModel,
    LiveTranscriptionModel,
    TranscriptionModel,
    SpeechGenerationModel
}

public enum AiCallKind
{
    Completion,
    RealtimeSession,
    Streaming,
    Transcription,
    SpeechGeneration
}

public enum ModelRouteSource
{
    PerCallOverride,
    EnvironmentOverride,
    ConfigDefault
}

public sealed record ModelRouteRequest(
    AiCapability Capability,
    AiCallKind Kind,
    string? OverrideModel = null,
    string? OverrideReason = null,
    string? ReasoningEffortOverride = null,
    bool IsProduction = false);

public sealed record ModelRoute(
    AiCapability Capability,
    string Model,
    string? ReasoningEffort,
    ModelRouteSource Source,
    string? OverrideReason);

public interface IModelRouter
{
    ModelRoute Resolve(ModelRouteRequest request);
}

public sealed class ModelRouteException(string message) : Exception(message);
