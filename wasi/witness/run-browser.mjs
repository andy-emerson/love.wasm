// Browser witness driver: instantiate a wasm32-wasi command module in real
// Chromium with a hand-rolled WASI preview1 shim (no Emscripten, no node:wasi),
// capture stdout, and report the exit code. The shim here is the seed of
// love-wasi's browser host: fd_write, proc_exit, clocks, random, arg/env stubs.
import { readFileSync } from 'node:fs';
import { chromium } from 'playwright-core';

const wasmB64 = readFileSync(process.argv[2] ?? 'eh-witness.wasm').toString('base64');

const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const page = await browser.newPage();

const result = await page.evaluate(async (b64) => {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  let memory, out = '';
  const td = new TextDecoder();
  const dv = () => new DataView(memory.buffer);
  const wasi = {
    fd_write(fd, iovs, iovsLen, nwritten) {
      let n = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = dv().getUint32(iovs + i * 8, true);
        const len = dv().getUint32(iovs + i * 8 + 4, true);
        out += td.decode(new Uint8Array(memory.buffer, ptr, len));
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
    fd_seek() { return 70; },       // ESPIPE — stdout isn't seekable
    fd_fdstat_get() { return 0; },
    fd_prestat_get() { return 8; }, // EBADF — no preopened dirs
    fd_prestat_dir_name() { return 8; },
  };
  let exit = -1;
  try {
    const { instance } = await WebAssembly.instantiate(bytes, { wasi_snapshot_preview1: wasi });
    memory = instance.exports.memory;
    instance.exports._start();
    exit = 0;                        // _start returned without proc_exit
  } catch (e) {
    if (e && typeof e.wasiExit === 'number') exit = e.wasiExit;
    else return { out, exit: -1, error: String(e) };
  }
  return { out, exit };
}, wasmB64);

await browser.close();
console.log('--- browser stdout ---');
console.log(result.out.trimEnd());
console.log('--- exit: ' + result.exit + (result.error ? '  error: ' + result.error : '') + ' ---');
process.exit(result.exit === 0 && result.out.includes('EH-WITNESS: PASS') ? 0 : 1);
