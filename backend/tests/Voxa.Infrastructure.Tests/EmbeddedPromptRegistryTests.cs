using Voxa.Application.Ai;
using Voxa.Infrastructure.OpenAI;

namespace Voxa.Infrastructure.Tests;

public sealed class EmbeddedPromptRegistryTests
{
    [Fact]
    public void GetReturnsPromptByExplicitIdAndVersion()
    {
        var registry = EmbeddedPromptRegistry.CreateDefault();

        var prompt = registry.Get(new PromptRef("onboarding/placement-conversation", 1));

        Assert.Equal("onboarding/placement-conversation", prompt.Ref.Id);
        Assert.Equal(1, prompt.Ref.Version);
        Assert.Equal(PromptKind.Completion, prompt.Kind);
        Assert.Equal(AiCapability.TutorModel, prompt.Capability);
        Assert.NotEmpty(prompt.Hash);
    }

    [Fact]
    public void GetRejectsUnknownPromptVersion()
    {
        var registry = EmbeddedPromptRegistry.CreateDefault();

        var exception = Assert.Throws<PromptRegistryException>(() =>
            registry.Get(new PromptRef("onboarding/placement-conversation", 2)));

        Assert.Contains("not found", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void RenderRequiresEveryDeclaredVariableUsedByTemplate()
    {
        var registry = EmbeddedPromptRegistry.CreateDefault();

        var exception = Assert.Throws<PromptRegistryException>(() =>
            registry.Render(
                new PromptRef("onboarding/placement-conversation", 1),
                new Dictionary<string, string>
                {
                    ["targetLanguage"] = "French",
                    ["nativeLanguage"] = "English",
                    ["selfReportedLevel"] = "B1",
                    ["currentEstimatedLevel"] = "B1"
                }));

        Assert.Contains("recentTurns", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RenderRejectsTemplateTokenWithoutVariableDeclaration()
    {
        var prompt = """
            kind: completion
            id: test/bad-token
            version: 1
            capability: TutorModel
            variables:
              - name: declared
                required: true
            system: "{{undeclared}}"
            user: "{{declared}}"
            """;
        var registry = EmbeddedPromptRegistry.FromYamlDocuments([prompt]);

        var exception = Assert.Throws<PromptRegistryException>(() =>
            registry.Render(new PromptRef("test/bad-token", 1), new Dictionary<string, string>
            {
                ["declared"] = "value"
            }));

        Assert.Contains("undeclared", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void RenderComposesCompatibleFragmentIntoCompletionSystemPrompt()
    {
        var registry = EmbeddedPromptRegistry.FromYamlDocuments(
        [
            """
            kind: fragment
            id: correction/mode-fragment.tutor
            version: 1
            compatibleCapabilities:
              - RealtimeTutorModel
            variables:
              - name: proficiencyBand
                required: true
            fragment: "Tutor policy for {{proficiencyBand}}"
            """,
            """
            kind: completion
            id: correction/live-recast
            version: 1
            capability: RealtimeTutorModel
            variables:
              - name: proficiencyBand
                required: true
            fragments:
              - id: correction/mode-fragment.tutor
                version: 1
            system: "Realtime prompt"
            user: "Learner turn"
            """
        ]);

        var rendered = registry.Render(new PromptRef("correction/live-recast", 1), new Dictionary<string, string>
        {
            ["proficiencyBand"] = "B1-B2"
        });

        Assert.Contains("Realtime prompt", rendered.System, StringComparison.Ordinal);
        Assert.Contains("Tutor policy for B1-B2", rendered.System, StringComparison.Ordinal);
    }

    [Fact]
    public void RenderRejectsFragmentWithIncompatibleCapability()
    {
        var registry = EmbeddedPromptRegistry.FromYamlDocuments(
        [
            """
            kind: fragment
            id: correction/mode-fragment.tutor
            version: 1
            compatibleCapabilities:
              - TutorModel
            variables: []
            fragment: "Tutor policy"
            """,
            """
            kind: completion
            id: correction/live-recast
            version: 1
            capability: RealtimeTutorModel
            variables: []
            fragments:
              - id: correction/mode-fragment.tutor
                version: 1
            system: "Realtime prompt"
            user: "Learner turn"
            """
        ]);

        var exception = Assert.Throws<PromptRegistryException>(() =>
            registry.Render(new PromptRef("correction/live-recast", 1), new Dictionary<string, string>()));

        Assert.Contains("compatible", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void RenderRejectsRequiredFragmentVariableNotDeclaredByCompletionPrompt()
    {
        var registry = EmbeddedPromptRegistry.FromYamlDocuments(
        [
            """
            kind: fragment
            id: correction/mode-fragment.tutor
            version: 1
            compatibleCapabilities:
              - RealtimeTutorModel
            variables:
              - name: proficiencyBand
                required: true
            fragment: "Tutor policy for {{proficiencyBand}}"
            """,
            """
            kind: completion
            id: correction/live-recast
            version: 1
            capability: RealtimeTutorModel
            variables: []
            fragments:
              - id: correction/mode-fragment.tutor
                version: 1
            system: "Realtime prompt"
            user: "Learner turn"
            """
        ]);

        var exception = Assert.Throws<PromptRegistryException>(() =>
            registry.Render(new PromptRef("correction/live-recast", 1), new Dictionary<string, string>
            {
                ["proficiencyBand"] = "B1-B2"
            }));

        Assert.Contains("proficiencyBand", exception.Message, StringComparison.Ordinal);
    }
}
