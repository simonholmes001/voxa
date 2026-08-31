using System.Reflection;
using System.Text.Json;
using Voxa.Application.Ai;

namespace Voxa.Infrastructure.OpenAI;

public sealed class OpenAiModelRouter(
    ModelRouterConfiguration configuration,
    IReadOnlyDictionary<AiCapability, string> environmentOverrides) : IModelRouter
{
    public static OpenAiModelRouter CreateDefault(Func<string, string?>? getEnvironmentVariable = null)
    {
        var readEnvironmentVariable = getEnvironmentVariable ?? Environment.GetEnvironmentVariable;
        return new OpenAiModelRouter(
            ModelRouterConfiguration.LoadDefault(),
            LoadEnvironmentOverrides(readEnvironmentVariable));
    }

    public ModelRoute Resolve(ModelRouteRequest request)
    {
        if (request.Capability == AiCapability.SpeechGenerationModel &&
            string.IsNullOrWhiteSpace(request.OverrideModel) &&
            string.IsNullOrWhiteSpace(EnvironmentOverrideFor(request.Capability)))
        {
            throw new ModelRouteException("SpeechGenerationModel is not configured for MVP.");
        }

        if (!string.IsNullOrWhiteSpace(request.OverrideModel))
        {
            if (request.IsProduction && string.IsNullOrWhiteSpace(request.OverrideReason))
            {
                throw new ModelRouteException("A production model override requires an override reason.");
            }

            EnsureAllowlisted(request.OverrideModel);
            return CreateRoute(request, request.OverrideModel, ModelRouteSource.PerCallOverride, request.OverrideReason);
        }

        var environmentOverride = EnvironmentOverrideFor(request.Capability);
        if (!string.IsNullOrWhiteSpace(environmentOverride))
        {
            EnsureAllowlisted(environmentOverride);
            return CreateRoute(request, environmentOverride, ModelRouteSource.EnvironmentOverride, null);
        }

        if (!configuration.Models.TryGetValue(request.Capability, out var configuredModel) ||
            string.IsNullOrWhiteSpace(configuredModel))
        {
            throw new ModelRouteException($"{request.Capability} is not configured.");
        }

        EnsureAllowlisted(configuredModel);
        return CreateRoute(request, configuredModel, ModelRouteSource.ConfigDefault, null);
    }

    private ModelRoute CreateRoute(
        ModelRouteRequest request,
        string model,
        ModelRouteSource source,
        string? overrideReason)
    {
        if (request.Capability == AiCapability.SpeechGenerationModel &&
            !string.IsNullOrWhiteSpace(request.ReasoningEffortOverride))
        {
            throw new ModelRouteException("Speech generation routes cannot set reasoning effort.");
        }

        var reasoningEffort = request.ReasoningEffortOverride;
        if (string.IsNullOrWhiteSpace(reasoningEffort))
        {
            configuration.ReasoningEfforts.TryGetValue(request.Capability, out reasoningEffort);
        }

        return new ModelRoute(request.Capability, model, reasoningEffort, source, overrideReason);
    }

    private string? EnvironmentOverrideFor(AiCapability capability)
    {
        return environmentOverrides.TryGetValue(capability, out var model) ? model : null;
    }

    private void EnsureAllowlisted(string model)
    {
        if (!configuration.AllowedModels.Contains(model))
        {
            throw new ModelRouteException($"Model '{model}' is not allowlisted.");
        }
    }

    private static IReadOnlyDictionary<AiCapability, string> LoadEnvironmentOverrides(
        Func<string, string?> getEnvironmentVariable)
    {
        var overrides = new Dictionary<AiCapability, string>();
        foreach (var capability in Enum.GetValues<AiCapability>())
        {
            var model = getEnvironmentVariable($"VOXA_ROUTER_{capability.ToString().ToUpperInvariant()}");
            if (!string.IsNullOrWhiteSpace(model))
            {
                overrides[capability] = model;
            }
        }

        return overrides;
    }
}

public sealed class ModelRouterConfiguration
{
    public ModelRouterConfiguration(
        IReadOnlyDictionary<AiCapability, string> models,
        IReadOnlyDictionary<AiCapability, string> reasoningEfforts,
        IReadOnlySet<string> allowedModels)
    {
        Models = models;
        ReasoningEfforts = reasoningEfforts;
        AllowedModels = allowedModels;
    }

    public IReadOnlyDictionary<AiCapability, string> Models { get; }

    public IReadOnlyDictionary<AiCapability, string> ReasoningEfforts { get; }

    public IReadOnlySet<string> AllowedModels { get; }

    public static ModelRouterConfiguration LoadDefault()
    {
        var assembly = typeof(ModelRouterConfiguration).Assembly;
        var defaults = ReadJson<RouterDefaultsFile>(assembly, "Voxa.Infrastructure.config.router.defaults.json");
        var allowed = ReadJson<RouterAllowedModelsFile>(assembly, "Voxa.Infrastructure.config.router.allowed-models.json");

        return new ModelRouterConfiguration(
            ParseCapabilityMap(defaults.Models),
            ParseCapabilityMap(defaults.ReasoningEfforts),
            allowed.Models.ToHashSet(StringComparer.Ordinal));
    }

    private static T ReadJson<T>(Assembly assembly, string resourceName)
    {
        using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new ModelRouteException($"Missing embedded router configuration resource '{resourceName}'.");
        return JsonSerializer.Deserialize<T>(stream, JsonSerializerOptions.Web)
            ?? throw new ModelRouteException($"Router configuration resource '{resourceName}' is invalid.");
    }

    private static IReadOnlyDictionary<AiCapability, string> ParseCapabilityMap(IReadOnlyDictionary<string, string> values)
    {
        var parsed = new Dictionary<AiCapability, string>();
        foreach (var (capabilityName, value) in values)
        {
            if (!Enum.TryParse<AiCapability>(capabilityName, out var capability))
            {
                throw new ModelRouteException($"Unknown AI capability '{capabilityName}'.");
            }

            parsed[capability] = value;
        }

        return parsed;
    }

    private sealed record RouterDefaultsFile(
        IReadOnlyDictionary<string, string> Models,
        IReadOnlyDictionary<string, string> ReasoningEfforts);

    private sealed record RouterAllowedModelsFile(IReadOnlyList<string> Models);
}
