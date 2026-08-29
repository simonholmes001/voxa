import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');
const promptRoot = path.join(repoRoot, 'docs', 'prompts');
const evalRoot = path.join(repoRoot, 'docs', 'evals');
const allowedCapabilities = new Set([
  'RealtimeTutorModel',
  'RealtimeTutorModelLite',
  'TutorModel',
  'LessonGenerationModel',
  'CurriculumModel',
  'AssessmentModel',
  'BoundedTaskModel',
  'LiveTranscriptionModel',
  'SpeechGenerationModel',
]);
const allowedAssertionPredicates = new Set([
  'equals',
  'notEquals',
  'contains',
  'notContains',
  'length',
  'matches',
  'oneOf',
  'noneOf',
  'jsonSchema',
]);

function listYamlFiles(root) {
  return fs.readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      return listYamlFiles(entryPath);
    }

    return entry.isFile() && entry.name.endsWith('.yaml') ? [entryPath] : [];
  });
}

function topLevelValue(text, key) {
  const match = text.match(new RegExp(`^${key}:\\s*(.+)?$`, 'm'));
  return match ? (match[1] ?? '').trim() : null;
}

function declaredVariables(text) {
  const names = [];
  let inVariables = false;

  for (const line of text.split('\n')) {
    if (line === 'variables:') {
      inVariables = true;
      continue;
    }

    if (inVariables && /^[A-Za-z][A-Za-z0-9]*:/.test(line)) {
      break;
    }

    const match = line.match(/^\s+- name:\s*([A-Za-z][A-Za-z0-9_]*)/);
    if (inVariables && match) {
      names.push(match[1]);
    }
  }

  return names;
}

function renderedVariables(text) {
  return [...text.matchAll(/\{\{\s*([A-Za-z][A-Za-z0-9_]*)\s*\}\}/g)].map((match) => match[1]);
}

function assertionPredicateLines(text) {
  const lines = text.split('\n');
  const predicates = [];

  for (let index = 0; index < lines.length; index += 1) {
    if (!/^\s+- path: /.test(lines[index])) {
      continue;
    }

    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      const predicateMatch = lines[cursor].match(/^\s{8}([A-Za-z][A-Za-z0-9]*):/);
      if (predicateMatch) {
        predicates.push(predicateMatch[1]);
        break;
      }

      if (/^\s+- path: /.test(lines[cursor]) || /^\S/.test(lines[cursor])) {
        break;
      }
    }
  }

  return predicates;
}

test('prompt examples obey registry metadata and strict variable contracts', () => {
  for (const promptFile of listYamlFiles(promptRoot)) {
    const relativePath = path.relative(promptRoot, promptFile);
    const text = fs.readFileSync(promptFile, 'utf8');
    const kind = topLevelValue(text, 'kind');
    const id = topLevelValue(text, 'id');
    const version = topLevelValue(text, 'version');

    assert.ok(kind, `${relativePath} must declare kind explicitly`);
    assert.ok(['completion', 'fragment'].includes(kind), `${relativePath} has invalid kind ${kind}`);
    assert.ok(id, `${relativePath} must declare id`);
    assert.equal(relativePath, `${id}.v${version}.yaml`, `${relativePath} must mirror id/version`);

    const declared = new Set(declaredVariables(text));
    const rendered = new Set(renderedVariables(text));

    for (const variable of rendered) {
      assert.ok(declared.has(variable), `${relativePath} renders undeclared variable {{${variable}}}`);
    }

    for (const variable of declared) {
      assert.ok(rendered.has(variable), `${relativePath} declares unused variable ${variable}`);
    }

    if (kind === 'completion') {
      const capability = topLevelValue(text, 'capability');
      assert.ok(allowedCapabilities.has(capability), `${relativePath} has invalid capability ${capability}`);
      assert.equal(topLevelValue(text, 'compatibleCapabilities'), null, `${relativePath} must not declare compatibleCapabilities`);
    } else {
      assert.equal(topLevelValue(text, 'capability'), null, `${relativePath} fragments must not declare capability`);
      assert.match(text, /^compatibleCapabilities:\n(?:\s+- [A-Za-z0-9]+\n)+/m, `${relativePath} must declare compatibleCapabilities`);
    }
  }
});

test('eval examples use only documented assertion predicates', () => {
  for (const evalFile of listYamlFiles(evalRoot)) {
    const relativePath = path.relative(evalRoot, evalFile);
    const text = fs.readFileSync(evalFile, 'utf8');

    assert.ok(topLevelValue(text, 'suite'), `${relativePath} must declare suite`);
    assert.ok(topLevelValue(text, 'version'), `${relativePath} must declare version`);
    assert.match(text, /^cases:\n/m, `${relativePath} must declare cases`);

    for (const predicate of assertionPredicateLines(text)) {
      assert.ok(allowedAssertionPredicates.has(predicate), `${relativePath} uses undocumented assertion predicate ${predicate}`);
    }
  }
});
