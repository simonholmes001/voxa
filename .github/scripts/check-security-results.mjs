import fs from 'node:fs';
import path from 'node:path';

function reports(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? reports(file) : entry.isFile() && file.endsWith('.sarif') ? [file] : [];
  });
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
        const rule = run.tool.driver.rules.find((candidate) => candidate.id === result.ruleId)
          ?? run.tool.driver.rules[result.ruleIndex];
        if (!rule) throw new Error('Result has no corresponding rule.');
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
