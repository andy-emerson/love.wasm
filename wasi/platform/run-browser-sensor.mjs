// Browser leg of the issue-#27 sensor/preview-warn witness: the LÖVE core + real
// love.sensor warned-stub backend driven in real Chromium (frames on
// requestAnimationFrame), via the shared harness (wasi/host/witness-harness.mjs)
// and the shared WASI shim. The shim's fd_write accumulates every fd — stderr
// included — into its host tap (result.stdout), so the "[love-wasi preview]"
// line lands there. The witness calls getData TWICE (same feature) yet the tap
// must hold exactly ONE preview line — the ONE-TIME dedup, witnessed and
// printed. No browser APIs are used, so a blank page is enough.
// Usage: node run-browser-sensor.mjs <love-sensor.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-sensor.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-sensor.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.error) console.log('--- error: ' + result.error + ' ---');

const tap = result.stdout || '';
const previewLines = tap.split('\n').filter((l) => l.includes('[love-wasi preview]'));
const count = previewLines.length;

console.log('--- host tap (fd_write) preview lines ---');
for (const l of previewLines) console.log(l);
console.log(`preview-warning count after two getData calls: ${count} (expected 1)`);

const oneTimeOk = count === 1;
if (!result.ok) console.log('FAIL: Lua witness did not reach STEP27-WARN-WITNESS: PASS');
if (!oneTimeOk) console.log(`FAIL: expected exactly 1 preview line, got ${count}`);
console.log((result.ok && oneTimeOk) ? 'browser leg: PASS' : 'browser leg: FAIL');
process.exit(result.ok && oneTimeOk ? 0 : 1);
