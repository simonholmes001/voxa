# Voxa — Product Requirements Document

**Working Product Name:** Voxa  
**Document Type:** Product Requirements Document (PRD)  
**Version:** 1.1  
**Date:** 26 August 2026
**Revision:** OpenAI model and Realtime architecture review  
**Platforms:** iPhone and iPad first  
**Primary Client Technology:** Swift / SwiftUI  
**Backend:** .NET 10  
**AI Platform:** OpenAI API  
**Cloud Infrastructure:** Microsoft Azure, deliberately minimal and cost-gated  
**Status:** Initial product definition

---

# 1. Executive Summary

Voxa is an AI-native language-learning application designed to take a learner from their current ability to genuine practical fluency in a chosen language.

The product is not intended to be a conventional course application with an AI chatbot added to it. The AI tutor is the product.

A user should be able to tell Voxa:

> "I want to learn Japanese."

Voxa should then determine:

- what the learner already knows;
- why they want to learn the language;
- what type of language they need;
- how much time they can dedicate;
- how quickly they want to progress;
- how they learn most effectively;
- what pronunciation problems they have;
- what vocabulary and grammar they have mastered;
- what they repeatedly forget;
- what situations they need to handle in real life;
- and what they should learn next.

Voxa then creates and continuously adapts a personalized learning program.

The application must teach all major language skills:

1. speaking;
2. listening;
3. pronunciation;
4. vocabulary;
5. grammar;
6. reading;
7. writing;
8. conversational comprehension;
9. idiomatic language;
10. cultural and pragmatic communication.

The central product objective is not completion of lessons. It is the ability to communicate naturally in the target language.

The long-term ambition is:

> **Voxa should become the closest practical equivalent to having a highly capable private language teacher available at any time.**

---

# 2. Product Vision

## 2.1 Vision Statement

Create an AI language tutor capable of taking a learner from zero knowledge to confident real-world communication through continuous assessment, personalized instruction, deliberate practice, and natural spoken interaction.

## 2.2 Product Philosophy

Voxa follows five principles.

### AI first

The curriculum is not a fixed sequence of screens.

The system determines the best next learning activity based on the learner's actual performance.

### Conversation first

The ultimate objective of language learning is communication.

Speaking and listening therefore begin as early as possible.

### Adaptive, not linear

Two learners studying French should not necessarily receive the same lesson sequence.

The curriculum must change according to:

- ability;
- mistakes;
- interests;
- learning velocity;
- objectives;
- native language;
- pronunciation difficulties;
- prior language knowledge;
- available study time.

### Explain when necessary, immerse when possible

Beginners require explanation.

More advanced learners require increasingly greater exposure to the target language.

Voxa should gradually reduce dependence on the learner's native language.

### Fluency over gamification

Streaks, XP, levels, challenges, and achievements may help motivation, but they must never become the purpose of the product.

A user should progress because their language ability is improving, not because they learned how to optimize a points system.

---

# 3. Product Positioning

Voxa sits between:

- structured language applications such as Bunpo;
- gamified systems such as Duolingo;
- conversational AI;
- private language tutors;
- pronunciation applications;
- vocabulary applications;
- grammar reference applications;
- and human conversation platforms.

The differentiator is that these capabilities are combined into one persistent AI tutor.

The product should feel less like navigating a language course and more like working with a teacher who knows:

- everything the learner has studied;
- every significant error they have made;
- which concepts are weak;
- which words are becoming stable;
- how they pronounce difficult sounds;
- what topics interest them;
- and what should happen next.

---

# 4. Target Users

## 4.1 Primary Personas

### Complete Beginner

Has little or no knowledge of the language.

Needs:

- foundations;
- pronunciation;
- writing system where applicable;
- survival vocabulary;
- basic grammar;
- confidence speaking immediately.

### Returning Learner

Previously studied the language but has forgotten much of it.

Needs:

- rapid placement testing;
- gap identification;
- refresher curriculum;
- vocabulary reactivation;
- speaking practice.

### Intermediate Learner

Can understand and communicate but struggles with natural conversation.

Needs:

- larger active vocabulary;
- listening speed;
- spontaneous speech;
- grammar correction;
- pronunciation refinement;
- idiomatic expressions.

### Advanced Learner

Already communicates well.

Needs:

- nuance;
- native-like phrasing;
- pronunciation refinement;
- professional vocabulary;
- cultural context;
- complex reading;
- sophisticated writing.

### Goal-Oriented Learner

Needs language for a particular objective.

Examples:

- travel;
- relocation;
- work;
- university;
- relationship/family;
- exam preparation;
- citizenship;
- business negotiation;
- technical work.

---

# 5. User Goals

The system must support goals such as:

- "I want conversational French."
- "I am moving to Japan in six months."
- "I need B2 German."
- "I want to speak Spanish with my partner's family."
- "I need business English."
- "I want to read Japanese manga."
- "I want to read French literature."
- "I need to pass DELF B2."
- "I want to understand Korean television without subtitles."
- "I can read Italian but I cannot speak it."

Each goal should result in a materially different learning plan.

---

# 6. Success Definition

Voxa succeeds when users measurably improve their ability to use the language.

Primary product outcomes:

- increased listening comprehension;
- increased spontaneous speaking ability;
- reduced recurring grammatical errors;
- improved pronunciation intelligibility;
- increased active vocabulary;
- improved reading ability;
- improved writing ability;
- increased ability to handle real-world scenarios;
- measurable progression through CEFR or an equivalent internal proficiency framework.

The system should never equate "lesson completed" with "skill mastered."

---

# 7. Supported Proficiency Framework

Voxa should use CEFR internally where appropriate:

- A0 — true beginner / pre-A1;
- A1;
- A2;
- B1;
- B2;
- C1;
- C2.

CEFR should not constrain languages for which other frameworks are more useful.

The architecture must allow mappings such as:

- JLPT for Japanese;
- HSK for Chinese;
- TOPIK for Korean;
- ACTFL;
- IELTS/TOEFL-oriented English objectives;
- DELF/DALF;
- Goethe-Zertifikat;
- DELE.

The learner model should store both:

1. an overall proficiency level;
2. separate proficiency estimates for individual skills.

Example:

```text
Overall: B1

Speaking:      A2+
Listening:     B1
Reading:       B2
Writing:       A2
Grammar:       B1
Vocabulary:    B1
Pronunciation: A2
```

This asymmetric skill model is essential.

---

# 8. Language Coverage

The architecture must be language-independent.

Initial launch should concentrate on a smaller group of high-quality languages rather than claiming universal support immediately.

Recommended initial set:

- English;
- French;
- Spanish;
- German;
- Italian;
- Portuguese;
- Japanese.

Subsequent candidates:

- Korean;
- Mandarin Chinese;
- Dutch;
- Swedish;
- Norwegian;
- Polish;
- Russian;
- Arabic.

Each supported language requires a language-specific configuration defining:

- writing system;
- phonology;
- pronunciation considerations;
- grammar progression;
- politeness/register system;
- transliteration policy;
- CEFR/framework mappings;
- high-frequency vocabulary;
- cultural conventions;
- known learner difficulties by source language.

The LLM remains general-purpose, but pedagogy must not rely entirely on generic prompting.

---

# 9. Onboarding

Onboarding should feel like meeting a teacher, not completing an administrative form.

## 9.1 Required Inputs

Voxa should establish:

- native language;
- target language;
- prior experience;
- approximate current level;
- primary goal;
- desired target level;
- target date if applicable;
- preferred daily study duration;
- speaking confidence;
- reading confidence;
- writing confidence;
- reasons for learning;
- areas of interest.

## 9.2 Placement Assessment

Existing learners should be offered an adaptive placement assessment.

The assessment should include, where appropriate:

- conversational interview;
- listening;
- vocabulary;
- grammar;
- reading;
- pronunciation;
- short written production.

The AI should dynamically increase or decrease difficulty.

A placement test should not require every user to complete a fixed 40-question test.

## 9.3 First Learning Plan

After assessment, Voxa produces:

- estimated current level;
- strengths;
- weaknesses;
- target;
- estimated learning path;
- initial weekly plan;
- recommended daily study duration;
- first milestone.

Example:

```text
Current level: A2 French
Target: B2 conversational French
Time available: 30 min/day

Current strengths:
- reading
- basic grammar
- everyday vocabulary

Priority weaknesses:
- spontaneous speech
- past tense accuracy
- listening at native speed
- /y/ vs /u/ pronunciation

Next milestone:
Hold a 10-minute conversation about everyday life without switching to English.
```

---

