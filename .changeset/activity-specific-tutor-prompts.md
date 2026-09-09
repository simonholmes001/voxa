---
"voxa": minor
---

Realtime tutor now runs a distinct prompt per activity. Nine activity templates (open practice, guided lesson, review, pronunciation drill, scenario roleplay, mistakes replay, vocabulary drill, listening practice, key-language briefing) live in `backend/prompts/realtime-tutor/*.v1.yaml` and compose a shared `realtime-tutor/persona-base.v1` fragment that carries identity, level-adaptation, turn-taking, and the target-language handoff cue. `OpenAiRealtimeClientSecretIssuer` now routes `SessionIntent` → `PromptRef` and asks `IPromptRegistry` to render, replacing the inline `BuildInstructions` string builder. iOS `RealtimeTutorIntent` gains six new cases and every intent emits the snake_case string the backend router matches on; unknown or legacy intents fall back safely to open-practice.
