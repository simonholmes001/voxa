# Voxa API Contracts

This document defines the first mobile-facing backend contract surfaces for iPhone and iPad clients. DTOs are provider-neutral: they do not expose OpenAI, Azure, storage, or deployment implementation details.

## Common Rules

- Base path: `/api`.
- Authentication: every endpoint requires the authenticated Voxa user context. The backend resolves tenant and user scope from verified auth claims.
- Correlation IDs: clients send `X-Correlation-Id`; the backend echoes it in responses and errors. If omitted, the backend creates one.
- Idempotency: mutating endpoints accept `Idempotency-Key`; repeated requests with the same key must not duplicate side effects.
- Concurrency: learner-state mutations use `If-Match` or an equivalent expected version value.
- Retry behavior: `429`, `502`, `503`, and `504` are retryable with backoff. Validation, auth, and concurrency errors are not retryable without user or client state changes.
- Error shape:

```json
{
  "code": "validation_error",
  "message": "Target language is required.",
  "correlationId": "corr-123",
  "retryable": false
}
```

## App Sessions

`POST /api/auth/apple`

Exchanges Sign in with Apple proof for Voxa app-session tokens. Apple identity tokens and authorization codes are accepted only by the backend and are never echoed in responses.

```json
{
  "identityToken": "apple-id-token",
  "authorizationCode": "authorization-code",
  "nonce": "nonce-123"
}
```

Response `200`:

```json
{
  "correlationId": "corr-123",
  "tenantId": "tenant-default",
  "userId": "user-apple-subject",
  "accessToken": "app-access-token",
  "refreshToken": "app-refresh-token",
  "expiresAt": "2026-08-29T08:15:00Z",
  "refreshTokenExpiresAt": "2026-09-28T08:15:00Z"
}
```

`POST /api/auth/refresh`

Rotates a valid refresh token and returns a new app-session token pair. Unknown, revoked, or expired refresh tokens return `401`.

```json
{
  "refreshToken": "app-refresh-token"
}
```

`POST /api/auth/logout`

Revokes the supplied refresh token. Access tokens naturally expire; clients must discard local session state on success.

```json
{
  "refreshToken": "app-refresh-token"
}
```

## Onboarding

`POST /api/onboarding`

Creates or updates the learner profile and initial learning plan.

```json
{
  "targetLanguage": "fr",
  "nativeLanguage": "en",
  "proficiencyLevel": "A1",
  "goals": ["travel", "conversation"],
  "dailyMinutes": 15
}
```

Response `200`:

```json
{
  "profile": {
    "targetLanguage": "fr",
    "nativeLanguage": "en",
    "proficiencyLevel": "A1"
  },
  "activePlan": {
    "planId": "plan-1",
    "title": "Survival French",
    "knowledgeUnitIds": ["greetings"]
  },
  "version": 1,
  "correlationId": "corr-123"
}
```

## Realtime Session Issuance

`POST /api/realtime/session`

Issues a short-lived client authorization payload for a Voxa Realtime practice session. The permanent OpenAI API key remains server-side only. The endpoint requires an authenticated Voxa app session.

```json
{
  "coachingMode": "tutor",
  "proficiencyBand": "B1-B2",
  "targetLanguage": "fr-FR"
}
```

Response `200`:

```json
{
  "correlationId": "corr-123",
  "clientSecret": "short-lived-client-token",
  "model": "gpt-realtime-2.1",
  "reasoningEffort": "low",
  "expiresAt": "2026-08-29T08:20:00Z",
  "settings": {
    "coachingMode": "tutor",
    "proficiencyBand": "B1-B2",
    "targetLanguage": "fr-FR"
  }
}
```

Response `401`:

```json
{
  "code": "app_session_required",
  "message": "An authenticated app session is required.",
  "correlationId": "corr-123",
  "retryable": false
}
```

## Lesson Generation

`POST /api/lessons`

Requests a lesson for the current plan and learner state.

```json
{
  "knowledgeUnitId": "greetings",
  "targetDurationMinutes": 10
}
```

Response `201`:

```json
{
  "lessonId": "lesson-1",
  "knowledgeUnitId": "greetings",
  "title": "First greetings",
  "steps": [
    {
      "stepId": "step-1",
      "type": "listen_repeat",
      "prompt": "Bonjour"
    }
  ],
  "correlationId": "corr-123"
}
```

## Learner State

`GET /api/learner/state`

Returns the full server-owned learner state for the authenticated user when the client needs more than a resume checkpoint.

`PUT /api/learner/state`

Updates learner state with optimistic concurrency.

Required headers:

- `If-Match: "1"`
- `Idempotency-Key: state-update-123`

Response `200` returns the updated version.

## Review

`GET /api/review/queue`

Returns due review items.

`POST /api/review/results`

Records review outcomes and updates the review queue.

```json
{
  "results": [
    {
      "knowledgeUnitId": "bonjour",
      "score": 0.82,
      "answeredAt": "2026-08-29T07:05:00Z"
    }
  ]
}
```

## Progress

`GET /api/progress`

Returns learner progress for the active plan.

```json
{
  "activePlanId": "plan-1",
  "completedKnowledgeUnitIds": ["greetings"],
  "streakDays": 3,
  "minutesPracticed": 45,
  "correlationId": "corr-123"
}
```

## Resume

`GET /api/session/resume`

Returns the checkpoint needed to continue from another iPhone or iPad.

Response `200`:

```json
{
  "correlationId": "corr-123",
  "version": 2,
  "profile": {
    "targetLanguage": "fr",
    "nativeLanguage": "en",
    "proficiencyLevel": "A1"
  },
  "activePlan": {
    "planId": "plan-1",
    "title": "Survival French",
    "knowledgeUnitIds": ["greetings"]
  },
  "currentLesson": {
    "lessonId": "lesson-1",
    "knowledgeUnitId": "greetings",
    "stepIndex": 3,
    "updatedAt": "2026-08-29T07:00:00Z"
  },
  "reviewQueue": [
    {
      "knowledgeUnitId": "bonjour",
      "dueAt": "2026-08-30T07:00:00Z",
      "priority": 2
    }
  ],
  "recentSessions": [
    {
      "sessionId": "session-1",
      "startedAt": "2026-08-29T07:00:00Z",
      "durationSeconds": 600,
      "lessonId": "lesson-1"
    }
  ]
}
```

Response `404`:

```json
{
  "code": "resume_checkpoint_not_found",
  "message": "No resume checkpoint exists for the current learner.",
  "correlationId": "corr-123",
  "retryable": false
}
```

## Durable Store Decision

MVP learner state and refresh-session state use the existing Azure Storage account through a Table-style persistence boundary. This keeps the Azure footprint minimal and avoids introducing Cosmos DB Serverless until query needs justify the extra service.

The backend persists:

- learner resume state by tenant and user,
- optimistic learner-state versions for cross-device concurrency,
- refresh-session records with expiry and revocation support.

Learner-state storage must keep tenant/user scope explicit in partition and row keys. Refresh-session storage must avoid raw-token keys. Tests must prove tenant isolation, JSON round-trip compatibility, stale-version rejection, refresh-token rotation, expiry, and revocation.