# 10. AI Tutor

The AI tutor is the central interface.

It should have a persistent understanding of the learner.

The tutor must be able to:

- teach;
- explain;
- ask questions;
- converse;
- challenge;
- correct;
- demonstrate;
- listen;
- assess;
- review;
- encourage repetition;
- create examples;
- generate exercises;
- adapt difficulty;
- track mastery;
- determine the next learning action.

The learner should be able to interrupt the lesson naturally.

Examples:

- "Why is that feminine?"
- "Say that again more slowly."
- "What does that word mean?"
- "Why can't I use this tense?"
- "How would a native speaker actually say this?"
- "Give me another example."
- "I don't understand."
- "Can we practice this?"
- "Let's stop grammar and just talk."
- "Test me on yesterday's vocabulary."

The system should respond immediately and alter the lesson appropriately.

---

# 11. Lesson System

## 11.1 Dynamic Lesson Generation

Lessons are generated from:

- learner objectives;
- curriculum requirements;
- learner model;
- mastery scores;
- spaced-repetition schedule;
- recent mistakes;
- pronunciation weaknesses;
- previous conversations;
- upcoming milestones;
- user interests.

A lesson should therefore not simply be retrieved from a static catalog.

## 11.2 Lesson Structure

A typical 20-minute lesson could be:

```text
2 min   retrieval review
4 min   new concept
4 min   guided examples
5 min   spoken practice
3 min   conversation
2 min   assessment and summary
```

This structure is configurable.

## 11.3 Lesson Types

Voxa should support:

- grammar lessons;
- vocabulary lessons;
- listening lessons;
- pronunciation lessons;
- reading lessons;
- writing lessons;
- guided conversations;
- role plays;
- dictation;
- translation exercises;
- sentence construction;
- comprehension exercises;
- storytelling;
- picture description;
- error correction;
- free conversation;
- exam simulations;
- rapid reviews.

---

# 12. Conversation Mode

Conversation is one of the flagship experiences.

The user taps **Talk** and begins speaking.

The conversation should feel natural rather than turn-based wherever technically possible.

The AI must:

- listen continuously;
- detect when the learner has finished speaking;
- respond naturally;
- allow interruption;
- adapt its speed;
- adapt vocabulary complexity;
- remember the conversation;
- correct errors according to the selected coaching mode.

## 12.1 Conversation Modes

### Tutor Mode

The AI actively corrects and teaches.

### Natural Conversation

The AI prioritizes flow and delays minor corrections.

### Strict Correction

The AI identifies nearly every meaningful error.

### Immersion

Only the target language is used unless the learner explicitly asks for help.

### Scenario

Examples:

- restaurant;
- airport;
- doctor;
- hotel;
- job interview;
- date;
- business meeting;
- university;
- taxi;
- shopping;
- apartment viewing.

### Debate

For advanced learners.

### Story

AI and learner collaboratively tell a story.

---

# 13. Correction System

Corrections must be useful without destroying conversational flow.

For each meaningful mistake Voxa may identify:

- what the learner said;
- corrected version;
- why it was wrong;
- how a native speaker would normally express it;
- severity;
- whether it is a recurring error.

Example:

```text
You said:
"Je suis allé à Paris depuis deux ans."

Better:
"J'habite à Paris depuis deux ans."

Why:
French uses the present tense with "depuis" for an action that began in the past and continues now.
```

The learner can tap:

- Explain;
- Hear it;
- Practice;
- Save;
- Give me another example.

Repeated mistakes should automatically enter the learner's remediation queue.

---

# 14. Pronunciation System

Pronunciation is a core subsystem.

It must go beyond determining whether speech could be transcribed.

## 14.1 Pronunciation Capabilities

The system should:

- play native-quality pronunciation;
- allow the learner to record themselves;
- transcribe the attempt;
- compare intended vs detected speech;
- identify likely pronunciation problems;
- explain mouth/tongue/lip positioning where useful;
- allow immediate repetition;
- track recurring pronunciation weaknesses;
- generate targeted minimal-pair practice.

Example:

```text
Target:
"tu"

Your pronunciation is closer to:
"tout"

Focus:
French /y/ requires the tongue position of "ee" while rounding the lips.

Try again.
```

## 14.2 Pronunciation Dimensions

Where technically supportable:

- phoneme production;
- word stress;
- sentence stress;
- rhythm;
- vowel quality;
- consonant production;
- liaison;
- intonation;
- syllable timing;
- intelligibility.

## 14.3 Pronunciation Scoring

Voxa should avoid presenting false precision.

The MVP should use qualitative categories such as:

- Excellent;
- Good;
- Understandable;
- Needs work;
- Try again.

Internally, confidence values may be recorded.

A future dedicated phoneme/acoustic scoring service may be introduced if benchmarking demonstrates that model-based diagnosis alone is insufficient.

---

# 15. Reading and Writing Systems

Languages with non-Latin scripts need specific treatment.

Examples:

### Japanese

- hiragana;
- katakana;
- kanji;
- readings;
- stroke-order assistance;
- furigana controls;
- romaji progressively disabled.

### Mandarin

- characters;
- pinyin;
- tones;
- character recognition;
- simplified/traditional options.

### Korean

- Hangul construction;
- pronunciation rules;
- batchim;
- sound changes.

### Arabic

- alphabet;
- connected forms;
- diacritics;
- Modern Standard Arabic vs dialect decisions.

Voxa must teach users to read the language rather than making transliteration a permanent dependency.

---

# 16. Vocabulary System

Vocabulary should be managed as a personalized knowledge graph rather than a flat word list.

Each lexical item may contain:

- lemma;
- translation;
- definitions;
- example sentences;
- frequency;
- register;
- pronunciation;
- grammatical gender;
- plural;
- conjugation information;
- related words;
- synonyms;
- antonyms;
- collocations;
- idioms;
- contexts encountered;
- mastery score;
- last reviewed;
- next review.

The system should distinguish:

- unseen;
- recognized;
- understood;
- retrievable;
- usable with prompting;
- actively mastered.

---

# 17. Spaced Repetition

A spaced repetition engine should automatically schedule review.

Review units include:

- vocabulary;
- grammar;
- phrases;
- pronunciation targets;
- recurring mistakes;
- listening patterns;
- writing mistakes.

The learner should not have to manually construct flashcards.

Anything worth remembering can become a review item automatically.

---

# 18. Grammar Engine

Grammar instruction should be contextual.

The tutor should:

- explain concepts;
- compare them with the learner's native language;
- show examples;
- generate exercises;
- detect mistakes;
- record weak concepts;
- revisit them later.

The user should be able to ask:

> "Explain the French subjunctive."

But Voxa should also recognize that the learner repeatedly avoids or misuses the subjunctive and proactively schedule practice.

---

# 19. Listening Training

Listening activities should support:

- slow speech;
- normal speech;
- fast/native speech;
- replay;
- sentence-by-sentence replay;
- transcript hidden/revealed;
- vocabulary assistance;
- dictation;
- comprehension questions.

Difficulty should evolve through:

- speech speed;
- vocabulary;
- accent;
- background complexity;
- sentence length;
- topic complexity.

Future versions may deliberately expose advanced learners to multiple regional accents.

---

# 20. Adaptive Learner Model

The learner model is the core intellectual property of the product.

For every learner Voxa should maintain estimates for:

- language level;
- speaking;
- listening;
- reading;
- writing;
- grammar;
- vocabulary;
- pronunciation;
- confidence;
- learning velocity;
- retention;
- recurring errors;
- recently learned concepts;
- mastered concepts.

The model should be updated after every meaningful interaction.

## 20.1 Knowledge Units

Skills should be decomposed into knowledge units.

Examples:

```text
French.Grammar.PasseCompose.Avoir
French.Grammar.PasseCompose.Etre
French.Pronunciation.U
French.Pronunciation.R
French.Vocabulary.Food
French.Listening.Numbers
French.Functional.RestaurantOrdering
```

Each unit has a mastery probability or score.

---

# 21. Curriculum Engine

The curriculum engine determines **what the learner should do next**.

Inputs:

```text
Learner profile
        +
Learning objective
        +
Skill graph
        +
Mastery state
        +
Recent performance
        +
Spaced repetition queue
        +
Available study time
        +
Learner preferences
        ↓
Next-best-learning-action
```

The LLM generates the actual experience after the curriculum engine selects the pedagogical objective.

This separation is important.

The LLM should not independently improvise the entire long-term curriculum on every request.

---

# 22. AI Architecture

Voxa should use different OpenAI models for different workloads rather than selecting a single model for the entire product.

