import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

function check(reports, threshold = 75) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'voxa-coverage-test-'));
  try {
    for (const [name, content] of Object.entries(reports)) fs.writeFileSync(path.join(dir, name), content);
    const config = path.join(dir, 'thresholds.json');
    fs.writeFileSync(config, JSON.stringify({ overall: threshold, layers: { 'Voxa.Api': threshold } }));
    return spawnSync('python3', ['.github/scripts/check-backend-coverage.py', dir, config], { encoding: 'utf8' });
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
}
const xml = (hits) => `<coverage><packages><package><classes><class filename="Voxa.Api/Functions/Example.cs"><lines>${hits.map((h,i)=>`<line number="${i+1}" hits="${h}"/>`).join('')}</lines></class></classes></package></packages></coverage>`;

test('coverage gate combines hits across suites without double counting lines', () => {
  const result = check({ 'a.cobertura.xml': xml([1,0]), 'b.cobertura.xml': xml([0,1]) }, 100);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /2\/2/);
});
test('coverage gate fails below threshold', () => {
  assert.equal(check({ 'a.cobertura.xml': xml([1,0]) }).status, 1);
});
test('coverage gate fails on absent, empty, malformed, or invalid reports', () => {
  for (const reports of [{}, {'a.cobertura.xml': xml([])}, {'a.cobertura.xml': '<invalid'}, {'a.cobertura.xml': xml([-1])}])
    assert.notEqual(check(reports).status, 0);
});
test('coverage gate ignores generated code and fails if a required layer is absent', () => {
  assert.notEqual(check({ 'a.cobertura.xml': xml([1]).replace('Voxa.Api/Functions', 'Voxa.Api/obj/Debug') }).status, 0);
  assert.notEqual(check({ 'a.cobertura.xml': xml([1]).replace('Voxa.Api/', 'Voxa.Domain/') }).status, 0);
});
test('coverage gate rejects thresholds outside a finite percentage', () => {
  assert.notEqual(check({ 'a.cobertura.xml': xml([1]) }, 101).status, 0);
});
