// Node leg of the issue-#27 sensor/preview-warn witness: instantiate the reactor
// (LÖVE core + real love.sensor warned-stub backend) under node's WASI — an
// independent, complete WASI host, the cross-check against the hand-rolled
// browser shim — and run the shared transcript.
//
// The "[love-wasi preview]" warning is emitted over stderr (fd 2). node:wasi
// routes guest fd 2 to whatever host fd its `stderr` option names, so we point
// it at a temp file and, after the run, count the preview lines in it: the
// witness calls getData TWICE (same feature) yet the count must be exactly 1 —
// the ONE-TIME dedup, witnessed and printed.
// Usage: node run-node-sensor.mjs <love-sensor.wasm>
import { readFileSync, openSync, closeSync, mkdtempSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';
import { driveSensor } from './driver-sensor.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-sensor.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-sensor.wasm');

const tmp = mkdtempSync(join(tmpdir(), 'sensor-warn-'));
const errPath = join(tmp, 'stderr.txt');
const errFd = openSync(errPath, 'w');

let luaOk = false;
try {
  const wasi = new WASI({ version: 'preview1', stderr: errFd });
  const { instance } = await WebAssembly.instantiate(bytes, wasi.getImportObject());
  wasi.initialize(instance); // reactor: runs ctors, no _start
  luaOk = await driveSensor(
    instance.exports, bootSrc, (cb) => setTimeout(cb, 0), (line) => console.log(line)
  );
} finally {
  closeSync(errFd);
}

const errText = readFileSync(errPath, 'utf8');
rmSync(tmp, { recursive: true, force: true });

const previewLines = errText.split('\n').filter((l) => l.includes('[love-wasi preview]'));
const count = previewLines.length;

console.log('--- host tap (fd 2) preview lines ---');
for (const l of previewLines) console.log(l);
console.log(`preview-warning count after two getData calls: ${count} (expected 1)`);

const oneTimeOk = count === 1;
if (!luaOk) console.log('FAIL: Lua witness did not reach STEP27-WARN-WITNESS: PASS');
if (!oneTimeOk) console.log(`FAIL: expected exactly 1 preview line, got ${count}`);
console.log((luaOk && oneTimeOk) ? 'node leg: PASS' : 'node leg: FAIL');
process.exit(luaOk && oneTimeOk ? 0 : 1);