The model IDs must remain remotely configurable because the OpenAI model portfolio evolves rapidly. Model changes must not require an iOS release.

## 22.1 Recommended Model Strategy

The production model strategy should optimize three things independently:

1. pedagogical quality;
2. realtime latency;
3. cost.

### Realtime spoken tutoring — primary model

**Default:** `gpt-realtime-2.1`

Use for:

- natural speech-to-speech tutoring;
- live conversation;
- role plays;
- spoken lesson interactions;
- interruption/barge-in;
- tutor tool calling during a live session.

OpenAI's current Realtime documentation explicitly recommends `gpt-realtime-2.1` for low-latency voice agents.

Realtime 2.1 includes reasoning and tool use. For normal conversational tutoring, begin with low reasoning effort and increase only when evaluation shows that a task benefits from it. Excess reasoning can increase latency without improving the learning experience.

### Realtime spoken tutoring — cost-optimized option

**Candidate:** `gpt-realtime-2.1-mini`

Use only after Voxa-specific evaluation confirms acceptable quality for:

- beginner conversation;
- repetitive speaking drills;
- simple role plays;
- pronunciation repetition;
- lower-cost/free-tier voice sessions.

The full `gpt-realtime-2.1` model remains the initial quality baseline.

### Core asynchronous tutor / lesson model

**Default:** `gpt-5.6-terra`

Use for the majority of non-realtime pedagogical operations:

- lesson generation;
- grammar explanations;
- exercise generation;
- correction explanations;
- vocabulary examples;
- structured feedback;
- conversation debriefs;
- adaptive lesson modification.

Reason:

GPT-5.6 Terra is positioned by OpenAI as the balance between intelligence and cost. That is the appropriate default for a consumer language-learning application where accuracy matters but requests occur at high volume.

### Complex curriculum and assessment reasoning

**Default:** `gpt-5.6-sol`

Use selectively for:

- initial placement synthesis;
- long-term curriculum generation;
- difficult learner-state interpretation;
- periodic proficiency reassessment;
- analysis of contradictory learner signals;
- complex language questions;
- generation or validation of language-specific pedagogy;
- evaluation of whether a learner is ready to advance.

Sol should not be used automatically for every request because its higher cost is unnecessary for many routine learning interactions.

### High-volume bounded tasks

**Candidate:** `gpt-5.6-luna`

Use for narrowly scoped operations only after evaluation demonstrates adequate accuracy.

Potential workloads:

- vocabulary-card generation;
- simple classification;
- tagging mistakes to known skill IDs;
- summarization;
- metadata extraction;
- low-risk formatting;
- simple exercise variants.

Do not use Luna as the default teacher merely because it is cheaper.

### Live transcription

**Default where a dedicated transcription stream is required:** `gpt-live-transcribe`

Use when Voxa needs streaming transcript deltas independently from a speech-to-speech tutor session.

Examples:

- live captions;
- explicit dictation mode;
- transcription-only exercises;
- diagnostic capture where no spoken AI response is required.

The production delay/quality configuration must be tested using real learner audio, target languages, accents, microphone conditions, and non-native pronunciation.

### Bounded/file transcription

**Default candidate:** `gpt-transcribe`

Use for:

- uploaded or recorded pronunciation attempts;
- bounded audio exercises;
- asynchronous transcription;
- post-session audio processing when audio retention has been explicitly permitted.

Do not run a separate transcription model during every Realtime voice conversation unless the product requirement justifies the additional complexity and cost.

### Text-to-speech

For the primary spoken tutoring experience, prefer native audio output from the Realtime model.

Dedicated speech-generation models should be used only when Voxa needs standalone generated audio outside a live Realtime session, for example:

- pre-generated listening exercises;
- cached example pronunciation;
- generated audio lessons.

## 22.2 Model Routing Table

| Capability | Initial model | Notes |
|---|---|---|
| Live AI conversation | `gpt-realtime-2.1` | Primary quality baseline |
| Lower-cost live conversation | `gpt-realtime-2.1-mini` | Enable only after evals |
| Routine lessons/tutoring | `gpt-5.6-terra` | Default asynchronous pedagogical model |
| Curriculum/complex assessment | `gpt-5.6-sol` | Use selectively |
| Bounded high-volume utility tasks | `gpt-5.6-luna` | Only after task-specific evals |
| Live transcription | `gpt-live-transcribe` | When a separate transcription session is required |
| Bounded/file transcription | `gpt-transcribe` | Recorded or uploaded audio |
| Standalone speech generation | Current supported speech model | Only when Realtime audio output is not appropriate |

## 22.3 Model Router

The backend must expose logical model capabilities rather than physical model IDs.

Application code should request capabilities such as:

```text
RealtimeTutorModel
TutorModel
CurriculumModel
AssessmentModel
UtilityModel
LiveTranscriptionModel
TranscriptionModel
SpeechGenerationModel
```

Configuration maps each capability to a concrete OpenAI model.

Example:

```json
{
  "RealtimeTutorModel": "gpt-realtime-2.1",
  "TutorModel": "gpt-5.6-terra",
  "CurriculumModel": "gpt-5.6-sol",
  "AssessmentModel": "gpt-5.6-sol",
  "UtilityModel": "gpt-5.6-luna",
  "LiveTranscriptionModel": "gpt-live-transcribe",
  "TranscriptionModel": "gpt-transcribe"
}
```

This allows model upgrades, A/B tests, cost optimization, and emergency rollback without shipping a new mobile application.

## 22.4 Model Selection Must Be Eval-Driven

The model table above is the initial engineering baseline, not a permanent rule.

For every logical capability, maintain Voxa-specific evaluation sets covering:

- multilingual correctness;
- grammar accuracy;
- naturalness;
- learner-level appropriateness;
- non-native speech understanding;
- correction quality;
- instruction following;
- latency;
- cost;
- structured-output reliability.

A cheaper model replaces a more capable model only when evaluation demonstrates that the user experience remains acceptable.



# 23. Realtime Audio Architecture

Low latency is essential to the core Voxa experience.

For iPhone and iPad, the preferred architecture is **direct WebRTC between the mobile client and the OpenAI Realtime API using a short-lived client secret created by the Voxa backend**.

OpenAI's current documentation recommends WebRTC for browser and mobile clients that directly capture and play audio. WebSockets are better suited to server-side media pipelines.

## 23.1 Recommended Realtime Flow

```text
┌─────────────────────────┐
│    iPhone / iPad App    │
│                         │
│ Swift / SwiftUI         │
│ AVFoundation            │
│ WebRTC                  │
└────────────┬────────────┘
             │
             │ 1. Request a Voxa Realtime session
             ▼
┌─────────────────────────┐
│      Voxa Backend       │
│        .NET 10          │
│ Azure Functions         │
│ Flex Consumption        │
└────────────┬────────────┘
             │
             │ 2. POST /v1/realtime/client_secrets
             │    using permanent server credential
             │
             │ 3. Attach privacy-preserving
             │    OpenAI Safety Identifier
             ▼
┌─────────────────────────┐
│       OpenAI API        │
└────────────┬────────────┘
             │
             │ 4. Return short-lived client secret
             ▼
┌─────────────────────────┐
│    iPhone / iPad App    │
└────────────┬────────────┘
             │
             │ 5. Establish WebRTC call
             │    via /v1/realtime/calls
             ▼
┌─────────────────────────┐
│  OpenAI Realtime API    │
│  gpt-realtime-2.1       │
│                         │
│ audio ⇄ audio           │
│ transcript events       │
│ tool calls              │
└─────────────────────────┘
```

## 23.2 Credential Handling

The iPhone/iPad application must **never contain a permanent OpenAI API key**.

The backend owns the permanent OpenAI credential.

For each authorized learner session:

1. the mobile app authenticates to the Voxa backend;
2. the backend validates the user and subscription/usage policy;
3. the backend creates a Realtime client secret through `POST /v1/realtime/client_secrets`;
4. the backend returns only the short-lived credential and allowed session configuration;
5. the mobile app establishes the WebRTC session directly with OpenAI.

The short-lived credential must be treated as ephemeral session material and not persisted.

## 23.3 Why WebRTC

Use WebRTC for the iPhone/iPad live tutoring path because the mobile application directly captures microphone audio and plays generated speech.

Benefits:

- low latency;
- direct audio transport;
- efficient streaming;
- natural interruption handling;
- no requirement to proxy every audio packet through Azure;
- lower backend bandwidth;
- simpler backend scaling.

## 23.4 When to Use WebSockets Instead

