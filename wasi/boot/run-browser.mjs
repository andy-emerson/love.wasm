// Browser leg of the step-3 boot witness: the LÖVE core booting in real
// Chromium, frames on requestAnimationFrame, same WASI shim lineage as the
// step-0/step-2 witnesses. Usage: node run-browser.mjs <love-boot.wasm>
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { driveBoot } from './driver.mjs';

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

const result = await page.evaluate(async ({ b64, boot, driverSrc }) => {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  let memory;
  const td = new TextDecoder();
  const dv = () => new DataView(memory.buffer);
  let stdout = '';
  const wasi = {
    fd_write(fd, iovs, iovsLen, nwritten) {
      let n = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = dv().getUint32(iovs + i * 8, true);
        const len = dv().getUint32(iovs + i * 8 + 4, true);
        stdout += td.decode(new Uint8Array(memory.buffer, ptr, len));
        n += len;
      }
      dv().setUint32(nwritten, n, true);
      return 0;
    },
    proc_exit(code) { throw { wasiExit: code }; },
    clock_time_get(_id, _prec, ptr) {
      dv().setBigUint64(ptr, BigInt(Math.round(performance.now() * 1e6)), true);
      return 0;
    },
    random_get(ptr, len) { crypto.getRandomValues(new Uint8Array(memory.buffer, ptr, len)); return 0; },
    environ_sizes_get(c, s) { dv().setUint32(c, 0, true); dv().setUint32(s, 0, true); return 0; },
    environ_get() { return 0; },
    args_sizes_get(c, s) { dv().setUint32(c, 0, true); dv().setUint32(s, 0, true); return 0; },
    args_get() { return 0; },
    fd_close() { return 0; },
    fd_seek() { return 70; },
    fd_fdstat_get() { return 0; },
    fd_prestat_get() { return 8; },
    fd_prestat_dir_name() { return 8; },
  };
  const lines = [];
  try {
    const module = await WebAssembly.compile(bytes);
    for (const imp of WebAssembly.Module.imports(module)) {
      if (imp.module === 'wasi_snapshot_preview1' && !(imp.name in wasi)) {
        wasi[imp.name] = () => 52;  // ENOSYS — loudly absent, not silently wrong
      }
    }
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi });
    memory = instance.exports.memory;
    instance.exports._initialize();
    const driveBoot = new Function('return ' + driverSrc)();
    const ok = await driveBoot(
      instance.exports, boot,
      (cb) => requestAnimationFrame(cb),
      (line) => lines.push(line),
    );
    return { ok, lines, stdout };
  } catch (e) {
    return { ok: false, lines, stdout, error: String(e) };
  }
}, { b64: wasmB64, boot: bootSrc, driverSrc: driveBoot.toString() });

await browser.close();
console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout (love error_printer etc.) ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
