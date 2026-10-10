import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

function check(doc) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'voxa-sarif-'));
  try {
    if (doc !== null) writeFileSync(path.join(dir, 'results.sarif'), JSON.stringify(doc));
    return spawnSync(process.execPath, ['.github/scripts/check-security-results.mjs', dir], {encoding:'utf8'});
  } finally { rmSync(dir, {recursive:true,force:true}); }
}
function sarif(severity, results=[{ruleId:'test',ruleIndex:0}]) {
  return {version:'2.1.0',runs:[{tool:{driver:{rules:[{id:'test',properties:{'security-severity':severity}}]}},results}]};
}
test('security gate blocks high and critical findings', () => {
  for (const severity of ['7.0', '9.8']) assert.equal(check(sarif(severity)).status, 1);
});
test('security gate permits clean results and lower severity findings', () => {
  assert.equal(check(sarif('9.8', [])).status, 0);
  assert.equal(check(sarif('6.9')).status, 0);
});
test('security gate fails closed for missing or malformed reports and rule metadata', () => {
  for (const document of [null, {}, {version:'2.1.0',runs:[]}, sarif('invalid'), sarif('7.0',[{ruleId:'missing'}])])
    assert.equal(check(document).status, 1);
});
test('security gate rejects results at error level even without security severity', () => {
  assert.equal(check(sarif(undefined,[{ruleId:'test',level:'error'}])).status, 1);
});