Do not use a server-routed WebSocket audio path for normal mobile tutoring.

WebSockets become appropriate if Voxa later adds a server-side media pipeline such as:

- telephone integration;
- recorded media ingest;
- server-side audio transformation;
- broadcast processing;
- a worker that already receives raw audio.

## 23.5 Realtime Session Configuration

The Realtime layer should control:

- model;
- tutor instructions;
- target language;
- learner level;
- correction mode;
- output voice;
- turn detection;
- reasoning effort;
- tool availability;
- conversation context;
- relevant learner weaknesses.

For `gpt-realtime-2.1`, begin with low reasoning effort for ordinary voice tutoring and increase it only when task complexity justifies the latency tradeoff.

## 23.6 Safety Identifier

For identified Voxa users, the backend should send a stable privacy-preserving safety identifier when creating the Realtime session.

Use a hashed/internal derived user identifier rather than directly exposing personal information.

The same logical safety identifier should also be used for other OpenAI API interactions where supported.

## 23.7 Realtime Tools

The Realtime tutor should not receive unrestricted database access.

Expose narrowly scoped server-side tools such as:

```text
get_current_lesson_context
get_relevant_learner_weaknesses
record_learning_event
save_new_vocabulary
record_error
mark_activity_complete
request_deeper_explanation
```

Tool actions that update persistent state remain validated by the Voxa backend.

## 23.8 Separate Transcription Sessions

A normal `gpt-realtime-2.1` conversation should not automatically create an additional live-transcription session.

Use `gpt-live-transcribe` when the product specifically requires a transcription-first workflow such as:

- dictation;
- captioning;
- transcript-only assessment;
- diagnostic speech capture.

This keeps architecture and costs proportionate to the actual learning task.



# 24. High-Level System Architecture

```text
                        ┌─────────────────────────┐
                        │    iPhone / iPad App    │
                        │ Swift / SwiftUI         │
                        │                         │
                        │ Lessons                 │
                        │ Conversation            │
                        │ Audio                   │
                        │ Progress                │
                        │ Reviews                 │
                        └───────────┬─────────────┘
                                    │
                             HTTPS / REST
                                    │
                       ┌────────────▼────────────┐
                       │     Voxa Backend        │
                       │       .NET 10           │
                       │ Azure Functions         │
                       │ Flex Consumption        │
                       │                         │
                       │ API                     │
                       │ Curriculum Engine       │
                       │ Learner Model           │
                       │ Lesson Orchestrator     │
                       │ AI Router               │
                       │ Session Service         │
                       └─────┬───────────┬───────┘
                             │           │
                  ┌──────────▼───┐   ┌──▼────────────────┐
                  │ Persistent   │   │     OpenAI API    │
                  │ Store        │   │                   │
                  │              │   │ GPT               │
                  │ Profiles     │   │ Realtime          │
                  │ Progress     │   │ Transcription     │
                  │ Mastery      │   │ Audio             │
                  └──────────────┘   └───────────────────┘

                       Supporting Azure services
                       ─────────────────────────
                       Key Vault
                       Application Insights
                       Log Analytics
                       Storage Account
```

---

# 25. Azure Infrastructure

The infrastructure should remain deliberately small.

## 25.1 Required Azure Resources

### Resource Group

One resource group per environment initially.

Examples:

```text
rg-voxa-dev
rg-voxa-prod
```

### Azure Functions Flex Consumption

Hosts the .NET 10 backend.

Responsibilities:

- REST APIs;
- authentication integration;
- learner state;
- curriculum;
- AI orchestration;
- lesson generation;
- realtime-session issuance;
- subscription validation;
- usage enforcement.

Why Functions first:

- lowest practical hosted compute footprint for an early mobile MVP;
- event/request driven execution model;
- scale-to-zero/low-idle-cost behavior;
- no container registry required for the initial deployment path;
- simple deployment;
- easy managed identity;
- enough capability for issuing Realtime client secrets, validating subscriptions, recording learning events, and serving learner state;
- consistent with the minimum-cost Azure proxy pattern already proven in Deja Groove.

The MVP backend should be a modular monolith in code even if deployed as a Function App. It should not be split into many independent functions with separate business logic ownership.

The Function App must use a user-assigned managed identity for Azure resource access. It should use outbound virtual network integration to reach private Azure data-plane resources. For the mobile MVP, public HTTPS ingress may remain enabled so iPhone and iPad clients can reach the backend without adding a paid public edge. If Function ingress is made private, the architecture must add an explicit client-access pattern such as Front Door, API Management, App Gateway, or VPN and revalidate cost.

### Azure Container Apps

Azure Container Apps is not the default MVP runtime.

Move to Container Apps only when one or more of the following are proven:

- Azure Functions cold starts materially harm the learner experience;
- the backend requires long-running orchestration not suited to Functions;
- server-side media processing or WebSocket routing becomes a real requirement;
- deployment/runtime constraints make a containerized ASP.NET Core service simpler than Functions;
- sustained traffic makes Container Apps cheaper or operationally clearer than Functions.

### Azure Cosmos DB

Recommended initial persistent database candidate using serverless capacity where available/appropriate.

Stores:

- users;
- learner profiles;
- languages;
- learning objectives;
- lesson history;
- mastery state;
- vocabulary state;
- error history;
- review queue;
- conversation summaries;
- usage metadata.

Reasons:

- minimal administration;
- flexible schema;
- well suited to evolving learner models;
- scalable without database administration.

Cosmos DB is not mandatory until cost and data-shape validation confirms it is the best initial store.

The MVP data decision should compare:

- Cosmos DB Serverless for flexible learner state and event documents;
- Azure Table Storage for the cheapest simple key/value and event-style persistence;
- local development storage for offline engineering workflows.

PostgreSQL should not be introduced for MVP unless relational querying becomes a demonstrated requirement. Deja Groove's move away from PostgreSQL and hosted collection APIs is a useful warning against adding a managed database before the product needs it.

If Cosmos DB is selected, it must be accessed through managed identity/RBAC where supported and private networking in production. Public network access must remain disabled except for explicit, time-bound development exceptions.

### Azure Key Vault

Stores server-side secrets such as:

- OpenAI API credentials;
- App Store server credentials;
- external service credentials.

Secrets are never embedded in the mobile app binary.

The backend must access Key Vault with managed identity and RBAC. Production Key Vault access must be restricted through private endpoint/private DNS unless a temporary development exception is explicitly enabled.

### Azure Storage Account

Required by Azure Functions for host/runtime storage and deployment package storage.

Use standard locally redundant storage. Do not store learner audio or raw transcripts here by default.

Storage account shared key access and blob public access must be disabled. The Function App must use managed identity for runtime/deployment storage access. Production storage access must be through private endpoint/private DNS.

### Azure Container Registry

Not required for the initial Function-based MVP.

Introduce Azure Container Registry only if the backend moves to a containerized runtime such as Azure Container Apps.

### Application Insights / Log Analytics

Used for:

- backend telemetry;
- exceptions;
- performance;
- OpenAI latency;
- model usage;
- lesson failures;
- realtime-session failures;
- cost monitoring.

Telemetry must be sampled and retained for the shortest practical period in dev/test. Logs must not contain raw audio, full transcripts, OpenAI responses, API keys, subscription receipts, or sensitive learner data.

### Virtual Network, Private Endpoints, and Private DNS

The MVP Azure network baseline should be small but private for data-plane services:

- one virtual network per environment;
- one subnet for Azure Functions Flex Consumption outbound integration;
- one subnet for private endpoints;
- private endpoints and private DNS for Storage, Key Vault, and Cosmos DB if Cosmos is enabled.

This is a security requirement, not a signal to add a full enterprise network. Do not add hub-and-spoke networking, firewalls, NAT Gateway, peering, or private ingress services unless a specific threat model or runtime requirement justifies the extra cost.

### CI/CD Bootstrap Identity

GitHub Actions Azure access must be bootstrapped through code, not portal-only setup.

The repository should include subscription-scoped Bicep that creates:

- pipeline identity resource group;
- user-assigned managed identity for GitHub Actions;
- GitHub OIDC federated credential scoped to the main branch deployment workflow;
- target environment resource group;
- resource-group-scoped RBAC for deployment.

Do not store Azure client secrets in GitHub. The GitHub workflow should use OIDC and repository secrets for the managed identity client ID, tenant ID, subscription ID, target location, target resource group, and OpenAI API key.

## 25.2 Explicitly Not Required Initially

Do not introduce the following until justified:

