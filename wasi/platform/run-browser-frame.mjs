// Chromium leg of the step-6.6b FIRST-FRAME witness — THE MILESTONE. The union
// artifact (LÖVE core + real filesystem + window + graphics/WebGL2 + image + font
// + event/keyboard/mouse + timer + system) boots LÖVE's real boot.lua under the
// pump and runs an actual game to a drawn pixel:
//   conf.lua (real love.filesystem) -> love.window.setMode opens the canvas at the
//   conf dimensions -> love.load (prints a unique MARKER to the host tap) ->
//   love.run's loop yields once per frame running event.pump / timer.step /
//   update / clear / draw / present.
//
// The host is the UNION of the sub-step hosts over ONE real WebGL2 context:
//   love_gl + love_win  -> webgl-win-host (creates the canvas/context in
//                          window_setmode, presents in window_present, and exposes
//                          readPixel for the backbuffer readback)
//   love_fs             -> fs-host (the canned conf.lua + main.lua project)
//   love_input          -> an EMPTY queue (input_poll returns 0; love.run's
//                          event.pump must find nothing — no DOM events injected)
//   love_system         -> system-host (getOS "Web", processor count, locales)
//
// After pumping several frames the driver asserts three things and prints the
// verdict STEP66-FRAME-WITNESS: PASS/FAIL:
//   (1) the host tap (fd 1) contains the love.load MARKER  -> love.load ran
//       through the real boot;
//   (2) the presented backbuffer's centre pixel is RED     -> conf -> canvas ->
//       load -> draw -> present ran a real frame end to end;
//   (3) no Lua error / no proc_exit                         -> the loop ran clean.
//
// Chromium-only: it needs a real WebGL2 context (node has no WebGL2), exactly like
// the 6.3 window witness and the step-4 graphics witnesses. A node leg is not
// possible and not expected.
// Usage: node run-browser-frame.mjs <love-frame.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const boot = readFileSync(process.argv[3] ?? join(here, 'witness-frame.lua'), 'utf8');
const b64 = readFileSync(process.argv[2] ?? join(here, 'love-frame.wasm')).toString('base64');
const MARKER = 'STEP66B-LOVE-LOAD-MARKER-7F3A9C';

// Self-contained page function (serialized by Playwright): rebuilds the shim +
// the three hosts + an empty input host from source, instantiates the reactor
// with every import module, drives the pump several frames, then reads the
// centre pixel back through the WebGL2 context and checks the MARKER + verdict.
async function framePageFn({ b64, boot, marker, shimSrc, winHostSrc, fsHostSrc, systemHostSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + winHostSrc)())();
  const fs = (new Function('return ' + fsHostSrc)())();
  const system = (new Function('return ' + systemHostSrc)())();
  const lines = [];
  const log = (s) => lines.push(s);

  if (!host.haveContext()) return { ok: false, lines, error: 'no WebGL2 context' };

  // An EMPTY love_input host: love.run's event.pump drains input_poll, which must
  // report an empty queue (0). No DOM events are injected — the frame is driven by
  // the pump, not by input.
  const input = {
    input_poll() { return 0; },
    input_set_cursor_visible() {},
    input_set_cursor_shape() {},
    input_warp() {},
    input_set_relative() { return 0; },
    input_set_text_input() {},
  };

  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: host.glImports,
      love_win: host.winImports,
      love_fs: fs.imports,
      love_input: input,
      love_system: system.imports,
    });
    const x = instance.exports;
    shim.bind(x.memory);
    host.bind(x.memory, x.malloc);
    fs.bind(x.memory);
    system.bind(x.memory);
    x._initialize();

    // Pump ABI helpers (a fresh memory view each time — pump_in can grow it).
    const te = new TextEncoder(), td = new TextDecoder();
    const mem = () => new Uint8Array(x.memory.buffer);
    const put = (s) => { const b = te.encode(s); const p = x.pump_in(b.length); mem().set(b, p); return b.length; };
    const out = () => { const p = x.pump_out(); return td.decode(mem().slice(p, p + x.pump_out_len())); };
    const tick = () => new Promise((r) => requestAnimationFrame(r));

    // Boot: runs love.boot + love.init (conf -> setMode -> canvas) + love.run's
    // love.load, to the first per-frame yield.
    let st = x.pump_boot(put(boot));
    log('pump_boot status ' + st + (st < 0 ? (' out: ' + out()) : ''));
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'boot error: ' + out() };

    // Pump several real frames (enough for setMode + load + a draw + present).
    const FRAMES = 6;
    for (let i = 0; i < FRAMES && st >= 0; i++) {
      await tick();
      st = x.pump_frame(put('t'));
      log('frame ' + (i + 1) + ' status ' + st);
    }
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'frame error: ' + out() };

    // (1) MARKER in the host tap (fd 1) — love.load ran through the real boot.
    const stdout = shim.stdout || '';
    const markerSeen = stdout.indexOf(marker) !== -1;
    log('marker seen: ' + markerSeen);

    // (2) Read the presented backbuffer's centre pixel back through WebGL2.
    const [cw, ch] = host.canvasSize();
    log('canvas size: ' + cw + 'x' + ch);
    const px = host.readPixel(cw >> 1, ch >> 1);
    log('centre pixel rgba = (' + (px ? px.join(',') : 'null') + ')');
    const near = (v, e) => v != null && Math.abs(v - e) <= 2;
    const isRed = !!px && near(px[0], 255) && near(px[1], 0) && near(px[2], 0) && near(px[3], 255);
    log('centre pixel is RED: ' + isRed);

    const ok = markerSeen && isRed && st >= 0;
    return { ok, lines, stdout, marker: markerSeen, pixel: px, canvas: [cw, ch] };
  } catch (e) {
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, stdout: shim.stdout, error };
  }
}

const result = await runInChromium(framePageFn, {
  b64, boot, marker: MARKER,
  shimSrc: makeWasiShim.toString(),
  winHostSrc: makeWebGLWinHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  systemHostSrc: makeSystemHost.toString(),
});

console.log('--- browser transcript ---');
for (const line of result.lines || []) console.log(line);
if (result.stdout) console.log('--- wasm stdout (host tap) ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
console.log('STEP66-FRAME-WITNESS: ' + (result.ok ? 'PASS' : 'FAIL'));
process.exit(result.ok ? 0 : 1);
