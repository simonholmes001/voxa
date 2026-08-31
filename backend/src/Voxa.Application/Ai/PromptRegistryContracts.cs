namespace Voxa.Application.Ai;

public enum PromptKind
{
    Completion,
    Fragment
}

public sealed record PromptRef(string Id, int Version);

public sealed record PromptVariable(string Name, bool Required);

public sealed record RegisteredPrompt(
    PromptRef Ref,
    PromptKind Kind,
    AiCapability? Capability,
    IReadOnlyList<AiCapability> CompatibleCapabilities,
    IReadOnlyList<PromptVariable> Variables,
    string Hash);

public sealed record RenderedPrompt(
    PromptRef Ref,
    PromptKind Kind,
    AiCapability? Capability,
    string? System,
    string? User,
    string Hash);

public interface IPromptRegistry
{
    RegisteredPrompt Get(PromptRef promptRef);

    RenderedPrompt Render(PromptRef promptRef, IReadOnlyDictionary<string, string> variables);
}

public sealed class PromptRegistryException(string message) : Exception(message);