- AKS;
- Service Bus;
- Redis;
- API Management;
- Azure AI Search;
- Event Grid;
- Event Hubs;
- dedicated vector database;
- Kubernetes;
- multi-region active-active;
- complex microservices;
- data lake.

Also do not introduce Container Apps or Azure Container Registry until the upgrade triggers above are met.

The MVP backend should be a **modular monolith**.

---

# 26. Backend Architecture

Technology:

- .NET 10;
- ASP.NET Core;
- REST APIs;
- OpenAI SDK/API integration;
- persistent-store SDK/client;
- OpenTelemetry/Application Insights;
- Docker.

Suggested logical modules:

```text
Voxa.Api
Voxa.Auth
Voxa.Users
Voxa.Languages
Voxa.Learners
Voxa.Curriculum
Voxa.Lessons
Voxa.Conversations
Voxa.Pronunciation
Voxa.Vocabulary
Voxa.Grammar
Voxa.Review
Voxa.Assessment
Voxa.AI
Voxa.Subscriptions
Voxa.Telemetry
```

These should initially deploy as one application.

Do not create independent microservices unless scaling or ownership requirements make that necessary later.

---

# 27. iPhone and iPad Architecture

Technology:

- Swift;
- SwiftUI;
- async/await;
- AVFoundation;
- URLSession;
- StoreKit 2;
- SwiftData or local SQLite/cache where appropriate.

Voxa must support both iPhone and iPad from the initial product architecture.

The experience should feel native on each device:

- iPhone optimized for quick daily practice, voice conversation, and review;
- iPad optimized for longer lessons, reading/writing, progress review, and richer lesson layouts;
- shared SwiftUI feature modules where practical;
- adaptive layouts rather than separate product behavior.

## 27.1 Cross-Device Session Continuity

A learner must be able to start on iPhone and continue on iPad, or start on iPad and continue on iPhone, without losing learning context.

This means Voxa must persist server-side:

- current learning plan;
- current lesson state;
- active or recently completed lesson checkpoint;
- conversation summaries;
- review queue;
- mastery updates;
- vocabulary state;
- recurring errors;
- subscription/usage state;
- user preferences.

When the user opens Voxa on another device, the app should restore the latest meaningful learning checkpoint.

Examples:

- continue the same lesson at the next unfinished activity;
- resume the same daily plan;
- preserve completed review items;
- preserve conversation debriefs and extracted corrections;
- keep subscription and usage limits consistent across devices.

Realtime voice sessions themselves do not need to move live between devices. If a live conversation is active on iPhone and the user later opens iPad, the iPad should receive the finalized conversation summary and updated learner state after the session completes.

Local device storage is a cache, not the source of truth for learner progress.

Conflict handling should be simple for MVP:

- each learning event has a server timestamp and idempotency key;
- completed activities are append-only events;
- mastery updates are derived server-side from accepted events;
- the latest valid lesson checkpoint wins only for resumable UI position;
- never lose completed learning events because of device switching.

Suggested modules:

```text
App
Authentication
Onboarding
Home
Tutor
Conversation
Lessons
Pronunciation
Vocabulary
Grammar
Reading
Writing
Review
Progress
Profile
Subscription
Audio
Networking
Persistence
DesignSystem
```

Recommended application architecture:

- feature-oriented;
- MVVM or similarly explicit state-management pattern;
- dependency injection;
- protocol-based networking/services;
- testable business logic.

---

# 28. Core Application Screens

## 28.1 Home / Today

The home screen answers:

> "What should I do now?"

Example:

```text
Good evening.

French — B1

Today's plan                         24 min

Continue
Past tense in conversation           8 min

Speak
At a Paris restaurant                7 min

Pronunciation
u vs ou                              4 min

Review
12 items due                         5 min
```

Primary CTA:

**Start today's lesson**

## 28.2 Talk

Large, minimal conversational UI.

Should include:

- AI speaking state;
- learner speaking state;
- transcript toggle;
- live translation toggle;
- correction indicator;
- pause;
- slower;
- repeat;
- end conversation.

The UI should not resemble a messaging application unless transcript mode is explicitly selected.

## 28.3 Learn

Displays the personalized curriculum.

Not a generic fixed tree.

## 28.4 Review

Shows material currently due for retrieval practice.

## 28.5 Progress

Shows genuine proficiency metrics rather than only XP.

Examples:

- overall CEFR estimate;
- speaking;
- listening;
- vocabulary;
- grammar;
- pronunciation;
- weekly study;
- active vocabulary;
- weak skills;
- milestones.

---

# 29. AI-Generated Learning Plan

The user should be able to inspect their plan.

Example:

```text
Goal
Conversational B2 French

Current level
A2+

Estimated path
8–12 months at 30 minutes/day

Current phase
Building spontaneous everyday speech

This month
✓ reinforce passé composé
✓ introduce imparfait
✓ increase active vocabulary to 1,800 words
✓ improve /y/ pronunciation
✓ understand everyday speech at normal speed

This week
Monday      past tense conversation
Tuesday     listening + vocabulary
Wednesday   pronunciation + role play
Thursday    grammar consolidation
Friday      free conversation
Saturday    review
Sunday      assessment
```

The plan is continuously updated.

---

# 30. Assessment System

Assessment should happen continuously.

Signals include:

- successful recall;
- response latency;
- conversation errors;
- pronunciation attempts;
- listening comprehension;
- writing errors;
- grammar exercise results;
- repeated hints;
- use of translation;
- vocabulary retrieval.

Dedicated checkpoint assessments should also exist.

Examples:

- weekly mini-assessment;
- monthly proficiency assessment;
- milestone challenge.

---

# 31. Error Memory

Voxa should remember meaningful mistakes.

Example internal record:

```json
{
  "language": "fr",
  "category": "grammar",
  "skill": "depuis_present_tense",
  "occurrences": 4,
  "lastOccurrence": "2026-08-24",
  "severity": "medium",
  "mastery": 0.42
}
```

When the same error recurs, the curriculum engine increases remediation priority.

This allows Voxa to say:

> "You've made the same `depuis` tense error several times this week. Let's fix it properly."

---

# 32. Memory Strategy

Do not send the learner's entire history to the LLM.

Maintain structured state.

Each AI interaction receives only relevant context:

```text
User objective
Current ability
Current lesson
Relevant mastery units
Relevant recurring errors
Recent vocabulary
Recent conversation summary
Tutor behavior preferences
```

Long conversations should be summarized.

This controls:

- token use;
- latency;
- privacy;
- model distraction.

---

# 33. Personalization

Voxa should learn user preferences such as:

- correction frequency;
- desired difficulty;
- preferred speech speed;
- preferred lesson duration;
- topics of interest;
- formal vs informal speech;
- tolerance for native-language explanations;
- preferred daily learning time.

Content can then reflect interests.

Someone interested in technology should encounter technology-related vocabulary.

Someone moving to France should encounter:

- apartment rental;
- banking;
- administration;
- restaurants;
- transport;
- workplace conversations.

---

# 34. Tutor Personalities

The product may offer different teaching styles without changing underlying pedagogy.

Examples:

### Supportive

More explanation and encouragement.

### Direct

Minimal praise; immediately identifies weaknesses.

### Immersive

Avoids native-language explanations.

### Intensive

High correction rate and aggressive progression.

This is a UX preference rather than separate AI agents.

---

# 35. Motivation and Gamification

Useful mechanics:

- streak;
- weekly target;
- milestones;
- skill progress;
- conversation minutes;
- active vocabulary count;
- proficiency progression;
- challenge completion.

Avoid:

- meaningless currencies;
- excessive animations;
- manipulative notification patterns;
- progression disconnected from actual learning.

The strongest reward should be:

> "You can now do something in this language that you could not do last month."

---

# 36. Notifications

Optional notifications:

- daily lesson available;
- review due;
- streak reminder;
- weekly progress report;
- milestone achieved;
- "You haven't spoken French in four days."

Notifications must be user-configurable.

---

# 37. Authentication

Recommended initial options:

- Sign in with Apple;
- email-based account if required later.

Sign in with Apple should be the primary authentication path on iPhone and iPad.

The backend should issue its own application session/access tokens after identity validation.

Authentication architecture should remain independent from the AI provider.

Accounts must be device-independent.

A learner signing in with the same account on iPhone and iPad must see the same:

- learning plan;
- progress;
- active lesson checkpoint;
- review queue;
- vocabulary and error history;
- subscription entitlement;
- usage limits.

Device-specific state should be limited to local cache, audio permissions, downloaded content, and UI preferences that are intentionally local.

---

# 38. Subscription and Monetization

Recommended model:

