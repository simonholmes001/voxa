# Evaluation Cases

Design-facing eval cases the evaluation harness ([#32](https://github.com/simonholmes001/voxa/issues/32)) will execute against Voxa's AI capabilities. Cases here are authoritative for policy assertions in the specs — the runtime harness is expected to pick them up verbatim or via a straightforward transform.

## Directory layout

```
docs/evals/
├── README.md                          # this file
├── correction/
│   ├── overcorrection.v1.yaml         # policy §10 overcorrection cases
│   └── false-correction.v1.yaml       # policy §10 false-correction (native variance) cases
├── onboarding/
│   └── (extended by Codex from the spec §7 test list)
└── router/
    └── (extended by Codex from the router spec §8 test list)
```

## Case file schema

```yaml
suite: correction/overcorrection
version: 1
description: >
  What this suite proves and why.
context:            # optional; shared across cases in the suite
  targetLanguage: fr-FR
  coachingMode: natural
  proficiencyBand: B1-B2
cases:
  - id: 001
    description: >
      One-line description of the scenario.
    input:
      # capability-specific input; the harness maps this to a router call.
      learnerUtterance: "…"
      conversationContext: []
    assertions:
      # Each assertion is a simple predicate against the classifier output
      # or a downstream behavior (interrupt, debrief, memory write).
      - path: corrections
        length:
          equals: 0
      - path: interrupted
        equals: false
    tags: [overcorrection, natural-mode]
```

## Assertion predicates

- `equals`, `notEquals`
- `contains`, `notContains`
- `length: { equals | atLeast | atMost }`
- `matches: <regex>` (multiline)
- `oneOf: [...]`, `noneOf: [...]`
- `jsonSchema: { $ref: ... }` — full-shape validation

The harness ([#32](https://github.com/simonholmes001/voxa/issues/32)) is free to add more; every existing assertion here uses only the primitives above so it can adopt them without rework.

## Determinism

Every case MUST be deterministic. That means:
- No time-dependent inputs.
- No randomness in assertions (use `oneOf` if the model has legitimate variance).
- Any LLM-graded assertion uses the router's `RecordReplayOpenAiClient` or a `FakeOpenAiClient` seed.
