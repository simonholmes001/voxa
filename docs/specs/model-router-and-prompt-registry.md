# Model Router and Prompt / Version Registry — Design Spec

**Status:** Draft (for backend implementation)
**Issue:** [#31 Implement OpenAI model router and prompt/version registry](https://github.com/simonholmes001/voxa/issues/31)
**Source of truth:** PRD §22 (AI Architecture) — routing table, capability enum, JSON config example, eval-driven selection
**Related specs:** [Onboarding and placement](./onboarding-and-placement.md), [Correction and explanation policy](./correction-and-explanation-policy.md)
**Related ADR:** [ADR-0001 OpenAI Model Router and Prompt Registry](../adr/0001-openai-model-router-and-prompt-registry.md)

## 1. Purpose

Centralize OpenAI model selection, prompt content, prompt versioning, reasoning effort, and per-task routing so that:

- Application code requests **logical capabilities**, never concrete model IDs (PRD §22.3).
- Model choice is remotely configurable (PRD §22 — model changes must not require an iOS release).
- Every generated output is traceable to the exact prompt content and model that produced it.
- The router is fully testable without hitting the OpenAI API.

## 2. Scope

**In scope**
- The logical-capability enum and its default mapping to OpenAI model IDs.
- Router API surface (request shape, response shape, error semantics).
- Reasoning-effort defaults and per-call overrides.
- Prompt registry: file layout, YAML schema, immutability rule, versioning rule, hashing.
- Output logging (`PromptTrace`).
- Test doubles for offline testing.
- Rollout controls: default source, override precedence, A/B slot.

**Non-goals**
- The Azure Functions plumbing itself — the router lives inside the backend modular monolith ([#33](https://github.com/simonholmes001/voxa/issues/33)).
- Realtime session lifecycle (client-secret issuance in [#18](https://github.com/simonholmes001/voxa/issues/18)); this spec defines only how the Realtime capability + session config are chosen.
- Cost telemetry dashboards — informed by `PromptTrace`, owned by [#36 Observability](https://github.com/simonholmes001/voxa/issues/36).

## 3. Logical Capabilities

Canonical enum, matching PRD §22.3 verbatim:

| Capability | Purpose | Default model (initial) |
|---|---|---|
| `RealtimeTutorModel` | Live speech-to-speech tutoring | `gpt-realtime-2.1` |
| `RealtimeTutorModelLite` | Cost-optimized live tutoring (evals-gated) | `gpt-realtime-2.1-mini` |
| `TutorModel` | Async pedagogical operations — explanations, debrief, exercise gen | `gpt-5.6-terra` |
| `CurriculumModel` | Long-horizon curriculum / plan synthesis | `gpt-5.6-sol` |
| `AssessmentModel` | Grading, level estimation, correction classification | `gpt-5.6-sol` |
| `UtilityModel` | Bounded high-volume utility tasks (evals-gated) | `gpt-5.6-luna` |
| `LiveTranscriptionModel` | Streaming transcript deltas outside a Realtime tutor session | `gpt-live-transcribe` |
| `TranscriptionModel` | Bounded / file transcription | `gpt-transcribe` |
| `SpeechGenerationModel` | Standalone generated audio outside Realtime | (see PRD §22, TBD by eval) |

Capabilities are additive-only. Removing a capability is a breaking change and requires a deprecation window plus explicit call-site migration.

## 4. Configuration

### 4.1 Precedence (highest wins)

1. **Per-call override** — a call may pass `overrideModel: "gpt-5.6-terra"` for a spike or an eval run. Emits a `PromptTrace.overrideReason` field; refused in production without the reason.
2. **Environment override** — `VOXA_ROUTER_<CAPABILITY>=gpt-…` env var. Read once at process start; validated against the known-model allowlist.
3. **Config file** — committed defaults in `backend/config/router.defaults.json` mirroring the PRD example (§22.3).
4. **Hard-coded fallback** — matches the PRD defaults; used only if the config file cannot be parsed. Emits a warning on startup.

### 4.2 Reasoning effort defaults

Per PRD §22.1: Realtime 2.1 begins at **low** reasoning effort; the router exposes a per-capability default plus a per-call override:

```jsonc
{
  "reasoningEffortDefaults": {
    "RealtimeTutorModel":     "low",
    "RealtimeTutorModelLite": "low",
    "TutorModel":             "medium",
    "CurriculumModel":        "high",
    "AssessmentModel":        "high",
    "UtilityModel":           "low",
    "LiveTranscriptionModel": "low",
    "TranscriptionModel":     "low"
  }
}
```

Increasing reasoning effort at a call site MUST be justified with an eval win recorded in the PR that changes it.

### 4.3 A/B slot

Each capability has one optional `experimentModel` that receives a configurable fraction of traffic (`experimentTrafficRatio`, 0.0–1.0, default 0.0). Sampling is deterministic per `(capability, learnerId)` so a learner sees a consistent model within a session. Experiment allocation is recorded on `PromptTrace`.

### 4.4 Allowlist

The router refuses any model id not in `backend/config/router.allowed-models.json`. Adding a model to the allowlist is a PR that must reference an eval or the PRD update permitting it.

## 5. Router API (backend-internal)

Callers request a capability and a prompt id; the router loads the prompt, resolves the model, calls OpenAI (or its test double), and writes a `PromptTrace`.

Sketch (language-agnostic; final signature owned by Codex during backend implementation):

```csharp
public interface IAiRouter
{
    // Non-streaming completion.
    Task<AiCompletion> CompleteAsync(
        AiCapability capability,
        PromptRef prompt,                        // (id, version) — must resolve exactly
        IReadOnlyDictionary<string, object> variables,
        AiCallOptions? options = null,           // reasoningEffort, overrideModel+reason, etc.
        CancellationToken ct = default);

    // Streaming completion (SSE / delta chunks).
    IAsyncEnumerable<AiChunk> StreamAsync(...);

    // Realtime client-secret minting — thin wrapper over OpenAI /v1/realtime/client_secrets
    // so session-config (mode, model, reasoning) is centralized here.
    Task<RealtimeClientSecret> IssueRealtimeSessionAsync(
        RealtimeSessionRequest request,
        CancellationToken ct = default);
}
```

**Errors**
- `RouterConfigurationException` — capability unmapped, model not allowlisted, config unparseable.
- `PromptNotFoundException` — no prompt at `(id, version)`.
- `UpstreamRateLimitException` / `UpstreamTransientException` — retryable per capability policy (defaults: 3 attempts, exponential jitter, no retry on 4xx except 429).
- `UpstreamContentPolicyException` — non-retryable; surfaced to caller with redacted upstream message.

## 6. Prompt Registry

### 6.1 File layout

Prompts live in-repo under `backend/prompts/` (mirrored by developer-facing docs at `docs/prompts/` — the doc tree is the reviewable design surface; the backend copies committed at build time are the runtime source).

```
backend/prompts/
├── router-index.json          # generated at build; maps (id, version) → file + hash
├── correction/
│   ├── classify.v1.yaml
│   ├── classify.v2.yaml
│   ├── debrief.v1.yaml
│   └── live-recast.v1.yaml
├── onboarding/
│   ├── placement-conversation.v1.yaml
│   ├── placement-grade.v1.yaml
│   └── first-plan-synthesis.v1.yaml
└── …
```

### 6.2 Prompt file schema

Each `.yaml` is a single document. Every prompt file declares a `kind` — one of `completion` (the default; a prompt that produces a model completion) or `fragment` (a prompt-shaped snippet that is concatenated into another prompt's `system` block rather than issued to a model on its own). The required behavioral fields differ per kind; see §6.4 for the corresponding hash inputs.

#### `kind: completion`

```yaml
kind: completion                     # default; may be omitted
id: correction/classify              # stable, kebab, hierarchical
version: 1                           # integer, monotonically increasing per id
capability: AssessmentModel          # from §3
description: >
  Classifies a learner utterance in a conversation context and returns
  structured corrections with severity and class per correction policy §3.
variables:                           # variables the caller MUST supply
  - name: learnerUtterance
    required: true
  - name: conversationContext
    required: true
  - name: coachingMode
    required: true
  - name: proficiencyBand
    required: true
outputSchema:                        # JSON schema the model output MUST validate against
  $ref: ../schemas/correction.classification.v1.json
system: |
  You are Voxa's correction classifier. …
user: |
  ## Learner utterance
  {{learnerUtterance}}

  ## Recent conversation
  {{conversationContext}}

  ## Mode / band
  {{coachingMode}} / {{proficiencyBand}}
tools: []                            # optional; declares any tool calls
guardrails:
  refusesTopics: []                  # optional
  redactionRequired: [prompts, freeText]
notes: >
  See docs/specs/correction-and-explanation-policy.md §3–4.
```

#### `kind: fragment`

Fragments carry policy text that is composed into a governing prompt at render time; they never produce a completion on their own. `system`, `user`, `outputSchema`, and `tools` are therefore absent — only `fragment` and `variables` are meaningful. The router refuses to issue a completion from a fragment file, and refuses to render a governing prompt whose composed fragments do not all resolve.

```yaml
kind: fragment
id: correction/mode-fragment.tutor
version: 1
capability: TutorModel               # the capability of the governing prompt this fragment composes into
description: >
  Tutor-mode behavior policy composed into the correction/live-recast and
  correction/debrief prompts. Encodes the correction policy §4.1/§4.2/§4.3
  matrix cells for Tutor mode.
variables:
  - name: proficiencyBand
    required: true
  - name: interruptBudgetRemaining
    required: true
  - name: recentCorrections
    required: true
  - name: recurringSkillIds
    required: false
fragment: |
  ## Coaching mode: Tutor ({{proficiencyBand}})

  You are actively correcting and teaching. Balance conversational flow
  against learning opportunities. …
guardrails: {}
notes: >
  See docs/specs/correction-and-explanation-policy.md §4 and §5.
```

### 6.3 Immutability rule

**A committed prompt version is immutable.** Any change to a behavioral field (defined per kind in §6.4) requires bumping `version`. Non-behavioral edits (comments, `description`, `notes`) are permitted without a version bump; CI verifies this using content hashing (see §6.4).

Deprecated versions remain in-tree with `deprecated: true` and a `supersededBy: <newVersion>` line until no `PromptTrace` in the last 90 days references them.

### 6.4 Hashing

At build time, `router-index.json` is regenerated. For each prompt, a `hash` is computed as `sha256(canonical_yaml(behavioral_fields))`, where the behavioral field set depends on the prompt's `kind`:

| Kind | Behavioral fields hashed |
|---|---|
| `completion` | `{kind, system, user, tools, outputSchema, variables}` |
| `fragment`   | `{kind, fragment, variables}` |

`kind` is always included so migrating a prompt between kinds is a behavioral change. Non-behavioral fields (`description`, `notes`, comments, whitespace outside a hashed string) are excluded so cosmetic edits do not change the hash. CI enforces: **if any hashed field of an existing `(id, version)` differs from its recorded hash, the build fails.** The fix is to bump `version` and add a new file at `<name>.v<n+1>.yaml`.

### 6.5 Runtime resolution

Callers pass a `PromptRef`:

```csharp
public sealed record PromptRef(string Id, int Version);
```

`Version` is REQUIRED — the router does not implicitly resolve "latest". This forces call sites to opt into new prompt versions explicitly and keeps A/B experiments legible.

The router loads the prompt via the build-time index, renders variables (strict — unknown variables in the template or missing required variables both fail loudly), validates required variables, and issues the call.

## 7. Output Logging — `PromptTrace`

Every non-streaming call and every streaming call at completion emit a `PromptTrace` row. Streaming calls emit one row per completed generation (not per chunk).

```jsonc
{
  "traceId": "…",
  "requestId": "…",                  // correlates with client request
  "learnerId": "…",                  // optional; null for anonymous calls
  "capability": "AssessmentModel",
  "resolvedModel": "gpt-5.6-sol",
  "reasoningEffort": "high",
  "promptId": "correction/classify",
  "promptVersion": 1,
  "promptHash": "sha256:…",
  "variableKeys": ["learnerUtterance", "conversationContext", "coachingMode", "proficiencyBand"],
  "startedAt": "2026-08-29T10:12:03.412Z",
  "latencyMs": 843,
  "tokenCounts": { "input": 512, "output": 220, "reasoning": 96, "total": 828 },
  "outcome": "success",              // success | validation_error | upstream_error | refusal
  "outcomeDetail": null,
  "experimentSlot": null,            // e.g. "TutorModel:terra-vs-luna:A"
  "overrideReason": null
}
```

Traces are written asynchronously and MUST NOT block the caller's response.

**Redaction.** `PromptTrace` intentionally does NOT contain the rendered prompt text or the model output — those are stored under a separate `PromptTraceContent` table gated by consent (see [#37 Privacy and consent](https://github.com/simonholmes001/voxa/issues/37)). Sizes are still recorded for cost tracking.

## 8. Testability

The router accepts an injectable OpenAI client interface. Two production-quality doubles ship with the backend:

- `FakeOpenAiClient` — deterministic, returns canned responses keyed by `(promptId, promptVersion)` for unit tests. Fails loudly if a call is unmatched.
- `RecordReplayOpenAiClient` — records a real interaction to disk and replays it in later runs. Used in integration tests to avoid live API dependency and to keep eval runs reproducible.

Every capability MUST have at least one unit test using `FakeOpenAiClient` proving:

1. The correct model is resolved under default config.
2. Env override overrides file config.
3. Per-call override wins, and refuses without `overrideReason` in production mode.
4. A behavioral edit to a committed `(id, version)` fails the build (contract test on the hash rule).
5. An unmapped capability throws `RouterConfigurationException`.
6. A missing required variable throws before any upstream call.

The Realtime path additionally has a test that `IssueRealtimeSessionAsync` centralizes reasoning-effort defaults and refuses to issue a session for a capability other than `RealtimeTutorModel` / `RealtimeTutorModelLite`.

## 9. Rollout Controls

- **Kill switch per capability.** Setting `experimentTrafficRatio=1.0` with `experimentModel="__disabled__"` short-circuits calls to a `UpstreamDisabledException` — used for emergency rollback while a fix is prepared.
- **Circuit breaker.** Per capability: if 5xx rate exceeds 20% over a 60-second window with ≥ 10 attempts, open for 30 seconds. Callers get `UpstreamCircuitOpenException`.
- **Cost cap.** Optional per-capability daily token cap (from env). Exceeding the cap returns `CostCapExceededException`; production monitors alert well before this.

## 10. Definition of Done (issue #31)

- Every one of the eight logical capabilities in §3 is implemented, with the initial default model mapping matching PRD §22.
- Cost-aware defaults per §4.2 are in place and covered by tests.
- Every generated output is accompanied by a `PromptTrace` row containing `promptId`, `promptVersion`, `promptHash`, `resolvedModel`, and `reasoningEffort`.
- The router can be fully exercised in tests via `FakeOpenAiClient` with no live OpenAI calls.
- The prompt hash rule (§6.4) is enforced in CI.
- No hardcoded model IDs remain in backend business logic — a repo grep for `gpt-` in `backend/` returns matches only in `backend/config/router.*` and `backend/prompts/**/*.yaml` `notes:` blocks.

## 11. Implementer Notes

These are implementation-time notes, not product decisions. They are recorded here so the backend implementer can address each explicitly during the build-out of this spec rather than rediscovering them.

- **I-01 (packaging).** Prompt YAML files should be embedded as resources in the backend assembly rather than mounted from a config volume: it is simpler, keeps prompts version-locked with the deployed binary, and is consistent with the immutability rule in §6.3. Final call sits with the implementer.
- **I-02 (pending [#37 Privacy and consent](https://github.com/simonholmes001/voxa/issues/37)).** The write policy for `PromptTraceContent` (rendered prompt text + model output) is defined by the privacy and consent work in #37. This spec expects it to be consent-gated by default; wire the storage seam so #37 can flip the switch without a router change.
- **I-03 (deferred).** Whether the A/B experiment framework surfaces to the mobile client (e.g. for feature flags) is deferred until Voxa actually runs an experiment. MVP stays server-side only.