## Free

- onboarding;
- placement assessment;
- limited daily lessons;
- limited conversation minutes;
- progress tracking.

## Voxa Pro

- unlimited or high-limit AI lessons;
- larger conversation allowance;
- advanced pronunciation;
- personalized curriculum;
- detailed progress;
- advanced roleplays;
- exam preparation;
- extended history.

Because realtime audio has a materially higher marginal cost than text interactions, subscription design must include usage economics.

StoreKit 2 should manage Apple subscriptions.

The backend must verify subscription state.

---

# 39. Cost Management

AI cost must be treated as a product requirement.

Strategies:

- use high-end models only where pedagogically valuable;
- use lower-cost models for routine generation;
- keep prompts compact;
- store structured learner state;
- summarize long conversations;
- cap context;
- track AI cost per user;
- track AI cost per lesson;
- track realtime audio minutes;
- allow model changes through configuration;
- cache static explanations where appropriate.

Metrics:

```text
AI cost / DAU
AI cost / paid user
AI cost / lesson
AI cost / conversation minute
AI cost / retained subscriber
```

Azure infrastructure cost must also be treated as a product requirement.

For MVP, the default posture is:

- no always-on compute unless proven necessary;
- no container registry unless a container runtime is selected;
- no API Management;
- private networking limited to one small VNet, two subnets, and private endpoints for required data-plane services;
- no managed cache;
- no queue or message bus unless async processing is required;
- shortest practical telemetry retention;
- budget alerts before wider TestFlight/public beta usage.

Required Azure cost metrics:

```text
Azure cost / environment / month
Azure cost / active learner
Function executions / active learner
Data-store cost / active learner
Telemetry ingestion GB / month
Key Vault operations / month
Private endpoint cost / environment / month
Private DNS zone cost / environment / month
```

Before public beta, the team must produce a simple cost model covering:

- 100 active learners;
- 1,000 active learners;
- expected free-tier usage;
- expected paid-tier usage;
- worst-case realtime abuse scenario;
- expected telemetry ingestion.

---

# 40. Privacy

Voice and language-learning data can be sensitive.

Principles:

- do not persist raw microphone audio by default;
- explicitly request consent before retaining recordings;
- store only what is needed for the learning experience;
- allow deletion of account and learning history;
- document AI processing clearly;
- encrypt data in transit and at rest;
- never expose server credentials to the client.

Conversation summaries and learning events should normally be retained rather than raw audio.

---

# 41. Security

Requirements:

- HTTPS only;
- OpenAI permanent credentials backend-only;
- short-lived realtime session credentials;
- Key Vault for secrets;
- user-assigned managed identity for backend Azure resource access;
- RBAC instead of connection strings or account keys where Azure services support it;
- private endpoints and private DNS for Azure data-plane resources in production;
- public network access disabled for Storage, Key Vault, and Cosmos DB in production;
- rate limiting;
- request validation;
- abuse controls;
- server-side subscription enforcement;
- telemetry without unnecessary sensitive content;
- dependency scanning;
- secure CI/CD;
- no credentials committed to Git.

---

# 42. Observability

Track:

## Application

- crashes;
- API latency;
- session failures;
- lesson generation failures;
- realtime connection failures.

## AI

- model;
- tokens;
- audio duration;
- latency;
- cost;
- tool errors;
- moderation/safety events.

## Learning

- lessons completed;
- conversation minutes;
- retention;
- mastery growth;
- recurring errors;
- pronunciation improvement;
- assessment changes.

## Product

- DAU;
- WAU;
- D1/D7/D30 retention;
- trial conversion;
- subscription churn;
- daily study minutes;
- lesson completion;
- conversation adoption.

---

# 43. Analytics Events

Example events:

```text
onboarding_started
onboarding_completed
placement_started
placement_completed
learning_plan_created
lesson_started
lesson_completed
conversation_started
conversation_completed
pronunciation_attempt
pronunciation_improved
review_item_completed
milestone_completed
subscription_started
subscription_cancelled
```

Learning telemetry and commercial analytics must remain logically separate.

---

# 44. Offline Behavior

Core AI functionality requires connectivity.

However, the application should cache:

- current lesson state;
- recently learned vocabulary;
- learning plan;
- progress;
- downloaded explanations;
- review items where possible.

A later version may support offline review exercises.

Offline work must synchronize safely when connectivity returns.

For MVP, offline behavior should be conservative:

- allow cached review and reading where possible;
- queue completed local review events with idempotency keys;
- sync queued events to the backend before recalculating mastery;
- show stale-state indicators if the device has not synced recently;
- avoid allowing long offline generated lessons that could diverge from server-side learner state.

---

# 45. Accessibility

Requirements:

- VoiceOver support;
- Dynamic Type;
- adequate contrast;
- subtitles/transcripts;
- adjustable speech speed;
- visual alternatives to audio cues;
- reduced-motion support;
- configurable font sizing for non-Latin scripts.

---

# 46. Initial MVP

The MVP must prove the central hypothesis:

> **An adaptive AI tutor can create a meaningfully better language-learning experience than a fixed lesson application.**

## MVP Features

### Required

- iPhone and iPad application;
- Sign in with Apple;
- target-language selection;
- learner onboarding;
- AI placement assessment;
- personalized curriculum;
- generated daily lessons;
- vocabulary;
- grammar;
- reading;
- listening;
- voice conversation;
- pronunciation practice;
- immediate corrections;
- learner mastery model;
- recurring-error tracking;
- spaced repetition;
- progress dashboard;
- subscription support;
- cross-device session continuity between iPhone and iPad;
- backend analytics;
- OpenAI cost monitoring.

### MVP Language Recommendation

Start with:

**French for English speakers**

Reasons:

- sufficiently complex pronunciation and grammar to test the architecture;
- Latin script avoids introducing script-learning complexity in the first implementation;
- excellent test case for speaking, listening, gender, conjugation, liaison, and pronunciation.

Then add Spanish and German.

Japanese should follow once the core learning architecture is stable because it introduces a substantially different writing-system and pedagogy requirement.

---

# 47. Phase 2

Potential additions:

- more languages;
- specialist pronunciation engine;
- video/image-based lessons;
- camera-based object learning;
- handwriting practice;
- regional accents;
- exam preparation;
- downloadable offline lessons;
- richer cultural content;
- live contextual translation;
- AI-generated stories;
- news-based lessons;
- podcasts generated for the learner;
- watch/listen comprehension from imported content;
- widgets;
- Apple Watch practice;
- Siri/App Intents;
- family plans.

---

# 48. Phase 3 Vision

Longer-term capabilities may include:

## Real-world companion mode

User wears AirPods while travelling.

Voxa can provide optional assistance such as:

- preparing the user before an interaction;
- explaining something they just heard;
- reviewing mistakes after a conversation;
- generating vocabulary from the experience.

## Personal immersion environment

Voxa generates:

- conversations;
- stories;
- news;
- exercises;
- listening material;
- role plays;

entirely at the learner's current level.

## Multi-modal learning

The learner points the camera at an object or environment and asks:

> "Teach me the words I need here."

## Cultural tutor

Teach:

- etiquette;
- register;
- humor;
- politeness;
- gestures;
- regional differences;
- when technically correct language sounds unnatural.

---

# 49. Explicit Non-Goals for MVP

Do not initially build:

- Android;
- web application;
- social network;
- tutor marketplace;
- user-generated courses;
- classroom LMS;
- enterprise administration;
- multiplayer games;
- complex avatars;
- metaverse environments;
- Kubernetes infrastructure;
- custom foundation models.

These can distract from proving the core tutoring experience.

---

# 50. API Surface

Indicative backend endpoints:

```text
POST   /api/auth/apple
GET    /api/me

POST   /api/onboarding
POST   /api/assessment/start
POST   /api/assessment/{id}/answer
GET    /api/assessment/{id}/result

GET    /api/learning-plan
POST   /api/learning-plan/regenerate

GET    /api/today
POST   /api/lessons
GET    /api/lessons/{id}
POST   /api/lessons/{id}/events
POST   /api/lessons/{id}/complete
GET    /api/lessons/{id}/checkpoint
PUT    /api/lessons/{id}/checkpoint

POST   /api/realtime/session
POST   /api/conversations
POST   /api/conversations/{id}/complete

POST   /api/pronunciation/evaluate

GET    /api/review
POST   /api/review/{id}/result

GET    /api/progress
GET    /api/mastery
GET    /api/session/resume
POST   /api/sync/events

GET    /api/subscription
POST   /api/subscription/apple/events
```

