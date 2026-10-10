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
`APP_ENABLE_DEV_RESET=true` together with `VOXA_ENVIRONMENT=dev`. Startup rejects
reset outside `dev`, an absent environment, invalid configured limits/flags,
and signing keys shorter than 32 UTF-8 bytes. When enabled, `DELETE /api/dev/learner-state`
requires a valid Voxa app-session bearer token and deletes only that
tenant/user's learner state. The endpoint is not a production user feature; it
exists to let testers replay sign-in, onboarding, resume, and Home/Talk routing
without manually editing Azure Table rows or reinstalling the app.

## Local Tests

```bash
DOTNET_CLI_HOME=/tmp/voxa-dotnet dotnet test backend/Voxa.sln --verbosity minimal
```

Tests do not require deployed Azure resources.

## Request and provider limits

Configuration is read once through `IConfiguration` at startup. Environment
variables remain the default source. `VoxaBackendOptions` is registered in DI.
`VOXA_ENVIRONMENT` is required in every environment, including local development.
Use a randomly generated signing key; the minimum length does not prove entropy.

Protected HTTP routes share a single authentication boundary. Missing, invalid,
expired, forged, and ambiguous authorization values return `401` before JSON is
read. Tenant/user identity comes only from the signed session, not request
headers or body fields. JSON is capped at 64 KiB, except image translation at
8 MiB; oversized input returns `413` before deserialization. Existing decoded
image and field-length limits still apply. Provider timeouts are 30 seconds for
Apple and 60 seconds for OpenAI; caller cancellation remains propagated.

The authenticated AI/debrief/plan/reassessment/practice/translation endpoints
and account export share a durable API request budget:

| Setting | Default |
| --- | ---: |
| `API_REQUEST_RATE_LIMIT_PER_WINDOW` | 20 attempts per user per minute |
| `API_REQUEST_MONTHLY_USER_LIMIT` | 3,000 attempts per user per UTC month |
| `API_REQUEST_MONTHLY_TENANT_LIMIT` | 30,000 attempts per tenant per UTC month |

Budget reservations use the existing Azure Table ETag mechanism in the separate
`api:tenant:*` partition namespace. They do not consume realtime issuance quotas.
Reservations happen before payload parsing/provider calls, so invalid attempts
also consume budget. Exhaustion returns `429` with `api_request_rate_limited` or
`api_request_budget_exhausted`; it cannot be bypassed by changing client identity
headers. Account deletion is allowed when this budget is exhausted and cleans up
per-user budget rows. Anonymous authentication abuse still needs an ingress
policy based on trusted source identity; client-supplied forwarding headers are
not a safe limiter key.

Backend CI merges source line coverage across test suites, excludes generated
`obj`/`bin` files, and enforces `coverage-thresholds.json`. Missing reports or
missing layer coverage fail the gate. Current floors are 75% overall, 95% Domain,
85% Application, 70% Infrastructure, and 70% API. These are measured baseline
floors, not changed-code coverage or proof of security.
