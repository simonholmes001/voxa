# Onboarding and Placement Assessment — Design Spec

**Status:** Draft (for backend + iOS implementation)
**Issue:** [#20 Implement onboarding profile and placement assessment flow](https://github.com/simonholmes001/voxa/issues/20)
**Source of truth:** PRD §9 (Onboarding), §8 (CEFR framing), §20 (Adaptive Learner Model)
**Related specs:** [Correction and explanation policy](./correction-and-explanation-policy.md), [Model router and prompt registry](./model-router-and-prompt-registry.md)

## 1. Purpose

Take a new learner from first launch to a personalized first learning plan without feeling like an administrative form. Produce a CEFR-aligned level estimate, persist the learner profile and initial plan server-side, and support resume across devices.

## 2. Scope

**In scope**
- First-run onboarding UX flow and inputs (PRD §9.1).
- Adaptive placement algorithm — one path for absolute beginners, one for existing learners (PRD §9.2).
- First learning plan synthesis (PRD §9.3).
- Backend contracts for step-by-step progress capture, resume, and finalization.
- Prompt design for the conversational placement segment.

**Non-goals**
- Sign in with Apple wiring — covered by [#17](https://github.com/simonholmes001/voxa/issues/17).
- The full learner model schema — this spec defines only the initial slice written at onboarding finalization; the wider schema is owned by [#14 Define canonical Voxa domain model and API contracts](https://github.com/simonholmes001/voxa/issues/14).
- Talk-screen tutor UX and Realtime session lifecycle ([#19](https://github.com/simonholmes001/voxa/issues/19), [#24](https://github.com/simonholmes001/voxa/issues/24)).
- Placement UI polish beyond adaptive-difficulty behavior. The Home surface is owned by [#28](https://github.com/simonholmes001/voxa/issues/28).

## 3. Onboarding Flow

Onboarding is modeled as an ordered, resumable **session** of discrete **steps**. The server is authoritative on step order and completion; the client renders the current step.

### 3.1 Step Sequence

| # | Step key | Kind | Required inputs (PRD §9.1) captured |
|---|---|---|---|
| 1 | `welcome` | Static | — (introduce Voxa, request microphone + notifications later) |
| 2 | `native_language` | Single-select | native language |
| 3 | `target_language` | Single-select (French for MVP; [#45](https://github.com/simonholmes001/voxa/issues/45)) | target language |
| 4 | `prior_experience` | Single-select (`none` / `some` / `formal_study` / `lived_immersion`) | prior experience |
| 5 | `self_reported_level` | Single-select CEFR bucket (`unknown`, `A1`, `A2`, `B1`, `B2`, `C1+`) | approximate current level |
| 6 | `goals` | Multi-select + free text | primary goal, reasons for learning, areas of interest |
| 7 | `target_level_and_date` | CEFR select + optional date | desired target level, target date |
| 8 | `study_time` | Single-select (`5m`, `15m`, `30m`, `45m`, `60m+`) | preferred daily study duration |
| 9 | `confidence_self_rating` | 3× 1–5 sliders | speaking / reading / writing confidence |
| 10 | `placement_intro` | Static | — (explain that the next 3–8 minutes calibrate the plan) |
| 11 | `placement` | **Adaptive** — see §4 | populates initial CEFR estimate and skill deltas |
| 12 | `plan_review` | Read-only presentation of first plan | — (learner confirms or requests adjustment) |
| 13 | `finalize` | Server-side finalization | plan committed, learner state initialized |

**Absolute-beginner shortcut.** If `self_reported_level = unknown` AND `prior_experience = none`, step 11 is replaced by `placement_skipped` — the server sets the estimate to `A0` (pre-A1) and produces a beginner plan. This honors PRD §9.2's "should not require every user to complete a fixed 40-question test."

**Estimated total time.** ≤ 3 minutes for absolute beginners; ≤ 10 minutes for existing learners.

### 3.2 UX Principles

- One decision per screen; every screen shows progress (`step N of M`, adaptive placement shows only an indeterminate indicator).
- No account gate before step 11. Sign in with Apple is requested at `plan_review` so the plan can be persisted server-side. Prior steps are stored on-device against an anonymous session id and synced upon sign-in.
- Every input is editable in Settings after onboarding — nothing captured here is one-shot.
- Copy avoids testing vocabulary ("assessment") in favor of teaching vocabulary ("let's see where you are").

## 4. Placement Assessment

### 4.1 Design Constraints

- Adaptive difficulty: item difficulty adjusts based on prior responses (PRD §9.2).
- Multi-modal coverage: conversational interview, listening, vocabulary, grammar, reading, pronunciation, short written production (PRD §9.2). MVP MUST include conversational interview + vocabulary + grammar; SHOULD include listening + short reading; MAY defer pronunciation and short written production to a "pronunciation check" mini-step after the first lesson.
- Stop rule: end when either (a) the CEFR posterior has narrowed to a single band with confidence ≥ 0.7, (b) 12 items have been administered, or (c) the learner asks to stop.

### 4.2 Algorithm (item-by-item)

The server maintains a **placement session state**:

```jsonc
{
  "sessionId": "…",
  "estimatedLevel": "A2",          // current mode of posterior
  "levelPosterior": {              // discrete distribution over CEFR bands
    "A1": 0.05, "A2": 0.55, "B1": 0.30, "B2": 0.08, "C1+": 0.02
  },
  "skillEstimates": {              // per-skill provisional bucket
    "speaking":       { "level": "A2", "confidence": 0.4 },
    "listening":      { "level": "B1", "confidence": 0.3 },
    "vocabulary":     { "level": "A2", "confidence": 0.5 },
    "grammar":        { "level": "A2", "confidence": 0.5 },
    "reading":        { "level": "B1", "confidence": 0.3 },
    "pronunciation":  { "level": "unknown", "confidence": 0.0 }
  },
  "itemsAdministered": [ /* … */ ],
  "stopReason": null
}
```

**Item-selection loop**

1. Compute the current CEFR mode.
2. Choose the **weakest-signal skill** among those with confidence < 0.6.
3. Ask the router for an item at difficulty ≈ current mode ± 1 CEFR step for that skill, using the `CurriculumModel` capability (PRD §22, mapped to `gpt-5.6-sol` initially — see [model router spec](./model-router-and-prompt-registry.md)).
4. Grade the response — correctness is a rubric-graded probability, not binary. Grading uses the `AssessmentModel` capability with a rubric-carrying prompt (`assessment/placement-grade.v1`).
5. Bayesian-update the CEFR posterior and the skill estimate using the item's difficulty and observed correctness.
6. Evaluate stop rule.

**Conversational segment.** Items 1–3 are administered as a short conversational interview through the `TutorModel` capability with the `onboarding/placement-conversation.v1` prompt. The tutor asks open-ended questions in the target language (with graceful fallback to the native language if the learner does not respond in ≤ 8s or explicitly asks). Free-text responses are graded on grammar accuracy, vocabulary breadth, and register.

**Written production.** Item 12 (if administered) is a 2–3 sentence prompt at the current-mode difficulty; graded on grammar, vocabulary, and coherence.

**No spoken audio in MVP.** Voice-based placement items are deferred until [#19 iOS WebRTC Realtime session client](https://github.com/simonholmes001/voxa/issues/19) is available; the conversational segment uses text-only input during onboarding for MVP. The follow-up work is tracked as a first-class board item — see §10 Follow-ups.

### 4.3 First Learning Plan (PRD §9.3)

After placement (or the beginner shortcut), the server synthesizes the first plan with `CurriculumModel` and the `onboarding/first-plan-synthesis.v1` prompt. Inputs:

- Learner profile (from steps 2–9).
- Placement session state (final).
- Language-content baseline for the target language ([#45](https://github.com/simonholmes001/voxa/issues/45)).

Output schema:

```jsonc
{
  "estimatedLevel": "A2",                    // CEFR
  "targetLevel": "B2",
  "estimatedWeeksToTarget": 40,              // best-effort; presented as "roughly"
  "strengths": ["reading", "basic grammar"],
  "priorityWeaknesses": [
    "spontaneous speech",
    "past tense accuracy",
    "listening at native speed"
  ],
  "recommendedDailyMinutes": 30,
  "firstMilestone": {
    "description": "Hold a 10-minute conversation about everyday life without switching to English.",
    "targetDate": null
  },
  "weekOnePlan": [
    { "day": 1, "focus": "past tense — recognition", "estMinutes": 25, "lessonType": "grammar" },
    { "day": 2, "focus": "everyday life vocabulary", "estMinutes": 20, "lessonType": "vocabulary" }
    // …
  ]
}
```

This shape drives the `plan_review` screen and seeds the Home / Today surface owned by [#28](https://github.com/simonholmes001/voxa/issues/28).

## 5. Backend Contracts

Owned by the backend modular monolith ([#33](https://github.com/simonholmes001/voxa/issues/33)); this spec proposes shapes for the API-contract issue ([#14](https://github.com/simonholmes001/voxa/issues/14)) to ratify.

Route family: `/api/*`, aligned with the PRD §50 API surface. The PRD deliberately models the **profile** side of onboarding and the **placement assessment** as separate resources; this spec follows that shape rather than nesting placement under an onboarding-session URL. Cross-device resume uses the PRD's dedicated `/api/session/resume` endpoint.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/onboarding` | Upsert the learner onboarding profile. Accepts a partial payload keyed by the step (`native_language`, `target_language`, `prior_experience`, …); the server merges into the caller's profile document and returns the merged profile plus `nextStepKey`. Idempotent per `Idempotency-Key` header (client supplies one per step submission). Advancing through the flow is done by repeated calls to this endpoint. |
| `GET` | `/api/session/resume` | Cross-device resume. Returns a discriminated union: `{ kind: "onboarding", nextStepKey, profileSoFar }`, `{ kind: "plan_review", planId }`, `{ kind: "lesson", lessonId }`, or `{ kind: "home" }`. Onboarding steps prior to `finalize` are the primary case for this spec. |
| `POST` | `/api/assessment/start` | Begin adaptive placement. Body includes the profile snapshot needed to seed difficulty. Returns `assessmentId` and the first item. |
| `POST` | `/api/assessment/{assessmentId}/answer` | Submit a graded response for the current item. Returns either the next item or `{ done: true, resultId }`. Idempotent per `Idempotency-Key` bound to the item id. |
| `GET` | `/api/assessment/{assessmentId}/result` | Fetch the final placement result (`estimatedLevel`, `levelPosterior`, `skillEstimates`, `priorityWeaknesses`). Callable only after the assessment is `done`. |
| `GET` | `/api/learning-plan` | Fetch the current first learning plan for the caller (populated by finalization; drives the `plan_review` screen and the Home / Today surface). |
| `POST` | `/api/learning-plan/regenerate` | Called from `plan_review` when the learner requests adjustments (e.g., "less grammar", "more speaking"). Regenerates the plan through the `CurriculumModel` capability with the same synthesis prompt and returns the new plan. |

**Finalization is implicit, not a distinct endpoint.** Once (a) `POST /api/onboarding` has captured every required field in §3.1 up to and including `study_time` and `confidence_self_rating`, and (b) `GET /api/assessment/{id}/result` succeeds (or the beginner shortcut fires in §4.1 which populates a synthetic result), the server auto-materializes the `LearnerState.initial` record and calls the plan-synthesis prompt to produce `LearningPlan.v1`. From that point `GET /api/learning-plan` returns 200. This keeps the API surface as documented in the PRD (no `/api/onboarding/finalize` route) and lets the client rely on `GET /api/session/resume` returning `kind: "plan_review"` as the finalization signal.

**Resume across devices** (PRD acceptance criterion). For signed-in users the profile is server-authoritative from the first step and `GET /api/session/resume` is the canonical way to pick up where the learner left off — including which onboarding step comes next. For pre-sign-in steps the client caches responses locally under an anonymous session token minted at first launch and replays them via `POST /api/onboarding` on first sign-in; the server accepts out-of-order step submissions only until finalization, after which edits go through Settings.

**Auth.** All endpoints require the app session issued by [#17 SIWA](https://github.com/simonholmes001/voxa/issues/17) except `POST /api/onboarding` and `POST /api/assessment/*`, which accept the anonymous session token for the pre-sign-in window. The server enforces that anonymous callers cannot trigger finalization: it holds the merged state until the caller either signs in (SIWA at `plan_review`) or the anonymous token expires.

**Data written on finalization.**
- `Profile`: languages, goals, confidence, study-time preference.
- `LearnerState.initial`: CEFR estimate, per-skill provisional bucket, priority weaknesses.
- `LearningPlan.v1`: full plan doc as returned by the synthesis prompt.
- `PromptTrace`: `promptId`, `promptVersion`, `promptHash`, model, request id, latency, token counts — one row per LLM call, per [model router spec](./model-router-and-prompt-registry.md).

## 6. Prompts

Placed under [`docs/prompts/onboarding/`](../prompts/onboarding/) per the [registry conventions](../prompts/README.md).

- `onboarding/placement-conversation.v1` — target-language conversational interview, adaptive difficulty guidance, native-language fallback rule, register controls.
- `onboarding/placement-grade.v1` — rubric-carrying grader used by `AssessmentModel`; deterministic JSON output.
- `onboarding/first-plan-synthesis.v1` — builds the `LearningPlan.v1` structure from profile + placement state + language-content baseline.

## 7. Evaluation (feeds #32 harness)

Acceptance test cases live under [`docs/evals/onboarding/`](../evals/) (initial set — expand in [#32](https://github.com/simonholmes001/voxa/issues/32)):

- **Beginner shortcut fires** when `self_reported_level=unknown ∧ prior_experience=none`.
- **Adaptive difficulty rises** after two correct items at the current difficulty.
- **Adaptive difficulty falls** after two incorrect items.
- **Stop rule** — session ends within 12 items across representative learner personas.
- **CEFR estimate stability** — for a synthetic "true B1" learner, ≥ 80% of runs terminate with mode = B1.
- **Resume correctness** — replay of a partial session on a second device returns identical `currentStep` and state.
- **Language fallback** — when the learner responds in the native language during the conversational segment, the tutor acknowledges in the target language before switching once.

## 8. Definition of Done (issue #20)

- Onboarding captures every PRD §9.1 input without any single screen exceeding one primary decision.
- The placement step terminates by stop rule and produces a CEFR estimate with per-skill provisional buckets.
- Finalization (implicit — see §5) writes `Profile`, `LearnerState.initial`, `LearningPlan.v1`, and `PromptTrace` rows; repeated onboarding submissions after finalization are rejected with a clear error and directed to Settings.
- Interrupted onboarding resumes on a second device via `GET /api/session/resume` with the same captured profile and `nextStepKey`.
- Evaluation harness in [#32](https://github.com/simonholmes001/voxa/issues/32) picks up the placement + grading eval cases.
- No hardcoded model IDs anywhere in the onboarding code path — all model calls go through the router by capability.

## 9. Open Decisions

- **D-02.** Anonymous session token lifetime — proposed 30 days, deleted on `finalize`. Awaiting confirmation from [#37 Privacy and consent](https://github.com/simonholmes001/voxa/issues/37).
- **D-03.** Whether the first-plan `estimatedWeeksToTarget` is shown to the learner. Recommend showing as "roughly N weeks at your chosen pace" to set expectations; alternative is hiding it to avoid discouragement.

## 10. Follow-ups

- [#51 Add voice-based placement to onboarding](https://github.com/simonholmes001/voxa/issues/51) — tracks the voice-first placement experience (spoken conversational segment + short pronunciation micro-assessment) once [#19 iOS WebRTC Realtime session client](https://github.com/simonholmes001/voxa/issues/19) is available. This is the durable tracker for what was previously flagged as D-01; text-only placement in this spec is deliberately an MVP stepping stone, not the target end state.