Exact endpoint design will be refined during technical design.

---

# 51. Core Data Model

Indicative entities:

```text
User
LearnerProfile
Device
UserSession
Language
LearningGoal
LearningPlan
LearningMilestone
Skill
SkillMastery
Lesson
LessonActivity
LessonAttempt
LessonCheckpoint
Conversation
ConversationSummary
ErrorEvent
VocabularyItem
VocabularyMastery
PronunciationTarget
PronunciationAttempt
ReviewItem
LearningEvent
Assessment
AssessmentResult
Subscription
UsageRecord
```

The durable data model must distinguish authoritative server state from device-local cache.

Authoritative server-owned state:

- learner profile;
- learning plan;
- lesson checkpoints;
- learning events;
- mastery state;
- review schedule;
- conversation summaries;
- subscription entitlement;
- usage records.

Device-local cache:

- recently viewed lessons;
- downloaded explanations;
- temporary audio buffers;
- local UI state;
- queued offline review events waiting for sync.

---

# 52. Example Learner State

```json
{
  "targetLanguage": "fr",
  "nativeLanguage": "en",
  "overallLevel": "A2",
  "goal": {
    "type": "conversational",
    "targetLevel": "B2",
    "minutesPerDay": 30
  },
  "skills": {
    "speaking": 0.43,
    "listening": 0.56,
    "reading": 0.69,
    "writing": 0.42,
    "grammar": 0.51,
    "vocabulary": 0.57,
    "pronunciation": 0.39
  },
  "weaknesses": [
    "French.Pronunciation.U",
    "French.Grammar.Depuis",
    "French.Grammar.PasseCompose.Etre"
  ]
}
```

---

# 53. Lesson Orchestration Flow

```text
User starts session
        │
        ▼
Load learner state
        │
        ▼
Load due review items
        │
        ▼
Evaluate current learning plan
        │
        ▼
Curriculum engine selects objectives
        │
        ▼
Lesson orchestrator creates lesson
        │
        ▼
User performs activities
        │
        ▼
AI evaluates responses
        │
        ▼
Record learning events
        │
        ▼
Update mastery
        │
        ▼
Schedule future review
        │
        ▼
Update learning plan if necessary
```

---

# 54. Conversation Completion Flow

After a conversation:

1. conversation ends;
2. transcript is finalized;
3. AI extracts significant errors;
4. errors are mapped to skills;
5. new vocabulary is identified;
6. pronunciation issues are recorded;
7. learner mastery is updated;
8. relevant review items are created;
9. conversation is summarized;
10. raw temporary audio is discarded unless explicitly retained;
11. learner receives a concise debrief.

Example debrief:

```text
12:34 conversation
92% target language

You did well:
- ordering naturally
- numbers
- polite requests

Work on:
- "je voudrais" pronunciation
- du/de la/des
- answering without translating first

New expressions:
- sur place
- à emporter
- ça sera tout
```

---

# 55. Testing Strategy

Development must use automated testing extensively.

## Backend

- unit tests;
- curriculum-engine tests;
- learner-state tests;
- model-router tests;
- API integration tests;
- persistent-store integration tests;
- OpenAI contract tests using mocked responses;
- prompt regression tests.

## iPhone / iPad

- unit tests;
- ViewModel/state tests;
- API client tests;
- audio-state tests;
- UI tests;
- snapshot tests where useful.

## AI Evaluation

Traditional unit tests are insufficient for generative behavior.

Maintain evaluation datasets for:

- grammar correction;
- vocabulary explanation;
- lesson generation;
- level appropriateness;
- pronunciation feedback;
- conversation behavior;
- placement accuracy;
- multilingual correctness.

Each model/prompt change should be evaluated against these datasets before production.

---

# 56. AI Quality Requirements

The AI must not:

- teach fabricated grammar rules;
- confidently invent word meanings;
- incorrectly "correct" valid regional language;
- assume one accent is inherently superior;
- overwhelm beginners with explanation;
- continually interrupt natural conversation;
- advance difficulty before mastery;
- simplify advanced learners indefinitely.

AI output should distinguish:

- incorrect;
- technically correct but unnatural;
- uncommon;
- formal;
- informal;
- dialectal;
- regional.

That distinction is particularly important for advanced learners.

---

# 57. Product Metrics

## North-Star Metric

**Meaningful target-language communication minutes per active learner per week.**

This aligns product usage with the intended outcome.

Supporting metrics:

- speaking minutes/week;
- lessons/week;
- weekly active learners;
- mastery gain;
- vocabulary retention;
- recurring-error reduction;
- pronunciation-error reduction;
- D7/D30 retention;
- free-to-paid conversion.

---

# 58. MVP Acceptance Criteria

The MVP is successful when a new user can:

1. install Voxa on iPhone or iPad;
2. authenticate;
3. select French;
4. specify a learning goal;
5. complete an adaptive placement assessment;
6. receive a personalized learning plan;
7. complete an AI-generated lesson;
8. speak naturally with Voxa;
9. receive useful corrections;
10. practice pronunciation;
11. receive vocabulary and grammar review;
12. see skill-specific progress;
13. return the next day and have Voxa remember what was learned;
14. move between iPhone and iPad and resume from the latest meaningful learning checkpoint;
15. receive a lesson materially influenced by previous performance.

The last requirement is critical.

Without persistent adaptive behavior, Voxa is merely an LLM interface.

---

# 59. Key Technical Risks

## Realtime latency

Conversation becomes unpleasant if response latency is excessive.

**Mitigation:** direct client-to-OpenAI realtime connection using temporary credentials where supported.

## Pronunciation diagnosis

Speech recognition accuracy is not equivalent to pronunciation assessment.

**Mitigation:** benchmark the MVP carefully; introduce a specialized pronunciation-analysis service only if necessary.

## Hallucinated language instruction

An LLM can occasionally provide incorrect explanations.

**Mitigation:** evaluation datasets, structured language definitions, quality monitoring, and deterministic curriculum rules for core concepts.

## Cost

Long realtime conversations can be expensive.

**Mitigation:** model routing, usage quotas, subscription economics, prompt/context control, and continuous cost telemetry.

Hosted Azure infrastructure can also become more expensive than the MVP justifies.

**Mitigation:** start with Functions Flex Consumption, avoid always-on compute, avoid ACR unless containers are required, validate the data store against a monthly cost target, and enforce budget alerts before public beta.

## Curriculum drift

A purely generative tutor may repeatedly jump between topics.

**Mitigation:** structured curriculum engine and persistent skill graph separate from the LLM.

## User dependency on translation

AI can make translation too convenient.

**Mitigation:** gradually reduce translation availability and encourage target-language reasoning as proficiency increases.

---

# 60. Architectural Principles

The engineering team must follow these principles.

1. **AI models are replaceable dependencies.**
2. **The learner model belongs to Voxa, not to the LLM context window.**
3. **Curriculum state is structured and persisted.**
4. **Realtime audio takes the shortest practical network path.**
5. **Never expose permanent server credentials to the mobile app.**
6. **Start with a modular monolith.**
7. **Do not introduce infrastructure without a demonstrated requirement.**
8. **Model quality must be measured through evaluation, not intuition.**
9. **Learning outcomes matter more than engagement tricks.**
10. **Every significant interaction should improve Voxa's understanding of the learner.**

---

# 61. Development Environments

Initial environments:

```text
Local
Dev
Prod
```

Preproduction can be added when release complexity warrants it.

## Local Development

Local development should require as little Azure infrastructure as possible.

Recommended:

```text
iOS/iPadOS Simulator / physical iPhone or iPad
        │
        ▼
Local .NET 10 backend / Functions host
        │
        ├── OpenAI API
        │
        └── local development store
```

Developers should be able to develop most features without deploying Azure resources continuously.

## Dev

Shared Azure environment for integrated testing.

## Prod

Production application and data.

---

# 62. Infrastructure as Code

All Azure infrastructure must be provisioned using Bicep.

Suggested structure:

```text
infra/
├── main.bicep
├── modules/
│   ├── functions.bicep
│   ├── storage.bicep
│   ├── data-store.bicep
│   ├── key-vault.bicep
│   └── monitoring.bicep
└── parameters/
    ├── dev.bicepparam
    └── prod.bicepparam
```

No production infrastructure should depend on manually created portal resources.

---

# 63. CI/CD

Recommended repository structure:

```text
/
├── ios/
├── backend/
├── infra/
├── tests/
├── evals/
└── docs/
```

Pipeline stages:

