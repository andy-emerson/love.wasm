// Browser leg of the step-3 boot witness: the LÖVE core booting in real
// Chromium, frames on requestAnimationFrame, sharing the one WASI shim
// (wasi/host/wasi-shim.mjs) with the step-0/step-2 witnesses.
// Usage: node run-browser.mjs <love-boot.wasm>
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { driveBoot } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';

const require = createRequire(resolve(process.cwd(), 'noop.js'));
const { chromium } = require('playwright-core');
const executablePath = process.env.CHROMIUM && existsSync(process.env.CHROMIUM)
  ? process.env.CHROMIUM
  : undefined;

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-boot.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-boot.wasm').toString('base64');

const browser = await chromium.launch(executablePath ? { executablePath } : {});
const page = await browser.newPage();

const result = await page.evaluate(async ({ b64, boot, driverSrc, shimSrc }) => {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const makeWasiShim = new Function('return ' + shimSrc)();
  const shim = makeWasiShim();
  const lines = [];
  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);  // ENOSYS the preview1 calls the reactor imports but the shim omits
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: shim.imports });
    shim.bind(instance.exports.memory);
    instance.exports._initialize();
    const driveBoot = new Function('return ' + driverSrc)();
    const ok = await driveBoot(
      instance.exports, boot,
      (cb) => requestAnimationFrame(cb),
      (line) => lines.push(line),
    );
    return { ok, lines, stdout: shim.stdout };
  } catch (e) {
    return { ok: false, lines, stdout: shim.stdout, error: String(e) };
  }
}, { b64: wasmB64, boot: bootSrc, driverSrc: driveBoot.toString(), shimSrc: makeWasiShim.toString() });

await browser.close();
console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout (love error_printer etc.) ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
