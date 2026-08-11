// Mock love_gl host for the raw-GL witness (step 4.1a), node leg.
//
// The deterministic counterpart to the real-WebGL2 browser host (gl-host-
// browser.mjs), exactly as audio-host.mjs (the mock PCM tap) is the counterpart
// to the real OfflineAudioContext/getUserMedia legs. It implements just enough
// of the GL import surface to round-trip a cleared pixel: it records the clear
// color and, on glReadPixels, writes that color back into wasm linear memory —
// proving the wasm<->host plumbing and the readback path without a real GL
// context. Fidelity against a real WebGL2 framebuffer is the browser leg's job.
//
// Self-contained by contract (no imports, no outer-scope refs), so it can be
// stringified and serialized into a page the same way the other hosts are.
export function makeGLHost() {
  let memory;
  const clear = new Uint8Array([0, 0, 0, 255]);   // last cleared color, RGBA8
  const u8 = (ptr, len) => new Uint8Array(memory.buffer, ptr, len);
  const to8 = (c) => Math.max(0, Math.min(255, Math.round(c * 255)));

  const imports = {
    glClearColor(r, g, b, a) { clear[0] = to8(r); clear[1] = to8(g); clear[2] = to8(b); clear[3] = to8(a); },
    glClear(_mask) { /* framebuffer is conceptually the clear color; nothing to store */ },
    glReadPixels(x, y, w, h, _format, _type, ptr) {
      const dst = u8(ptr, w * h * 4);
      for (let i = 0; i < w * h; i++) dst.set(clear, i * 4);
    },
  };

  return {
    imports,
    bind(m) { memory = m; },
    clearColor() { return Array.from(clear); },
  };
}
