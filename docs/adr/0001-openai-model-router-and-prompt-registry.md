# ADR-0001 — OpenAI Model Router and Prompt / Version Registry

- **Status:** Proposed
- **Date:** 2026-08-29
- **Deciders:** Simon (product); backend implementation to be executed by Codex
- **Consulted:** PRD §22 (AI Architecture)
- **Related:** [Model router and prompt registry spec](../specs/model-router-and-prompt-registry.md), issues [#31](https://github.com/simonholmes001/voxa/issues/31), [#14](https://github.com/simonholmes001/voxa/issues/14), [#36](https://github.com/simonholmes001/voxa/issues/36)

## Context

The PRD mandates that Voxa route different workloads to different OpenAI models, that model IDs remain remotely configurable, and that model selection be eval-driven rather than fixed. Without a single point of control:

- Model IDs would leak into feature code and require an iOS release to change.
- Cost telemetry and eval attribution would be per call site, not per capability.
- Prompt edits would silently change model outputs with no way to attribute regressions.
- The team would have no clean seam for offline testing or A/B experiments.

Two coupled concerns must be decided together, because a router without a prompt registry gains none of the traceability benefits:

1. **How the backend selects a model** for a given workload.
2. **How prompts are stored, versioned, and referenced** by that backend.

## Decision

Introduce an internal **AI Router** in the backend modular monolith that:

- Exposes the **logical capability enum** defined in the canonical table in the [model router spec §3](../specs/model-router-and-prompt-registry.md#3-logical-capabilities) — the spec's table is the single source of truth for the count and the mapping to PRD §22.3. `SpeechGenerationModel`'s default model resolution is deliberately deferred to a scoped follow-up per that section; the capability remains in the enum so call sites can plan against it.
- Resolves each capability to a concrete OpenAI model via a precedence chain (per-call override → env override → committed config → hard-coded fallback).
- Enforces a **model allowlist** and a **reasoning-effort default per capability**.
- Provides one entry point per call kind (`CompleteAsync`, `StreamAsync`, `IssueRealtimeSessionAsync`) — call sites never talk to the OpenAI SDK directly.
- Depends on an **`IOpenAiClient` seam** with `FakeOpenAiClient` and `RecordReplayOpenAiClient` implementations for offline testing.

And a colocated **Prompt Registry** in which:

- Every prompt is a YAML file under `backend/prompts/<domain>/<name>.v<n>.yaml`.
- Every prompt declares a `kind` — `completion` (default; carries `capability`, `system`, `user`, `tools`, `outputSchema`, `variables`) or `fragment` (carries `compatibleCapabilities`, `fragment`, `variables`; composed into another prompt's system block, never issued on its own). Both kinds carry `id`, `version`, and optional `guardrails` / `notes`.
- Committed versions are **immutable**; behavioral edits require bumping `version`.
- A build-time `router-index.json` records each version's `sha256` over its kind-appropriate behavioral fields; CI fails any behavioral drift on a committed version.
- Callers pass an explicit `(id, version)` `PromptRef` — the router does not resolve "latest".
- Every model call emits a `PromptTrace` with `promptId`, `promptVersion`, `promptHash`, `resolvedModel`, `reasoningEffort`, token counts, and outcome. Trace content (rendered prompt + output) is stored separately and gated on consent.

## Alternatives Considered

**A. Direct SDK calls with a shared `AppSettings.ModelId`.**
Cheapest to implement. Rejected: leaks model IDs everywhere; no per-capability tuning of reasoning effort; no traceability of prompt content; no A/B seam; no offline test path without call-site changes.

**B. Router with prompts held inline as string constants.**
Preserves capability abstraction. Rejected: prompt edits become invisible in diff review (a small string edit is easy to miss), hash-based immutability is impossible, and grepping the codebase for a prompt becomes lossy. Versioning would be by comment convention only.

**C. Router + prompts served from a remote config store (e.g., App Configuration).**
Enables prompt edits without redeploy. Rejected for MVP: adds a live dependency to the pedagogical hot path; the deploy pipeline already provides sufficient cadence; and prompt-file review is exactly the review the PRD asks for. Reconsider once eval maturity supports canary prompt rollouts.

**D. Router + prompts as OpenAI stored prompts (server-side by OpenAI).**
Similar to (C) with the same tradeoffs, plus vendor lock-in on prompt storage and diff/review. Rejected for MVP for the same reasons.

## Consequences

**Positive**
- Model changes ship without an iOS release; capability + prompt are the stable contract.
- Every prompt is a first-class, reviewable, hash-checked, versioned artifact.
- Regressions are attributable to a specific `(promptId, promptVersion, resolvedModel, reasoningEffort)` tuple via `PromptTrace`.
- Backend can run its full test suite without hitting OpenAI, keeping CI fast and offline-capable.
- A/B slot and kill switch give operational control without deploys for a defined class of change.

**Negative / cost**
- New call sites must go through the router; a lint or grep check keeps this honest but adds one line of policy to CODEOWNERS-adjacent guardrails.
- Prompt versioning discipline is now required — trivial "just tweak the wording" edits become PR-worthy events. This is the intended cost.
- The prompt hash rule may occasionally trip cosmetic changes if the canonical-YAML tool is misconfigured; owned by the router package.
- `PromptTrace` volume is O(model calls). Retention and sampling for high-volume utility capabilities are owned by the observability spec ([#36](https://github.com/simonholmes001/voxa/issues/36)).

**Neutral**
- Prompts live in the backend repo, not a shared package. If iOS ever needs to see prompt text (unlikely — PRD forbids client-side model calls), the registry would need an export.

## Compliance

- Aligned with PRD §22.1 (per-capability defaults), §22.3 (capability names + example config), §22.4 (eval-driven selection).
- Aligned with engineering guideline "OpenAI keys are server-side only" — router is the only OpenAI caller.
- Aligned with engineering guideline "No hardcoded Azure regions, IDs, or secrets" — extended in spirit to OpenAI model IDs: at runtime, model IDs exist only in `backend/config/router.defaults.json`, `backend/config/router.allowed-models.json`, and the router's own fallback constants file. Prompt files (`backend/prompts/**`) MUST NOT contain OpenAI model IDs in any field, including `notes:`. Design documents (this ADR, the spec, extracts of the PRD) may reference model IDs illustratively; the runtime rule is the enforced one. See the model router spec §10 for the CI grep check.

## Revisit Triggers

- If prompt-edit cadence outgrows the release cadence: reconsider (C).
- If the eval harness starts requiring live A/B on prompts: reconsider (C) with canary support.
- If a new capability is required that does not fit the canonical capability table in the model router spec §3: add via a follow-up ADR — do not stretch an existing capability.
