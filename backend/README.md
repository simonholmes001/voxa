# Voxa Backend

The backend is a .NET modular monolith deployed first on Azure Functions Flex Consumption.

The backend targets `net10.0`, matching the Azure Functions isolated worker runtime configured in Bicep and CI.

## Project Layout

- `src/Voxa.Domain`: domain identifiers, learner state, and domain exceptions.
- `src/Voxa.Application`: use cases, repository ports, and mobile-facing DTO contracts.
- `src/Voxa.Infrastructure`: adapter implementations for persistence and other infrastructure concerns.
- `src/Voxa.Api`: HTTP/API boundary, request validation, response/error shapes, and configuration validation.
- `tests/*`: unit tests by layer.

## MVP Persistence Decision

Voxa uses the existing Azure Storage baseline for MVP durable state through Table-style repository adapters. This keeps cost lower than adding Cosmos DB Serverless at this stage while supporting cross-device resume and app-session refresh-token state.

The implemented persistence boundary covers:

- learner state by tenant/user with optimistic version checks,
- refresh sessions with expiry and revocation,
- JSON document serialization for migration-friendly storage,
- in-memory table test doubles for deterministic local tests.

Cosmos DB remains disabled by default and should only be introduced after a separate cost/query decision.

## Mobile-Facing Session Contracts

The backend exposes contract classes for:

- Sign in with Apple exchange into Voxa app-session tokens,
- refresh-token rotation,
- logout refresh-token revocation,
- Realtime client-secret issuance for authenticated app sessions.

Permanent OpenAI API keys stay server-side; the mobile app receives only short-lived Realtime client credentials.
Apple identity tokens are verified against Apple's JWKS and must match the configured `APPLE_CLIENT_ID`.

## Developer Reset

For repeatable iPhone/iPad first-run UX testing, dev deployments can enable
`APP_ENABLE_DEV_RESET=true`. When enabled, `DELETE /api/dev/learner-state`
requires a valid Voxa app-session bearer token and deletes only that
tenant/user's learner state. The endpoint is not a production user feature; it
exists to let testers replay sign-in, onboarding, resume, and Home/Talk routing
without manually editing Azure Table rows or reinstalling the app.

## Local Tests

```bash
DOTNET_CLI_HOME=/tmp/voxa-dotnet dotnet test backend/Voxa.sln --verbosity minimal
```

Tests do not require deployed Azure resources.
