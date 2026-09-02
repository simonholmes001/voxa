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
  assert.doesNotMatch(workflow, /\n  node-tests:/);
  assert.doesNotMatch(workflow, /functions\/voxa-api/);
  assert.doesNotMatch(workflow, /\n  dotnet-tests:/);
  assert.doesNotMatch(workflow, /\n  ios-swift-tests:/);
  assert.doesNotMatch(workflow, /\n  ios-app-simulator-tests:/);
});

test('backend CI workflow is path-filtered to backend and contract-impacting files', () => {
  const workflow = readWorkflow('.github/workflows/backend-ci.yaml');

  assert.match(workflow, /name: Backend CI/);
  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /pull_request:\n\s+branches: \[main\]\n\s+paths:/);
  assert.match(workflow, /"backend\/\*\*"/);
  assert.match(workflow, /"docs\/api-contracts\.md"/);
  assert.doesNotMatch(workflow, /should-run/);
  assert.doesNotMatch(workflow, /Backend paths were not changed; skipping \.NET tests\./);
  assert.match(workflow, /dotnet test backend\/\*\.sln --verbosity minimal/);
});

test('iOS CI workflow is path-filtered and still covers Swift plus iPhone and iPad simulators', () => {
  const workflow = readWorkflow('.github/workflows/ios-ci.yaml');

  assert.match(workflow, /name: iOS CI/);
  assert.match(workflow, /pull_request:/);
  assert.match(workflow, /pull_request:\n\s+branches: \[main\]\n\s+paths:/);
  assert.match(workflow, /"ios\/\*\*"/);
  assert.doesNotMatch(workflow, /should-run/);
  assert.doesNotMatch(workflow, /iOS paths were not changed; skipping iOS tests\./);
  assert.match(workflow, /swift test --package-path ios\/VoxaApp/);
  assert.doesNotMatch(workflow, /matrix:/);
  assert.match(workflow, /Pick an iPhone simulator device/);
  assert.match(workflow, /Pick an iPad simulator device/);
  assert.match(workflow, /Run app target tests on iPhone Simulator/);
  assert.match(workflow, /Run app target tests on iPad Simulator/);
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
