import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

function readWorkflow(path) {
  return fs.readFileSync(path, 'utf8');
}

test('main CI workflow keeps only cheap repository-level PR checks', () => {
  const workflow = readWorkflow('.github/workflows/ci.yaml');

  assert.match(workflow, /changeset-check:/);
  assert.match(workflow, /repository-guard-tests:/);
  assert.match(workflow, /npm ci --workspaces=false/);
  assert.match(workflow, /npm test/);
  assert.doesNotMatch(workflow, /\n  node-tests:/);
  assert.doesNotMatch(workflow, /functions\/voxa-api/);
  assert.doesNotMatch(workflow, /\n  dotnet-tests:/);
  assert.doesNotMatch(workflow, /\n  ios-swift-tests:/);
  assert.doesNotMatch(workflow, /\n  ios-app-simulator-tests:/);
});

test('backend CI workflow uses a required sentinel and gates expensive tests by path', () => {
  const workflow = readWorkflow('.github/workflows/backend-ci.yaml');

  assert.match(workflow, /name: Backend CI/);
  assert.match(workflow, /pull_request:/);
  assert.doesNotMatch(workflow, /pull_request:\n\s+branches: \[main\]\n\s+paths:/);
  assert.match(workflow, /backend-ci-required:/);
  assert.match(workflow, /name: Backend CI Required/);
  assert.match(workflow, /"backend\/\*\*"/);
  assert.match(workflow, /"docs\/api-contracts\.md"/);
  assert.match(workflow, /Backend tests are not required for this change set\./);
  assert.match(workflow, /if: needs\.backend-ci-required\.outputs\.run-tests == 'true'/);
  assert.match(workflow, /name: \.NET Tests \(backend changes\)/);
  assert.match(workflow, /dotnet test backend\/\*\.sln --verbosity minimal/);
});

test('iOS CI workflow uses a required sentinel and covers iPhone and iPad simulators', () => {
  const workflow = readWorkflow('.github/workflows/ios-ci.yaml');

  assert.match(workflow, /name: iOS CI/);
  assert.match(workflow, /pull_request:/);
  assert.doesNotMatch(workflow, /pull_request:\n\s+branches: \[main\]\n\s+paths:/);
  assert.match(workflow, /ios-ci-required:/);
  assert.match(workflow, /name: iOS CI Required/);
  assert.match(workflow, /"ios\/\*\*"/);
  assert.match(workflow, /iOS tests are not required for this change set\./);
  assert.match(workflow, /if: needs\.ios-ci-required\.outputs\.run-tests == 'true'/);
  assert.match(workflow, /swift-package-privacy-tests:/);
  assert.match(workflow, /Run privacy-critical Swift package tests/);
  assert.match(workflow, /swift test\s+\\\n\s+--package-path ios\/VoxaApp\s+\\\n\s+--filter 'AuthViewModelTests\|VoxaBackendAuthenticationServiceTests'/);
  assert.doesNotMatch(workflow, /iPhone\/iPad Swift Tests \(iOS changes\)/);
  assert.match(workflow, /timeout-minutes: 10/);
  assert.match(workflow, /timeout-minutes: 25/);
  assert.doesNotMatch(workflow, /matrix:/);
  assert.match(workflow, /Pick an iPhone simulator device/);
  assert.match(workflow, /Pick an iPad simulator device/);
  assert.match(workflow, /Run app target tests on iPhone Simulator/);
  assert.match(workflow, /Run app target tests on iPad Simulator/);
  assert.strictEqual(
    (workflow.match(/actions\/cache@0057852bfaa89a56745cba8c7296529d2fc39830/g) ?? []).length,
    2,
  );
  assert.doesNotMatch(workflow, /actions\/cache@6849a6489940f00c2f30c0fb92c6274307ccb58a/);
});

test('iOS WebRTC package pin uses an upstream release with downloadable assets', () => {
  const manifest = readWorkflow('ios/VoxaApp/Package.swift');
  const lockfile = readWorkflow('ios/VoxaApp/Package.resolved');
  const readme = readWorkflow('ios/README.md');

  assert.match(manifest, /exact: "152\.0\.0"/);
  assert.match(lockfile, /"version" : "152\.0\.0"/);
  assert.match(readme, /Version\*\*: 152\.0\.0/);
  assert.doesNotMatch(manifest, /151\.0\.0|151\.0\.1/);
  assert.doesNotMatch(lockfile, /151\.0\.0|151\.0\.1/);
});

test('local pre-commit hook keeps unit test guardrails enabled', () => {
  const hook = readWorkflow('.githooks/pre-commit');

  assert.match(hook, /npm .*run test/);
  assert.match(hook, /dotnet test backend\/\*\.sln --verbosity minimal/);
  assert.match(hook, /swift test --package-path "\$target_dir"/);
  assert.doesNotMatch(hook, /functions\/voxa-api/);
});

test('TestFlight workflow requires backend and privacy policy release URLs', () => {
  const workflow = readWorkflow('.github/workflows/ios-testflight.yml');
  const fastfile = readWorkflow('ios/fastlane/Fastfile');

  assert.match(workflow, /VOXA_API_BASE_URL/);
  assert.match(workflow, /VOXA_PRIVACY_POLICY_URL/);
  assert.match(workflow, /Missing required secret: \$key/);
  assert.match(fastfile, /ENV\.fetch\("VOXA_API_BASE_URL"\)/);
  assert.match(fastfile, /ENV\.fetch\("VOXA_PRIVACY_POLICY_URL"\)/);
  assert.match(fastfile, /VOXA_PRIVACY_POLICY_URL=#\{privacy_policy_url\}/);
});

test('release workflow gates tagging on validation and infrastructure workflows', () => {
  const workflow = readWorkflow('.github/workflows/release.yml');
  const gate = readWorkflow('.github/scripts/release-gate.sh');

  assert.match(workflow, /workflow_run:/);
  assert.match(workflow, /- CI\n\s+- Backend CI\n\s+- iOS CI/);
  assert.match(workflow, /- Azure Infrastructure Deploy/);
  assert.match(workflow, /Wait for required validation and infrastructure workflows/);
  assert.match(workflow, /ref: \$\{\{ github\.event\.workflow_run\.head_sha \}\}/);
  assert.match(workflow, /--target "\$\{\{ github\.event\.workflow_run\.head_sha \}\}"/);
  assert.match(gate, /required_workflows=\("CI" "Backend CI" "iOS CI"\)/);
  assert.match(gate, /Azure Infrastructure Deploy/);
  assert.match(gate, /status.*completed/);
  assert.match(gate, /conclusion.*success/);
  assert.match(gate, /git cat-file -e.*\^\{commit\}/);
  assert.match(gate, /git diff-tree --root --no-commit-id --name-only -r -m/);
  assert.doesNotMatch(gate, /git diff --name-only.*\^1/);
  assert.match(gate, /Unable to compute changed files/);
});
