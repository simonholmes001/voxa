# Correction and Explanation Policy — Design Spec

**Status:** Draft (for backend + iOS + prompt implementation)
**Issue:** [#25 Implement correction and explanation policy](https://github.com/simonholmes001/voxa/issues/25)
**Source of truth:** PRD §12 (Conversation Mode), §13 (Correction System), §10 (AI Tutor), §20 (Adaptive Learner Model)
**Related specs:** [Onboarding and placement](./onboarding-and-placement.md), [Model router and prompt registry](./model-router-and-prompt-registry.md)

## 1. Purpose

Define **when** Voxa corrects, explains, interrupts, or lets a conversation continue — as a function of the learner's coaching mode, proficiency, and the character of the mistake. This policy is enforced two ways: in the Realtime session (interrupt vs defer) and in the post-turn debrief (which errors surface, how, and how the learner's error memory updates).

The goal is a tutor that never feels like a spell-checker on a phone call and never lets a genuinely learning-blocking error pass.

## 2. Scope

**In scope**
- Correction taxonomy — severity, class, recurrence.
- Behavior matrix over conversation modes × proficiency bands.
- Interruption thresholds during Realtime tutoring.
- Post-turn debrief rules.
- Error-memory update rules (what enters the learner's remediation queue).
- Anti-overcorrection guardrails.

**Non-goals**
- Pronunciation scoring internals — [#26](https://github.com/simonholmes001/voxa/issues/26).
- The Talk-screen UX — [#24](https://github.com/simonholmes001/voxa/issues/24).
- Realtime session lifecycle and barge-in mechanics — [#19](https://github.com/simonholmes001/voxa/issues/19).
- Full learner-model schema for error memory — belongs to the SR/vocab-grammar issue ([#27](https://github.com/simonholmes001/voxa/issues/27)); this spec defines only the write contract.

## 3. Correction Taxonomy

Every candidate correction is classified along three axes.

### 3.1 Class

| Class | Description | Example (FR) |
|---|---|---|
| `pronunciation` | Sound-level: phoneme, stress, intonation | `/y/` vs `/u/`: "tu" pronounced as "tout" |
| `morphology` | Word form: gender, agreement, conjugation | "un table" for "une table" |
| `syntax` | Word order, structure | "Je suis allé à Paris depuis deux ans" |
| `lexicon` | Wrong word, false friend, register slip | "assister" used to mean "assist" |
| `usage` | Grammatical but unnatural for a native speaker | "Je préfère plus X" |
| `register` | Formality mismatch for context | "tu" to a stranger in a formal scenario |
| `discourse` | Coherence, connector misuse, topic drift | Missing "d'ailleurs" / "en fait" for flow |

### 3.2 Severity

| Severity | Meaning | Default surfacing |
|---|---|---|
| `blocking` | Native speaker would not understand or would misunderstand | Interrupt permitted in every mode except Immersion; always surface in debrief |
| `high` | Understandable but distracting; would mark the learner as clearly non-native | Never interrupt; always in debrief |
| `medium` | Grammatically wrong but comprehensible; likely a slip | Never interrupt; in debrief only if not a one-off |
| `low` | Minor stylistic / usage nudge | Debrief only; suppressed in Natural / Immersion / Scenario / Debate / Story unless recurring |
| `native-variance` | Regional or stylistic variant, not an error | Never surfaced as a correction; may inform learner-model preferences |

Severity is assigned by the grader prompt (`correction/classify.v1`) using the `AssessmentModel` capability. A rubric is attached; the grader MUST return a `severity`, `class`, and one-sentence rationale.

### 3.3 Recurrence

Every classified error is looked up against the learner's error memory before surfacing:

- `first-observation` — no matching pattern in the last 30 days.
- `recurring` — 2–4 matching observations in the last 30 days.
- `chronic` — 5+ matching observations, or on the current remediation queue.

**Recurrence promotion rule.** Recurrence promotes an item's effective surfacing by exactly one band relative to the base cell in the §4 matrix:

- `—` (do not surface) → `D` (debrief only)
- `D` (debrief only) → `D` (unchanged — recurrence never adds live-interrupt permission)
- `I + D` → `I + D` (unchanged)

Recurrence, in other words, only prevents Voxa from *hiding* chronic problems from the debrief; it never earns an extra live interrupt. That decision is deliberate and protects §8 G-04 (debrief caps) and the interrupt budget in §4.4 rule 2 against a "chronic-item flood" that would otherwise override the anti-overcorrection guardrails.

`chronic` items additionally enter the remediation queue (see §7).

## 4. Behavior Matrix

Rows are the coaching modes from PRD §12.1; columns are proficiency bands. Cell values state **live-interrupt allowance** and **debrief surfacing** for each severity, before recurrence promotion (§3.3) is applied.

Legend:
- **I + D:** may interrupt live (barge-in with a brief recast) AND surface in debrief
- **D:** surface in post-turn debrief; no live interrupt
- **—:** do not surface (subject to promotion to `D` on recurrence per §3.3)

### 4.1 Beginner (A0–A2)

| Mode | blocking | high | medium | low |
|---|---|---|---|---|
| Tutor | I + D | D | D | — |
| Natural | I + D | D | — | — |
| Strict | I + D | I + D | D | — |
| Immersion | D | D | — | — |
| Scenario | I + D (only if it breaks the scenario) | D | — | — |
| Debate | *not offered at beginner* | — | — | — |
| Story | D | D | — | — |

### 4.2 Intermediate (B1–B2)

| Mode | blocking | high | medium | low |
|---|---|---|---|---|
| Tutor | I + D | D | D | D |
| Natural | I + D (rare) | D | — | — |
| Strict | I + D | I + D | D | D |
| Immersion | D | D | — | — |
| Scenario | I + D (only if in-role) | D | — | — |
| Debate | D | D | — | — |
| Story | D | D | — | — |

### 4.3 Advanced (C1+)

| Mode | blocking | high | medium | low |
|---|---|---|---|---|
| Tutor | I + D | D | D | D |
| Natural | I + D (rare) | D | D | — |
| Strict | I + D | I + D | D | D |
| Immersion | D | D | D | — |
| Scenario | I + D (only if in-role) | D | D | — |
| Debate | D | D | D | — |
| Story | D | D | D | — |

### 4.4 Absolute rules (override the matrix)

1. **Immersion never interrupts.** Any live correction breaks the mode contract.
2. **Interrupt budget per session.** At most **1 interruption per 3 minutes** of live conversation, regardless of mode. Additional would-be interruptions are queued to the debrief.
3. **No two consecutive interruptions.** After an interruption, the next candidate must go to debrief.
4. **Learner-initiated silence protection.** If the learner has held silence < 800ms after finishing a clause, do not interrupt.
5. **Learner requested a pause on corrections.** In-conversation instructions such as `"just let me talk"` or `"stop correcting"` suppress live interruptions for the **rest of the current session only**; debrief still runs unless the learner also disables debrief. A separate persistent **"Disable live corrections"** toggle in Settings applies across all future sessions until reversed. Spoken instructions never silently mutate the persistent preference — the boundary between session-only and persistent behavior is always driven by an explicit UI action.
6. **Native-variance is never a correction.** If the classifier returns `native-variance`, the item is discarded from the correction pipeline and optionally recorded as a preference.
7. **Pronunciation drills use a separate interrupt track.** Live feedback during pronunciation practice (repeat-after-me, minimal-pair drills) is intrinsically per-attempt and MUST NOT consume or share the grammar/vocabulary interrupt budget defined in rule 2. The pronunciation subsystem ([#26](https://github.com/simonholmes001/voxa/issues/26)) owns its own cadence rules; this policy applies only to conversational corrections.
8. **Debate mode holds blocking corrections to end of round.** In Debate, `blocking`-severity errors are never surfaced as live interrupts — they surface only in the post-round debrief. Debate is a rhetorical exercise where flow beats immediate correctness, and interrupting mid-argument would break the mode's contract even for otherwise "may interrupt" cases.

## 5. Interruption Mechanics

When the matrix + rules permit an interrupt, the Realtime tutor performs a **micro-recast**, not a full explanation:

1. Acknowledge briefly (one word, or a beat of silence).
2. Offer the corrected form.
3. Optionally add a 4–7 word cue.
4. Prompt the learner to continue.

Example:

> Learner: "Je suis allé à Paris depuis deux ans."
> Tutor: "Ah — on dirait: 'J'habite à Paris depuis deux ans'. Continue."

Total interruption ≤ 6 seconds of tutor speech. No grammar mini-lecture live; that goes to debrief.

The Realtime session receives the current coaching mode, proficiency band, interrupt budget, and "recent corrections" list via session config on each session start (see [#19](https://github.com/simonholmes001/voxa/issues/19)). The prompt fragment for interruption is `correction/live-recast.v1`.

## 6. Post-Turn Debrief

After the conversation ends (or on demand via the "Explain" button — PRD §13), the backend produces a debrief with the `TutorModel` capability and the `correction/debrief.v1` prompt.

For each surfaced correction, the debrief includes exactly the six PRD §13 fields:

- what the learner said
- corrected version
- why it was wrong
- how a native speaker would normally express it
- severity
- whether it is a recurring error

Plus tap-through actions (owned by iOS): **Explain**, **Hear it**, **Practice**, **Save**, **Give me another example**.

### Ordering

1. `chronic` recurrences first, ordered by severity desc.
2. Then `blocking` from the current turn.
3. Then `recurring` by severity desc.
4. Then `first-observation` up to a cap.

### Caps

- ≤ 3 items per debrief for beginner.
- ≤ 5 items per debrief for intermediate.
- ≤ 7 items per debrief for advanced.

Additional items are recorded to error memory but not shown, to protect against overcorrection fatigue.

## 7. Error Memory — Write Contract

Every classified correction (whether surfaced or not) writes to error memory. Schema owned by [#27](https://github.com/simonholmes001/voxa/issues/27); this spec fixes the write contract:

```jsonc
{
  "learnerId": "…",
  "occurredAt": "2026-08-29T10:12:03Z",
  "sessionId": "…",
  "conversationTurnId": "…",
  "class": "syntax",
  "severity": "high",
  "learnerUtterance": "Je suis allé à Paris depuis deux ans.",
  "corrected": "J'habite à Paris depuis deux ans.",
  "skillIds": ["fr.grammar.depuis-present", "fr.tense.present-continuous-analog"],
  "surfaced": true,
  "interrupted": false,
  "recurrenceState": "recurring",
  "promptTraceId": "…"
}
```

Recurrence promotion into the remediation queue:
- `recurring` on the same `skillId` twice within 14 days → queue at "review-soon".
- `chronic` → queue at "practice-next-session"; unlocks a targeted mini-drill.

## 8. Anti-Overcorrection Guardrails

These are non-negotiable; each is a testable eval case.

- **G-01.** The classifier MUST NOT flag `native-variance` items as corrections. Eval cases in `docs/evals/correction/false-correction.v1.yaml` include regional variants and register-appropriate colloquialisms.
- **G-02.** The classifier MUST NOT flag a form that appears in an accepted reference corpus for the target language at the learner's level.
- **G-03.** In Natural + Immersion + Scenario + Debate + Story modes at intermediate/advanced, `medium` and below are never surfaced live.
- **G-04.** The debrief MUST honor the per-mode cap even when many candidates exist.
- **G-05.** Learner-typed dialect or register preference (e.g., "I'm learning Quebec French") suppresses corrections that only apply to a different variant.
- **G-06.** If two consecutive debriefs contain zero `blocking` or `high` items and ≥ 1 `low`, the next debrief further reduces the cap by 1 (down to a floor of 1) — this addresses the "nitpick spiral" failure mode.

## 9. Prompts

Placed under [`docs/prompts/correction/`](../prompts/correction/):

- `correction/classify.v1` — takes a learner utterance in context (+ mode + level), returns classified corrections with rubric-rationale. `AssessmentModel`.
- `correction/live-recast.v1` — fragment appended to the Realtime session's system prompt when live interruption is permitted for this turn.
- `correction/debrief.v1` — produces the ordered, capped debrief. `TutorModel`.
- `correction/mode-fragment.tutor.v1`, `.natural.v1`, `.strict.v1`, `.immersion.v1`, `.scenario.v1`, `.debate.v1`, `.story.v1` — system-prompt fragments per mode, injected into both Realtime and debrief prompts. Each mode fragment declares `compatibleCapabilities` for the governing Realtime and debrief capabilities that may compose it.

Example provided: [`correction/mode-fragment.tutor.v1.yaml`](../prompts/correction/mode-fragment.tutor.v1.yaml). The rest are stub-generated by Codex against the same schema.

## 10. Evaluation (feeds #32 harness)

Initial cases under [`docs/evals/correction/`](../evals/):

- `overcorrection.v1.yaml` — Natural mode + intermediate: starter coverage for no live interrupt on `medium` items, debrief caps, and selected G-03/G-04/G-06 scenarios.
- `false-correction.v1.yaml` — starter coverage for G-01/G-02/G-05 native-variance, reference-corpus, and register-preference cases.
- `mode-adherence.v1.yaml` (Codex to extend in #32) — one case per mode × level cell verifying the matrix.
- `interrupt-budget.v1.yaml` (Codex to extend in #32) — synthetic conversation with 5 correction-worthy utterances in 2 minutes MUST yield ≤ 1 interruption.
- `error-memory.v1.yaml` (Codex to extend in #32) — after 3 recurrences of the same `skillId` in 10 days, remediation queue includes that skill.

## 11. Definition of Done (issue #25)

- Correction behavior varies by learner mode and proficiency per the matrix in §4.
- The tutor's interrupt rate stays within the budget in §4.4 across the evaluation suite.
- Every classified correction writes to error memory using the §7 schema (whether surfaced or not).
- Evaluation cases cover false corrections and overcorrection (§10, including `false-correction.v1.yaml` and `overcorrection.v1.yaml`).
- All model calls use logical capabilities via the router.
- Full implementation DoD: the #32 evaluation harness includes pass/fail assertions for G-01 through G-06, including mode-adherence, interrupt-budget, and error-memory suites. This PR contributes starter eval coverage through `false-correction.v1.yaml` and `overcorrection.v1.yaml`; G-03/G-04 remain partial until #32 expands the suite.

## 12. Open Decisions

_None outstanding. D-04, D-05, and D-06 have been resolved and folded into §4.4 (rules 5, 7, and 8 respectively)._
