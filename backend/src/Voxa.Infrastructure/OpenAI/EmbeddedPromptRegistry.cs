using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Voxa.Application.Ai;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace Voxa.Infrastructure.OpenAI;

public sealed partial class EmbeddedPromptRegistry : IPromptRegistry
{
    private readonly IReadOnlyDictionary<PromptRef, PromptFile> prompts;

    private EmbeddedPromptRegistry(IReadOnlyDictionary<PromptRef, PromptFile> prompts)
    {
        this.prompts = prompts;
    }

    public static EmbeddedPromptRegistry CreateDefault()
    {
        var assembly = typeof(EmbeddedPromptRegistry).Assembly;
        var documents = assembly
            .GetManifestResourceNames()
            .Where(name => name.Contains(".prompts.", StringComparison.Ordinal) &&
                           name.EndsWith(".yaml", StringComparison.Ordinal))
            .Select(name =>
            {
                using var stream = assembly.GetManifestResourceStream(name)
                    ?? throw new PromptRegistryException($"Missing embedded prompt resource '{name}'.");
                using var reader = new StreamReader(stream);
                return reader.ReadToEnd();
            })
            .ToArray();

        return FromYamlDocuments(documents);
    }

    public static EmbeddedPromptRegistry FromYamlDocuments(IReadOnlyList<string> yamlDocuments)
    {
        var deserializer = new DeserializerBuilder()
            .WithNamingConvention(CamelCaseNamingConvention.Instance)
            .IgnoreUnmatchedProperties()
            .Build();
        var parsed = new Dictionary<PromptRef, PromptFile>();

        foreach (var document in yamlDocuments)
        {
            var prompt = deserializer.Deserialize<PromptFile>(document)
                ?? throw new PromptRegistryException("Prompt document is empty.");
            prompt.Normalize();
            prompt.Hash = ComputeHash(prompt);
            var promptRef = prompt.ToRef();
            if (!parsed.TryAdd(promptRef, prompt))
            {
                throw new PromptRegistryException($"Duplicate prompt '{prompt.Id}' version {prompt.Version}.");
            }
        }

        return new EmbeddedPromptRegistry(parsed);
    }

    public RegisteredPrompt Get(PromptRef promptRef)
    {
        var prompt = Find(promptRef);
        return prompt.ToRegisteredPrompt();
    }

    public RenderedPrompt Render(PromptRef promptRef, IReadOnlyDictionary<string, string> variables)
    {
        var prompt = Find(promptRef);
        if (prompt.Kind != "completion")
        {
            throw new PromptRegistryException($"Prompt '{promptRef.Id}' version {promptRef.Version} is a fragment.");
        }

        var system = RenderTemplate(prompt.System ?? "", prompt, variables);
        foreach (var fragmentRef in prompt.Fragments)
        {
            var fragment = Find(new PromptRef(fragmentRef.Id, fragmentRef.Version));
            if (fragment.Kind != "fragment")
            {
                throw new PromptRegistryException($"Prompt '{fragmentRef.Id}' version {fragmentRef.Version} is not a fragment.");
            }

            var capability = prompt.ParseCapability();
            var compatibleCapabilities = fragment.ParseCompatibleCapabilities();
            if (!compatibleCapabilities.Contains(capability))
            {
                throw new PromptRegistryException(
                    $"Fragment '{fragment.Id}' is not compatible with capability '{capability}'.");
            }

            EnsureFragmentVariablesAreDeclaredByPrompt(prompt, fragment, fragmentRef);
            var mappedVariables = MapFragmentVariables(fragment, fragmentRef, variables);
            var renderedFragment = RenderTemplate(fragment.Fragment ?? "", fragment, mappedVariables);
            system = string.IsNullOrWhiteSpace(system)
                ? renderedFragment
                : $"{system.TrimEnd()}{Environment.NewLine}{Environment.NewLine}{renderedFragment}";
        }

        return new RenderedPrompt(
            prompt.ToRef(),
            PromptKind.Completion,
            prompt.ParseCapability(),
            system,
            RenderTemplate(prompt.User ?? "", prompt, variables),
            prompt.Hash);
    }

    private PromptFile Find(PromptRef promptRef)
    {
        if (!prompts.TryGetValue(promptRef, out var prompt))
        {
            throw new PromptRegistryException($"Prompt '{promptRef.Id}' version {promptRef.Version} was not found.");
        }

        return prompt;
    }

    private static void EnsureFragmentVariablesAreDeclaredByPrompt(
        PromptFile prompt,
        PromptFile fragment,
        PromptFragmentRef fragmentRef)
    {
        var declaredPromptVariables = prompt.Variables
            .Select(variable => variable.Name)
            .ToHashSet(StringComparer.Ordinal);
        foreach (var requiredVariable in fragment.Variables.Where(variable => variable.Required))
        {
            var promptVariableName = fragmentRef.VariableMap.TryGetValue(requiredVariable.Name, out var mappedName)
                ? mappedName
                : requiredVariable.Name;
            if (!declaredPromptVariables.Contains(promptVariableName))
            {
                throw new PromptRegistryException(
                    $"Prompt '{prompt.Id}' does not declare required fragment variable '{promptVariableName}'.");
            }
        }
    }

    private static IReadOnlyDictionary<string, string> MapFragmentVariables(
        PromptFile fragment,
        PromptFragmentRef fragmentRef,
        IReadOnlyDictionary<string, string> variables)
    {
        if (fragmentRef.VariableMap.Count == 0)
        {
            return variables;
        }

        var mapped = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var variable in fragment.Variables)
        {
            var sourceName = fragmentRef.VariableMap.TryGetValue(variable.Name, out var mappedName)
                ? mappedName
                : variable.Name;
            if (variables.TryGetValue(sourceName, out var value))
            {
                mapped[variable.Name] = value;
            }
        }

