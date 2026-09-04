using Voxa.Application.Ai;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class OpenAiModelRouterTests
{
    [Fact]
    public void ResolveUsesCapabilityDefaultAndReasoningEffort()
    {
        var router = OpenAiModelRouter.CreateDefault(_ => null);

        var route = router.Resolve(new ModelRouteRequest(
            AiCapability.RealtimeTutorModel,
            AiCallKind.RealtimeSession));

        Assert.Equal("gpt-realtime-2.1", route.Model);
        Assert.Equal("low", route.ReasoningEffort);
        Assert.Equal(ModelRouteSource.ConfigDefault, route.Source);
    }

    [Fact]
    public void ResolveAppliesAllowlistedEnvironmentOverride()
    {
        var router = OpenAiModelRouter.CreateDefault(name =>
            name == "VOXA_ROUTER_REALTIMETUTORMODEL" ? "gpt-realtime-2.1-mini" : null);

        var route = router.Resolve(new ModelRouteRequest(
            AiCapability.RealtimeTutorModel,
            AiCallKind.RealtimeSession));

        Assert.Equal("gpt-realtime-2.1-mini", route.Model);
        Assert.Equal("low", route.ReasoningEffort);
        Assert.Equal(ModelRouteSource.EnvironmentOverride, route.Source);
    }

    [Fact]
    public void ResolveReadsEnvironmentOverridesOnce()
    {
        var calls = 0;
        var router = OpenAiModelRouter.CreateDefault(name =>
        {
            calls++;
            return name == "VOXA_ROUTER_REALTIMETUTORMODEL" ? "gpt-realtime-2.1-mini" : null;
        });

        router.Resolve(new ModelRouteRequest(AiCapability.RealtimeTutorModel, AiCallKind.RealtimeSession));
        router.Resolve(new ModelRouteRequest(AiCapability.RealtimeTutorModel, AiCallKind.RealtimeSession));

        Assert.Equal(Enum.GetValues<AiCapability>().Length, calls);
    }

    [Fact]
    public void ResolveRejectsUnallowlistedEnvironmentOverride()
    {
        var router = OpenAiModelRouter.CreateDefault(name =>
            name == "VOXA_ROUTER_TUTORMODEL" ? "gpt-not-approved" : null);

        var exception = Assert.Throws<ModelRouteException>(() =>
            router.Resolve(new ModelRouteRequest(AiCapability.TutorModel, AiCallKind.Completion)));

        Assert.Contains("not allowlisted", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ResolveRejectsProductionPerCallOverrideWithoutReason()
    {
        var router = OpenAiModelRouter.CreateDefault(_ => null);

        var exception = Assert.Throws<ModelRouteException>(() =>
            router.Resolve(new ModelRouteRequest(
                AiCapability.TutorModel,
                AiCallKind.Completion,
                OverrideModel: "gpt-5.6-luna",
                OverrideReason: "",
                IsProduction: true)));

        Assert.Contains("override reason", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ResolveRejectsUnmappedSpeechGenerationDefault()
    {
        var router = OpenAiModelRouter.CreateDefault(_ => null);

        var exception = Assert.Throws<ModelRouteException>(() =>
            router.Resolve(new ModelRouteRequest(
                AiCapability.SpeechGenerationModel,
                AiCallKind.SpeechGeneration)));

        Assert.Contains("not configured", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ResolveAllowsSpeechGenerationOverrideWithoutReasoningEffort()
    {
        var router = OpenAiModelRouter.CreateDefault(_ => null);

        var route = router.Resolve(new ModelRouteRequest(
            AiCapability.SpeechGenerationModel,
            AiCallKind.SpeechGeneration,
            OverrideModel: "gpt-5.6-luna"));

        Assert.Equal("gpt-5.6-luna", route.Model);
        Assert.Null(route.ReasoningEffort);
    }

    [Fact]
    public void ResolveRejectsReasoningEffortForSpeechGeneration()
    {
        var router = OpenAiModelRouter.CreateDefault(_ => null);

        var exception = Assert.Throws<ModelRouteException>(() =>
            router.Resolve(new ModelRouteRequest(
                AiCapability.SpeechGenerationModel,
                AiCallKind.SpeechGeneration,
                OverrideModel: "gpt-5.6-luna",
                ReasoningEffortOverride: "low")));

        Assert.Contains("reasoning", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void DefaultConfigurationKeepsConfiguredModelsAllowlisted()
    {
        var configuration = ModelRouterConfiguration.LoadDefault();

        Assert.All(configuration.Models.Values, model =>
            Assert.Contains(model, configuration.AllowedModels));
    }
}
