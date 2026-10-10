import fs from 'node:fs';
import path from 'node:path';

function reports(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? reports(file) : entry.isFile() && file.endsWith('.sarif') ? [file] : [];
  });
}

function resolveRule(run, result) {
  const extensions = run.tool.extensions ?? [];
  const reference = result.rule;
  const componentReference = reference?.toolComponent;
  let components = [run.tool.driver, ...extensions];
  if (componentReference) {
    components = extensions.filter((component, index) =>
      (componentReference.index === undefined || componentReference.index === index)
      && (componentReference.name === undefined || componentReference.name === component.name)
      && (componentReference.guid === undefined || componentReference.guid === component.guid));
    if (components.length !== 1) throw new Error('Invalid rule component reference.');
  }
  const id = reference?.id ?? result.ruleId;
  if (reference?.id !== undefined && result.ruleId !== undefined && reference.id !== result.ruleId)
    throw new Error('Mismatched rule IDs.');
  const index = reference?.index ?? result.ruleIndex;
  if (reference?.index !== undefined && result.ruleIndex !== undefined && reference.index !== result.ruleIndex)
    throw new Error('Mismatched rule indexes.');
  if (index !== undefined && (!Number.isInteger(index) || index < 0))
    throw new Error('Invalid rule index.');
  // Without a component reference, an index belongs to the driver. An ID can
  // also identify an extension rule, as emitted by CodeQL.
  const candidates = id !== undefined
    ? components.flatMap(component => (component.rules ?? []).filter(rule => rule.id === id))
    : index !== undefined ? [(componentReference ? components[0] : run.tool.driver).rules?.[index]].filter(Boolean) : [];
  if (candidates.length !== 1) throw new Error('Result has no unambiguous corresponding rule.');
  if (index !== undefined) {
    const component = componentReference ? components[0] : run.tool.driver;
    if (componentReference || component.rules?.some(rule => rule === candidates[0])) {
      if (component.rules?.[index] !== candidates[0]) throw new Error('Mismatched rule index.');
    }
  }
  return candidates[0];
}

try {
  const files = reports(process.argv[2]);
  if (!files.length) throw new Error('No SARIF reports found.');
  let blocked = 0;
  for (const file of files) {
    const document = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (document.version !== '2.1.0' || !Array.isArray(document.runs) || !document.runs.length)
      throw new Error('Invalid SARIF document.');
    for (const run of document.runs) {
      if (!Array.isArray(run.results) || !Array.isArray(run.tool?.driver?.rules))
        throw new Error('Missing results or rule metadata.');
      for (const result of run.results) {
        const rule = resolveRule(run, result);
        const rawSeverity = rule.properties?.['security-severity'];
        const severity = rawSeverity === undefined ? 0 : Number(rawSeverity);
        if (!Number.isFinite(severity) || severity < 0 || severity > 10)
          throw new Error('Invalid security severity.');
        if (severity >= 7 || (result.level ?? rule.defaultConfiguration?.level) === 'error') blocked++;
      }
    }
  }
  console.log(`Security gate: ${files.length} reports, ${blocked} blocking findings.`);
  process.exitCode = blocked ? 1 : 0;
} catch (error) {
  console.error(`Security gate failed: ${error.message}`);
  process.exitCode = 1;
}