        return mapped;
    }

    private static string RenderTemplate(
        string template,
        PromptFile prompt,
        IReadOnlyDictionary<string, string> variables)
    {
        var declaredVariables = prompt.Variables
            .Select(variable => variable.Name)
            .ToHashSet(StringComparer.Ordinal);
        foreach (Match match in TemplateTokenRegex().Matches(template))
        {
            var variableName = match.Groups[1].Value;
            if (!declaredVariables.Contains(variableName))
            {
                throw new PromptRegistryException(
                    $"Prompt '{prompt.Id}' template uses undeclared variable '{variableName}'.");
            }
        }

        foreach (var variable in prompt.Variables.Where(variable => variable.Required))
        {
            if (!variables.TryGetValue(variable.Name, out var value) || string.IsNullOrWhiteSpace(value))
            {
                throw new PromptRegistryException(
                    $"Prompt '{prompt.Id}' is missing required variable '{variable.Name}'.");
            }
        }

        return TemplateTokenRegex().Replace(template, match =>
        {
            var variableName = match.Groups[1].Value;
            return variables.TryGetValue(variableName, out var value) ? value : "";
        });
    }

    private static string ComputeHash(PromptFile prompt)
    {
        var behavioralFields = new
        {
            prompt.Kind,
            prompt.Capability,
            prompt.CompatibleCapabilities,
            prompt.Fragment,
            prompt.System,
            prompt.User,
            prompt.Tools,
            prompt.OutputSchema,
            prompt.Variables,
            prompt.Fragments
        };
        var json = JsonSerializer.Serialize(behavioralFields, JsonSerializerOptions.Web);
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(json))).ToLowerInvariant();
    }

    [GeneratedRegex(@"\{\{\s*([A-Za-z0-9_]+)\s*\}\}", RegexOptions.CultureInvariant)]
    private static partial Regex TemplateTokenRegex();

    public sealed class PromptFile
    {
        public string Kind { get; set; } = "completion";

        public string Id { get; set; } = "";

        public int Version { get; set; }

        public string? Capability { get; set; }

        public List<string> CompatibleCapabilities { get; set; } = [];

        public List<PromptVariableFile> Variables { get; set; } = [];

        public List<PromptFragmentRef> Fragments { get; set; } = [];

        public object? OutputSchema { get; set; }

        public object? Tools { get; set; }

        public string? System { get; set; }

        public string? User { get; set; }

        public string? Fragment { get; set; }

        public string Hash { get; set; } = "";

        public void Normalize()
        {
            Kind = string.IsNullOrWhiteSpace(Kind) ? "completion" : Kind;
            if (Id.Length == 0 || Version < 1)
            {
                throw new PromptRegistryException("Prompt id and positive version are required.");
            }

            ParseKind();

            if (Kind == "completion" && string.IsNullOrWhiteSpace(Capability))
            {
                throw new PromptRegistryException($"Completion prompt '{Id}' requires a capability.");
            }

            if (Kind == "fragment" && CompatibleCapabilities.Count == 0)
            {
                throw new PromptRegistryException($"Fragment prompt '{Id}' requires compatible capabilities.");
            }

            var duplicateVariable = Variables
                .GroupBy(variable => variable.Name, StringComparer.Ordinal)
                .FirstOrDefault(group => group.Key.Length == 0 || group.Count() > 1);
            if (duplicateVariable is not null)
            {
                throw new PromptRegistryException($"Prompt '{Id}' has an invalid or duplicate variable declaration.");
            }
        }

        public PromptRef ToRef()
        {
            return new PromptRef(Id, Version);
        }

        public RegisteredPrompt ToRegisteredPrompt()
        {
            return new RegisteredPrompt(
                ToRef(),
                ParseKind(),
                Kind == "completion" ? ParseCapability() : null,
                ParseCompatibleCapabilities(),
                Variables.Select(variable => new PromptVariable(variable.Name, variable.Required)).ToArray(),
                Hash);
        }

        public PromptKind ParseKind()
        {
            return Kind switch
            {
                "completion" => PromptKind.Completion,
                "fragment" => PromptKind.Fragment,
                _ => throw new PromptRegistryException($"Prompt '{Id}' has unsupported kind '{Kind}'.")
            };
        }

        public AiCapability ParseCapability()
        {
            if (!Enum.TryParse<AiCapability>(Capability, out var capability))
            {
                throw new PromptRegistryException($"Prompt '{Id}' has unsupported capability '{Capability}'.");
            }

            return capability;
        }

        public IReadOnlyList<AiCapability> ParseCompatibleCapabilities()
        {
            return CompatibleCapabilities
                .Select(capabilityName =>
                {
                    if (!Enum.TryParse<AiCapability>(capabilityName, out var capability))
                    {
                        throw new PromptRegistryException(
                            $"Prompt '{Id}' has unsupported compatible capability '{capabilityName}'.");
                    }

                    return capability;
                })
                .ToArray();
        }
    }

    public sealed class PromptVariableFile
    {
        public string Name { get; set; } = "";

        public bool Required { get; set; }
    }

    public sealed class PromptFragmentRef
    {
        public string Id { get; set; } = "";

        public int Version { get; set; }

        public Dictionary<string, string> VariableMap { get; set; } =
            new Dictionary<string, string>(StringComparer.Ordinal);
    }
}
