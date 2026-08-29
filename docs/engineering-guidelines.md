# Voxa Engineering Guidelines

These guidelines apply to all Voxa work done by Codex, Copilot, Claude, and human contributors. They exist to keep the repository predictable before implementation work is split across multiple agents.

## Source Of Truth

- The PRD defines product intent, user journeys, and non-functional requirements.
- GitHub issues define scoped delivery work and acceptance criteria.
- Pull requests are the only path for changing `main`.
- Architecture-impacting decisions must be captured in the PRD, an ADR, or the relevant issue before implementation.

## Current Tech Stack

- **iPhone and iPad app:** Swift and SwiftUI under `ios/`, with iOS and iPadOS support required from the start.
- **iOS delivery:** Fastlane/TestFlight workflow under `ios/fastlane/` and `.github/workflows/ios-testflight.yml`; uploads stay skipped until an Xcode project or workspace exists.
- **Backend:** .NET 10 modular monolith, deployed initially as Azure Functions Flex Consumption.
- **Azure infrastructure:** Bicep templates under `infrastructure/`, deployed through GitHub Actions using OIDC and a user-assigned managed identity.
- **Cloud baseline:** minimal-cost Azure footprint with Function App, Storage, Key Vault, Application Insights, Log Analytics, VNet, private DNS, private endpoints, and optional Cosmos DB Serverless disabled by default.
- **AI integration:** OpenAI API keys are server-side only. Mobile clients must call Voxa backend endpoints, not OpenAI directly.
- **Repository automation:** Node.js 22 for workflow scripts and tests, Changesets for releasable changes, GitHub Actions for CI, infrastructure validation, Codex PR review, and future iOS delivery.

## Branch And Merge Controls

- Do not commit directly to `main`.
- Before any change, sync local `main` to `origin/main` with fast-forward only.
- Use a dedicated feature branch and worktree for each coherent change.
- Do not merge to `main` without Simon's explicit permission.
- Do not force-push unless there is an explicitly agreed reason, such as correcting a branch before anyone else depends on it.
- Do not bypass hooks or checks with `--no-verify`.
- Keep one primary intent per PR.
- Use Conventional Commits for PR titles and commits, for example `docs: add engineering guidelines`.

## Test-Driven Development

- Use TDD for behavior changes: Red, Green, Refactor.
- State the behavior first, then add the smallest failing test that describes it.
- Implement the minimum production change needed to pass.
- Refactor only after the relevant test slice is green.
- For bugs, write a failing regression test before the fix when feasible.
- For domain logic, prefer fast unit tests.
- For APIs and external boundaries, add integration or contract tests.
- For iOS flows, add focused unit/view-model tests first and keep UI automation targeted.
- Tests must be deterministic: control time, randomness, network calls, external services, and shared state.
- If a spike is needed, label it as a spike and follow it with tests before production implementation continues.

## Infrastructure Rules

- Azure infrastructure must be defined in Bicep and reviewed through PRs.
- Normal infrastructure deployment happens only through GitHub Actions after merge to `main`.
- Do not deploy or mutate Azure workload infrastructure locally unless Simon explicitly approves the exact action.
- Manual Azure Portal changes are limited to inspection, emergency recovery, or an explicitly approved one-time bootstrap action.
- No hardcoded Azure regions, subscription IDs, tenant IDs, client IDs, resource group names, resource names, or secrets.
- `AZURE_LOCATION` must drive the deployment region. Voxa dev currently uses `swedencentral`.
- Use GitHub OIDC with a user-assigned managed identity. Do not use Azure client secrets.
- Prefer least-privilege RBAC at the narrowest practical scope.
- Keep networking separated from workload resources: network foundation resources belong in the network resource group.
- Private networking, managed identity, and server-side secret handling are baseline requirements.
- Any additional paid Azure service requires an explicit cost and architecture decision before implementation.

## Security And Secrets

- Never commit secrets, tokens, certificates, API keys, provisioning profiles, or private keys.
- OpenAI keys, Azure IDs, Apple credentials, and Fastlane match credentials must remain GitHub repository secrets or approved local developer secrets.
- Mobile apps must not contain privileged service credentials.
- Log enough for supportability, but redact secrets, access tokens, personal data, and prompt payloads where required.
- Treat authentication, authorization, session continuity, and cross-device state sync as first-class product behavior.

## Agent Work Allocation

- Codex should own repo structure, backend contracts, CI/CD, infrastructure, security-sensitive flows, and cross-cutting guardrails.
- Copilot should take scoped implementation tasks with clear contracts, especially iOS screens, view models, and straightforward backend endpoints.
- Claude should take PRD refinement, prompt/evaluation design, user-story detail, acceptance criteria, and documentation-heavy work.
- Agents must not independently change architecture, infrastructure boundaries, or merge strategy.
- Any agent that finds a blocking ambiguity must stop and ask rather than inventing a hidden decision.

## Pull Request Expectations

- Link each PR to the relevant issue.
- Include the user-facing behavior, implementation summary, tests run, and risks.
- Include screenshots or recordings for meaningful iPhone/iPad UI changes.
- Include Azure validation evidence for infrastructure changes.
- Add a changeset for releasable changes.
- Resolve Codex review, CI, infrastructure validation, and reviewer findings before merge.
- Keep documentation updates in the same PR when behavior, operations, or architecture changes.

## Definition Of Done

- Acceptance criteria are met.
- Relevant tests were written first where practical and now pass.
- Linting, formatting, and repository checks pass.
- CI is green or any failure is understood, documented, and explicitly accepted.
- Documentation, PRD, ADRs, and changesets are updated when required.
- No Azure deployment, pipeline rerun, force-push, or merge happened without explicit permission where required.

## Stop-The-Line Conditions

Stop and ask before proceeding when:

- A change would mutate or delete Azure resources outside the approved pipeline path.
- A branch or worktree contains unknown user changes that could be overwritten.
- A requirement conflicts with the PRD, security baseline, or cost-minimal Azure architecture.
- A fix requires bypassing tests, branch protection, review, hooks, or merge controls.
- A task requires credentials or access that are not already available.
