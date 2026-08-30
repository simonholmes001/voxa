---
"voxa": minor
---

Wire the iOS app to the real backend auth contract: add `VoxaBackendAuthenticationService` in `VoxaNetworking` for `POST /api/auth/apple`, `/api/auth/refresh`, and `/api/auth/logout` with isolated wire DTOs and contract tests, add Sign in with Apple nonce handling, extend `AuthSession` with `refreshTokenExpiresAt`, and inject the service from `AppComposition` using a configurable `VOXA_API_BASE_URL` (failing clearly when unset). Onboarding now completes locally by default. Fix app signing so simulator/CI builds pass with a `CODE_SIGNING_ALLOWED=NO` override while device/TestFlight signing stays enabled.
