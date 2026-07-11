// Real-WebGL2 love_gl host for the raw-GL witness (step 4.1a), Chromium leg.
//
// The fidelity counterpart to the mock gl-host.mjs, as mic-host-browser.mjs is
// to the mock audio host: instead of emulating the framebuffer, it drives a
// real WebGL2 context (an OffscreenCanvas) so the cleared pixel is recovered
// from the browser's actual GL implementation, then copied back into wasm
// linear memory via glReadPixels — the same round-trip a real preview does.
//
// Self-contained by contract (no imports, no outer-scope refs): it is
// stringified and serialized into the page like the other browser hosts.
export function makeBrowserGLHost() {
  let memory;
  const canvas = new OffscreenCanvas(4, 4);
  // preserveDrawingBuffer so the cleared framebuffer survives until readPixels.
  const gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, alpha: true });
  const u8 = (ptr, len) => new Uint8Array(memory.buffer, ptr, len);

  const imports = {
    glClearColor(r, g, b, a) { gl.clearColor(r, g, b, a); },
    glClear(mask) { gl.clear(mask); },
    glReadPixels(x, y, w, h, format, type, ptr) {
      const tmp = new Uint8Array(w * h * 4);
      gl.readPixels(x, y, w, h, format, type, tmp);
      u8(ptr, w * h * 4).set(tmp);
    },
  };

  return {
    imports,
    bind(m) { memory = m; },
    haveContext() { return !!gl; },
  };
}
