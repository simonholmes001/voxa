# Voxa security hardening backlog

Recovered from the interrupted session on 2026-10-10. Work continues on
`hardening/security-config-test-gates`, based on `3bd0cf6`, in
`Voxa/.worktrees/security-config-test-gates`.

This file is the persistent task list. “Implemented” means code is present in
this branch; it does not mean deployed controls or production security have
been verified. No Azure deployment or live secret rotation was performed.

## Repository work implemented

- [x] Central authenticated HTTP request helper used by all 18 protected routes.
- [x] Route-wide negative tests for missing, malformed, expired, forged,
      wrong-scheme, and duplicate authorization values, before body parsing.
- [x] Cross-user and cross-tenant language-profile deletion tests, including
      attempted identity-header overrides.
- [x] Bounded JSON parsing: 64 KiB normally, 8 MiB for image translation.
- [x] `IConfiguration` composition seam and registered typed backend options.
- [x] Startup rejection of missing environment, reset outside `dev`, weak
      signing keys, invalid flags, and invalid explicitly configured quotas.
- [x] Explicit provider timeouts and existing caller cancellation propagation.
- [x] Durable per-user burst and user/tenant monthly budgets for authenticated
      AI and export routes, independent of realtime quotas.
- [x] Concurrent budget, tenant-sharing, namespace-isolation, and subject-cleanup
      tests; account deletion removes per-user API budget counters.
- [x] Merged backend source-line coverage floors and fail-closed report checks.
- [x] Transitive .NET and locked Node dependency auditing.
- [x] Secret scanning with PR comments and secret-report artifacts disabled.
- [x] CodeQL for C#, JavaScript/TypeScript, and GitHub Actions, with a SARIF
      gate that blocks high/critical findings and error-level results.
- [x] Focused compiled-ARM checks for Storage HTTPS/TLS and Key Vault soft delete,
      alongside Voxa’s existing RBAC/private-network/storage security guards.
- [x] Release waits for both security workflows; required-check configuration
      prepared in the existing ruleset workflow.
- [x] Endpoint authorization matrix, threat scenarios, and operations plan below.

## Verification and rollout still required

- [ ] Run the new scanners in GitHub CI and fix any findings. Workflow syntax
      validation is not evidence that CodeQL/Gitleaks/Checkov scans are clean.
- [ ] Confirm the ruleset updater succeeds after merge and the named checks are
      enforced. Existing administrator/integration bypasses are unchanged.
- [ ] Measure quota defaults and provider timeouts under representative traffic
      before production promotion; add concurrency/load and degraded-provider
      integration scenarios beyond the deterministic reservation tests.
- [ ] Add a trusted-ingress policy for anonymous Apple/refresh/logout abuse and
      account creation. Do not trust client-supplied forwarding headers.
- [ ] Expand positive ownership tests to every read/write route and real Azure
      Table storage, including export and full account deletion.
- [ ] Test iOS → deployed backend → Apple/Storage/OpenAI flows with disposable
      accounts, including deletion/export and realtime credential expiry.
- [ ] Add changed-code coverage, Swift security analysis, SBOM generation, and
      broader IaC checks after reviewing controls against the dev architecture.
- [ ] Verify deployed flags, managed identity/RBAC, private access, Key Vault
      reference resolution, redaction, and deployment provenance.
- [ ] Exercise key rotation, emergency revocation, alert delivery, rollback,
      and backup/restore using the operations plan.
- [ ] Add expiry/retention cleanup for old quota rows; monthly counters remain
      aggregate tenant accounting when a subject is deleted.
- [ ] Decide whether immediate access-token invalidation on logout/deletion is
      required. Current stateless access tokens remain valid until their
      15-minute expiry; refresh-session revocation is separately implemented.
- [ ] Execute AI adversarial evaluations and an independent penetration test.

## Endpoint authorization matrix

All routes have Azure Functions `AuthorizationLevel.Anonymous`: that setting
allows mobile HTTP access; app authorization is enforced inside the function.
There are no client-selectable tenant/user identity parameters.

| Method and route (`/api` prefix) | Required proof | Additional budget |
| --- | --- | --- |
| POST `auth/apple` | Apple identity token and authorization code validation | Trusted-ingress policy pending |
| POST `auth/refresh` | Active refresh token, rotated by session service | Trusted-ingress policy pending |
| POST `auth/logout` | Possession of refresh token being revoked | Trusted-ingress policy pending |
| GET `health/deployment` | Public deployment marker only | None |
| GET `account/export` | Signed app session | Shared API budget |
| DELETE `account` | Signed app session | Exempt so exhaustion does not block erasure |
| POST `onboarding` | Signed app session | None |
| POST `realtime/session` | Signed app session | Existing realtime budget |
| POST `realtime/debrief` | Signed app session | Shared API budget |
| GET `learner/plan` | Signed app session | Shared API budget |
| GET `learner/course` | Signed app session | None |
| POST `learner/course/reassess` | Signed app session | Shared API budget |
| GET `session/resume` | Signed app session | None |
| POST `session/complete` | Signed app session | None |
| GET `language-profiles` | Signed app session | None |
| POST `language-profiles/{languageKey}/select` | Signed app session | None |
| DELETE `language-profiles/{languageKey}` | Signed app session | None |
| POST `practice/vocabulary-quiz` | Signed app session | Shared API budget |
| POST `language-tools/ask` | Signed app session | Shared API budget |
| POST `language-tools/translate` | Signed app session | Shared API budget |
| POST `language-tools/translate-image` | Signed app session | Shared API budget |
| DELETE `dev/learner-state` | Signed app session; explicit dev-only enablement | None |

