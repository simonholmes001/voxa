# Security and deployment checklist

Use this checklist before promoting a Voxa backend or iOS release to a
production-facing environment. Each item needs an owner and a link to its
evidence in the release record. The implementation status, authorization matrix,
and remaining verification work are tracked in
[`security-hardening-backlog.md`](security-hardening-backlog.md).

## Application security

- [ ] Every protected route rejects missing, expired, malformed, forged,
      and ambiguous app-session credentials.
- [ ] Resource access is scoped to the authenticated tenant and user.
- [ ] Refresh-token rotation, revocation, expiry, and reuse detection pass the
      authentication regression tests.
- [ ] Rate limits and quotas cover authentication, realtime session issuance,
      AI/image/voice operations, exports, and account creation.
- [ ] Request size, timeout, concurrency, and retry limits are configured.
- [ ] Account export and deletion are verified in a production-like environment.

## Production configuration

- [ ] `VOXA_ENVIRONMENT` is explicitly set to the intended environment.
- [ ] `APP_ENABLE_DEV_RESET` is false outside `dev`.
- [ ] No debug routes, test credentials, or verbose sensitive logging are
      enabled.
- [ ] Key Vault references resolve through the intended managed identity.
- [ ] OpenAI, Apple, signing, and deployment credentials have an owner and
      rotation/revocation procedure.

## Supply chain and release

- [ ] .NET and Node dependency audits pass.
- [ ] Infrastructure validation and guard tests pass.
- [ ] Backend, iOS, and integration/regression tests pass for the release SHA.
- [ ] Coverage artifacts are published and reviewed; new security-critical
      code has regression coverage.
- [ ] Release, rollback, and deployment-marker checks have been exercised.

## Operations and AI assurance

- [ ] Authentication, abuse, cost, deployment, and provider-failure alerts are
      active and have an owner.
- [ ] Logs redact tokens, prompts, transcripts, and personal data.
- [ ] Backup/restore and rollback procedures have recent evidence.
- [ ] Prompt injection, sensitive-data leakage, unsafe output, and provider
      degradation evaluations pass for the deployed prompt/model versions.
