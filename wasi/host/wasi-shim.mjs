// The one hand-rolled WASI preview1 shim for love-wasi's browser host — the
// seed the step-4 WebGL2 import surface grows into (readme.md: "the shim is the
// seed of the runtime host"). Consolidated here from three near-identical inline
// copies that lived in the step-0/2/3 browser runners.
//
// Self-contained by contract, exactly like driver.mjs: no imports, no
// outer-scope references, so makeWasiShim.toString() can be stringified into a
// Playwright page and rebuilt with `new Function('return ' + src)()`. It runs
// unchanged in node too (TextDecoder, DataView, crypto, performance, and
// WebAssembly are all globals in both), though the witness *node* legs
// deliberately run under node:wasi instead — an independent, complete WASI host
// implementation, kept as a cross-check so the two legs don't share this shim's
// blind spots.
//
// Usage (in-page, stringified):
//   const makeWasiShim = new Function('return ' + shimSrc)();
//   const shim = makeWasiShim();
//   const module = await WebAssembly.compile(bytes);
//   shim.autostub(module);                        // reactor: ENOSYS the rest
//   const { instance } = await WebAssembly.instantiate(
//     module, { wasi_snapshot_preview1: shim.imports });
//   shim.bind(instance.exports.memory);           // before any import fires
//   instance.exports._initialize();               // reactor  (or _start() for a command)
//   shim.stdout                                    // accumulated fd_write text
export function makeWasiShim() {
  let memory;
  let stdout = '';
  const td = new TextDecoder();
  const dv = () => new DataView(memory.buffer);
  const imports = {
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
    fd_seek() { return 70; },       // ESPIPE — stdout isn't seekable
    fd_fdstat_get() { return 0; },
    fd_prestat_get() { return 8; }, // EBADF — no preopened dirs
    fd_prestat_dir_name() { return 8; },
  };
  return {
    imports,
    // Bind the instance's linear memory before any import call touches it.
    bind(m) { memory = m; },
    // ENOSYS-stub every preview1 import the module needs but the shim above
    // doesn't implement (a reactor pulls in more of preview1 than a command —
    // liolib drags in fd_fdstat_set_flags etc.). Loudly absent (errno 52),
    // never silently wrong. A no-op for a command module that imports only the
    // calls above.
    autostub(module) {
      for (const imp of WebAssembly.Module.imports(module)) {
        if (imp.module === 'wasi_snapshot_preview1' && !(imp.name in imports)) {
          imports[imp.name] = () => 52;  // ENOSYS
        }
      }
    },
    // Accumulated fd_write output across every fd (the witnesses only write to
    // stdout/stderr and match on substrings).
    get stdout() { return stdout; },
  };
}