Invalid protected sessions return `401 app_session_required` before JSON parsing
and before quota reservation. HTTP-function regression tests enumerate protected
functions from their attributes, so new routes must satisfy this boundary or be
explicitly classified as public in the test policy.

## Threat model and validation scenarios

| Threat | Repository control/evidence | Remaining evidence |
| --- | --- | --- |
| Forged/expired token; identity header spoofing | Signature/expiry validation; route-wide negative tests; token-owned subject | Deployed signing-key handling, full route ownership tests |
| Refresh-token reuse/concurrent rotation | Existing session/store rotation tests | Real storage concurrency and compromised-session recovery |
| Reuse of a stolen valid bearer token | Short expiry and quotas; TLS infrastructure | Immediate revocation decision; token-theft response exercise |
| AI cost amplification | Durable per-user/per-tenant budgets, request caps, provider timeouts | Anonymous ingress abuse controls, spend alerts, load tests |
| Oversized/malformed request | Bounded stream reads, field/image validation, `413`/`400` tests | Edge limits and realistic mobile image payloads |
| Developer reset exposed outside dev | Startup rejection and disabled endpoint | Deployed configuration evidence |
| Vulnerable dependency or leaked secret | Dependency/secret scans and aggregate checks | First successful CI scans and required-check enforcement |
| Unsafe code/workflow change | CodeQL and high-severity SARIF gate | CI analysis, independent security review |
| Data loss or partial account deletion | Ordered revocation/cleanup tests; error propagation | Restore exercise, retention audit, real deletion verification |
| Malicious learner text/image or model output | Existing prompt registry and output validation seams | Adversarial evaluations below |

Reusable bearer access tokens are expected to work more than once during their
lifetime. This is different from reusing a rotated refresh token; calling all
bearer reuse “replay rejection” would misstate the current protocol.

## Operations verification plan

Every exercise must record owner, UTC timestamp, environment, release SHA,
correlation IDs, expected/actual outcomes, and redacted evidence. Do not include
secret values, bearer tokens, prompts, transcripts, or personal data in evidence.
Use disposable test subjects; destructive exercises and deployments require the
existing explicit approval process.

1. **Configuration:** inspect only environment/reset/limit values and whether
   secret settings reference the expected vault and managed identity. Confirm
   startup with approved settings, and rejection of unsafe settings in a
   disposable environment. Do not test by changing the live production app.
2. **Rotation/revocation:** inventory OpenAI, Apple, app-session signing, and
   deployment credentials with owners and revocation procedures. Stage a new
   secret version; validate with a disposable session before switching clients.
   Signing-key replacement invalidates all access tokens signed by the old key;
   coordinate reauthentication and refresh-session revocation. Revoke the old
   upstream credential only after verifying the replacement. A leaked key must
   never be restored merely to make rollback easier.
3. **Monitoring:** configure and exercise authentication-failure, `429`, provider
   timeout/5xx, storage conflict, startup failure, stale deployment-marker,
   availability, and OpenAI spend alerts. Choose SLO targets from measured traffic
   and operational requirements; no alert or SLO is claimed enabled here. Verify
   alert delivery and named responder ownership, not just rule existence.
4. **Rollback:** identify the known-good release SHA/package, compatible storage
   schema, and configuration. Restore through the approved deployment workflow;
   verify `/api/health/deployment` reports that SHA, then sign-in/refresh/resume,
   practice, export, and deletion using disposable accounts. Record the recovery
   duration and any unrecovered data. No local Azure mutation is part of this plan.
5. **Backup/restore:** establish storage-specific retention and recovery
   capability, recovery-point and recovery-time objectives, and protected backup
   access. Restore into an isolated environment, verify tenant isolation and
   profile/evidence integrity, and check that revoked sessions are not revived.
6. **AI evaluations:** exercise role/secret-exfiltration instructions in learner
   text and image content, unsafe content, invalid/oversized provider output,
   model errors/timeouts and quota exhaustion. Assert the intended behavior and
   absence of sensitive logs with controlled fixtures first; use versioned live
   provider evaluations only with explicit budget and data-handling approval.

## Source coverage and evidence quality

Repository evidence: HTTP functions and tests, configuration/DI tests, existing
session and Table reservation tests, workflow/script tests, Bicep guards, and
coverage XML. [GitHub CodeQL](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages),
[Microsoft NuGet auditing](https://learn.microsoft.com/en-us/nuget/concepts/auditing-packages),
[Gitleaks](https://github.com/gitleaks/gitleaks-action), and
[Checkov](https://github.com/bridgecrewio/checkov/tree/3.3.26/checkov/arm/checks/resource) source documentation were checked on 2026-10-10 for workflow design.
Verified: local test and build results recorded in the delivery summary.
Derived: these controls reduce omission, allocation, and abuse risk.
Unverified: scanner results in GitHub and all deployed operational controls.
The original Copilot reports were design inputs, not penetration-test evidence.

## Last local verification

2026-10-10: 438 .NET 10 tests passed; 41 repository tests passed; Swift executed
362 tests with 2 expected macOS audio-host skips and zero failures. The mandatory
pre-commit hook passed. Merged source-line coverage was 79.07% overall (Domain
98.32%, Application 89.57%, Infrastructure 75.41%, API 77.98%); every configured
floor passed. Changed workflows passed `actionlint`, infrastructure guards
passed, and the main Bicep template compiled with its existing BCP081 type warning.
No iOS dependency version was changed; the initial Swift resolver cache failure
was recovered using uncached manifest resolution of the already-pinned version.
