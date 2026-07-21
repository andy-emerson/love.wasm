// love_system host — the browser/node fulfiller for the step-6.6 love.system
// seam. It stands in for the browser's real system capabilities: processor count
// (navigator.hardwareConcurrency), the text clipboard (a host-held cell fronting
// the async Clipboard API), openURL (window.open), and the preferred locales
// (navigator.languages). On a real page the host wires these to those browser
// APIs; here it bakes DETERMINISTIC values so the witness is identical on both
// legs (node has no navigator).
//
// Self-contained BY CONTRACT, like wasi-shim.mjs / fs-host.mjs / input-host.mjs:
// no imports, no outer-scope references, so makeSystemHost.toString() stringifies
// into a Playwright page and rebuilds with new Function(), and the SAME host runs
// under node (TextEncoder/TextDecoder/DataView are globals in both).
//
//   const sys = makeSystemHost();
//   ... instantiate with { love_system: sys.imports } ...
//   sys.bind(instance.exports.memory);   // before any import fires
//
// The string reads use the two-call size-then-copy shape the love_fs seam uses,
// so the synchronous LÖVE contract is preserved over host-held values.
export function makeSystemHost() {
  let memory;
  const te = new TextEncoder(), td = new TextDecoder();

  // Deterministic baked values (a real host swaps these for navigator.*).
  let clipboard = te.encode('love-wasi clipboard');
  const PROCESSOR_COUNT = 4;
  const LOCALES = ['en-US', 'en'];

  // Side effects a leg can assert.
  const effects = { openedURLs: [] };

  const readPath = (ptr, len) => td.decode(new Uint8Array(memory.buffer, ptr, len));

  const imports = {
    system_processor_count() { return PROCESSOR_COUNT; },

    system_clipboard_size() { return clipboard.length; },
    system_clipboard_read(bufPtr, cap) {
      const n = Math.min(cap, clipboard.length);
      new Uint8Array(memory.buffer, bufPtr, n).set(clipboard.subarray(0, n));
      return n;
    },
    system_clipboard_write(ptr, len) {
      clipboard = te.encode(readPath(ptr, len));
    },

    system_open_url(ptr, len) {
      const url = readPath(ptr, len);
      effects.openedURLs.push(url);
      // On a real page: window.open(url, '_blank'). The witness only needs the
      // call to be observed and to report success.
      return 1;
    },

    system_locale_count() { return LOCALES.length; },
    system_locale_read(index, bufPtr, cap) {
      if (index < 0 || index >= LOCALES.length) return -1;
      const bytes = te.encode(LOCALES[index]);
      const n = Math.min(cap, bytes.length);
      new Uint8Array(memory.buffer, bufPtr, n).set(bytes.subarray(0, n));
      return n;
    },
  };

  return {
    imports,
    bind(m) { memory = m; },
    // Exposed so a leg can assert against the baked values.
    processorCount: PROCESSOR_COUNT,
    locales: LOCALES,
    effects,
    clipboardText() { return td.decode(clipboard); },
  };
}