```text
Commit
  ↓
Build
  ↓
Unit Tests
  ↓
AI Evaluations
  ↓
Function Package
  ↓
Security Scan
  ↓
Deploy Dev
  ↓
Integration Tests
  ↓
Deploy Prod
```

Apple platform releases should use an appropriate App Store/TestFlight deployment workflow.

---

# 64. Design Direction

The application should feel:

- sophisticated;
- calm;
- premium;
- human;
- extremely responsive;
- conversation-oriented;
- unmistakably AI-native.

Avoid the visual language of children's educational software.

Avoid:

- cartoon mascots as the primary identity;
- excessive badges;
- cluttered curriculum maps;
- childish rewards;
- constant celebratory animation.

The primary experience should feel closer to a premium personal tutor than a mobile game.

---

# 65. Brand Direction

Working name:

# **Voxa**

Derived from the association with *vox* — voice.

Potential positioning lines:

> **Voxa — Learn a language by living it.**

> **Voxa — Learn to actually speak.**

> **Voxa — Your personal AI language tutor.**

> **Voxa — From first word to real conversation.**

The final name must undergo:

- trademark search;
- App Store search;
- domain availability check;
- social-handle search;
- linguistic screening across major languages.

Voxa should therefore remain a working name until those checks are complete.

---

# 66. Strategic Differentiator

The central differentiator is not speech synthesis, chat, grammar exercises, or lesson generation individually.

It is the closed learning loop:

```text
TEACH
  ↓
LISTEN
  ↓
OBSERVE
  ↓
DIAGNOSE
  ↓
REMEMBER
  ↓
ADAPT
  ↓
REVIEW
  ↓
ASSESS
  ↓
TEACH WHAT IS NEEDED NEXT
```

Every conversation and lesson changes the model of the learner.

Every change to the learner model changes what Voxa teaches next.

That feedback loop is the heart of the product.

---

# 67. Final Product Statement

Voxa should not ask users to navigate thousands of predetermined exercises until they eventually become competent.

The user gives Voxa an objective:

> **"Teach me French."**

Voxa determines:

- where they are;
- where they need to go;
- what they need to learn;
- what they have forgotten;
- how they need to practice;
- when they need review;
- when they are ready to advance.

It then teaches them through explanation, conversation, listening, pronunciation, reading, writing, correction, repetition, and real-world simulation.

The intended end state is not:

> "I completed Voxa."

It is:

> **"I can speak the language."**

---

# 68. Recommended First Build

The first implementation should deliberately remain narrow:

**Target:** English-speaking learner studying French.

Build, in this order:

1. learner profile and onboarding;
2. placement assessment;
3. skill/mastery model;
4. curriculum engine;
5. generated lesson framework;
6. realtime voice conversation;
7. correction extraction;
8. pronunciation practice;
9. spaced repetition;
10. progress dashboard;
11. cross-device session continuity;
12. subscription;
13. production telemetry.

If this loop works well for one language pair, additional languages become a controlled expansion problem.

If this loop does not work well, adding twenty languages will not fix the product.

---

# 69. Open Product Decisions

The following require prototype testing rather than assumption:

1. Whether `gpt-realtime-2.1` or a lower-cost realtime model provides the best conversation economics.
2. Whether model-based pronunciation assessment is sufficiently reliable for detailed coaching.
3. Whether the initial persistent store should be Cosmos DB Serverless, Azure Table Storage, or another low-cost durable option.
4. Exact correction frequency defaults.
5. Exact free-tier realtime voice allowance.
6. Whether curriculum generation should be fully dynamic or hybrid with expert-authored curriculum templates.
7. How aggressively the learner's native language should be phased out.
8. Whether CEFR estimates should be visible continuously or only after formal checkpoints.
9. Which language should follow French after MVP validation.
10. Exact iPhone-to-iPad resume behavior for partially completed lessons and interrupted conversations.
11. Whether the name **Voxa** is commercially available.

These should be treated as explicit experiments during product development rather than prematurely fixed assumptions.

---

# 70. Current Recommended Technical Baseline

```text
Client
  iPhone
  iPad
  Swift
  SwiftUI
  AVFoundation
  StoreKit 2

Backend
  .NET 10
  Azure Functions / ASP.NET Core-compatible application layer
  Modular monolith
  Serverless Function deployment first

AI
  OpenAI Responses API
  gpt-5.6-terra — routine tutoring and lesson generation
  gpt-5.6-sol — curriculum and complex assessment
  gpt-5.6-luna — bounded high-volume tasks after evals
  OpenAI Realtime API
  gpt-realtime-2.1 — primary live voice tutor
  gpt-realtime-2.1-mini — cost-optimized candidate after evals
  gpt-live-transcribe — dedicated live transcription when required
  gpt-transcribe — bounded/file transcription
  Configurable capability-based model router

Azure
  Azure Functions Flex Consumption
  Azure Storage Account
  Cosmos DB Serverless or cheapest validated durable store
  Key Vault
  User-assigned Managed Identity
  Virtual Network with minimal subnets
  Private Endpoints / Private DNS for data-plane resources
  Application Insights / Log Analytics
  Container Apps only after upgrade triggers
  Container Registry only if container runtime is selected

Infrastructure
  Bicep
  Subscription-scoped bootstrap Bicep for GitHub Actions OIDC identity

Architecture principle
  Minimal, cost-gated infrastructure with private data-plane access and managed identity by default
```

This baseline should be considered the starting architecture for Voxa.

---

# Appendix A — Current OpenAI Model Baseline

The OpenAI model landscape changes frequently, so Voxa must never depend structurally on a particular model identifier.

As reviewed against the OpenAI API documentation on 26 August 2026, the recommended starting baseline is:

```text
Live speech-to-speech tutor
    gpt-realtime-2.1

Cost-optimized live tutor candidate
    gpt-realtime-2.1-mini

Routine pedagogical generation
    gpt-5.6-terra

Complex curriculum / assessment reasoning
    gpt-5.6-sol

Bounded high-volume utility operations
    gpt-5.6-luna

Dedicated live transcription
    gpt-live-transcribe

Bounded/file transcription
    gpt-transcribe
```

OpenAI currently positions:

- GPT-5.6 Sol as the flagship model for complex reasoning and coding;
- GPT-5.6 Terra as the balance between intelligence and cost;
- GPT-5.6 Luna for cost-sensitive, high-volume workloads;
- GPT-Realtime-2.1 for low-latency voice agents;
- GPT-Live-Transcribe for live streaming transcription.

For Voxa, this maps naturally to a tiered architecture:

```text
                         ┌──────────────────────┐
                         │ gpt-5.6-sol          │
                         │ Hard reasoning       │
                         │ Curriculum           │
                         │ Assessment           │
                         └──────────┬───────────┘
                                    │
                         ┌──────────▼───────────┐
                         │ gpt-5.6-terra        │
                         │ Main async tutor     │
                         │ Lessons              │
                         │ Explanations         │
                         └──────────┬───────────┘
                                    │
                         ┌──────────▼───────────┐
                         │ gpt-5.6-luna         │
                         │ Bounded utilities    │
                         │ High volume          │
                         └──────────────────────┘


iPhone / iPad microphone
       │
       │ WebRTC
       ▼
┌─────────────────────────────┐
│ gpt-realtime-2.1            │
│ Live speech-to-speech tutor │
└─────────────────────────────┘
```

The final production routing must be based on Voxa-specific evaluations measuring:

- multilingual accuracy;
- learner-accent understanding;
- realtime latency;
- interruption handling;
- pronunciation-feedback quality;
- grammar correctness;
- pedagogical quality;
- structured-output reliability;
- cost per lesson;
- cost per learning minute.

Model selection is therefore a runtime configuration and evaluation concern, not a permanent architecture decision.

---

# Appendix B — OpenAI Realtime Implementation Notes

For the iPhone/iPad application:

```text
Transport:
    WebRTC

Session credential:
    Short-lived client secret

Client-secret endpoint:
    POST /v1/realtime/client_secrets

WebRTC call endpoint:
    /v1/realtime/calls

Primary model:
    gpt-realtime-2.1
```

Do not build a new implementation around the old beta Realtime interface.

Use the current GA session/event model and current Realtime API event names.

The backend should also associate each Realtime session with a privacy-preserving OpenAI safety identifier.

The Realtime connection is primarily a conversation transport and tutor runtime. Durable learner state remains owned by Voxa and is persisted through validated backend operations.

---


# Appendix C — Product Principle in One Sentence

> **Voxa is an AI tutor that continuously learns how you learn, remembers what you know and what you struggle with, and decides what you need to do next until you can genuinely use the language.**
