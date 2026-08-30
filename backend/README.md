# Voxa Backend

The backend is a .NET modular monolith deployed first on Azure Functions Flex Consumption.

The initial skeleton targets `net9.0` so it can be built and tested with the SDK currently installed locally. CI uses the .NET 10 SDK and can still build this target framework. Move the target framework to `net10.0` once the local developer SDK baseline is upgraded.

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

## Local Tests

```bash
DOTNET_CLI_HOME=/tmp/voxa-dotnet dotnet test backend/Voxa.sln --verbosity minimal
```

Tests do not require deployed Azure resources.
