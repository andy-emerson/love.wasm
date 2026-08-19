// Frame leg of the love.shim witness — the last two entries, which no other leg
// can reach.
//
// love.graphics.stencil and ParticleSystem:get/setAreaSpread need a live GL
// context that Lua can use. The graphics artifact has a context but drives every
// draw from C++ helpers that leave none open, so those legs could only skip. The
// FRAME artifact is different: LÖVE's own boot calls love.window.setMode, and
// love.draw then runs with the context current — the same place a real game
// would call these functions.
//
// So this leg runs a real game (frame-game.lua) through the real boot, with
// love.shim preloaded as a module. The game prints SHIMFRAME lines; this runner
// asserts on them.
// Usage: node run-browser-frame-shim.mjs <love-frame.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const shimLua = readFileSync(join(here, 'love-shim.lua'), 'utf8');
const gameLua = readFileSync(join(here, 'frame-game.lua'), 'utf8');
// The boot wrapper is the frame witness's, unchanged: it seeds `arg`, requires
// love, satisfies require for unlinked modules, and runs LÖVE's real boot. The
// only addition is love.shim in package.preload, which is the same door LÖVE's
// own submodules arrive through — so the game requires it exactly as it would
// once the boot wrapper registers it for real.
const frameBoot = readFileSync(join(here, '..', 'platform', 'witness-frame.lua'), 'utf8');
const boot = `package.preload["love.shim"] = function(...)\n${shimLua}\nend\n${frameBoot}`;
const b64 = readFileSync(process.argv[2] ?? 'love-frame.wasm').toString('base64');

async function pageFn({ b64, boot, gameSrc, shimSrc, winHostSrc, fsHostSrc, systemHostSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + winHostSrc)())();
  const fs = (new Function('return ' + fsHostSrc)())();
  const system = (new Function('return ' + systemHostSrc)())();
  const lines = [];
  const log = (s) => lines.push(s);

  if (!host.haveContext()) return { ok: false, lines, error: 'no WebGL2 context' };

  // Swap the canned project for the shim game. The fs host exposes its file map
  // precisely so a leg can do this; conf.lua is left as it is, since the canvas
  // it asks for is what gives love.draw a context to draw into.
  fs.files['main.lua'] = new TextEncoder().encode(gameSrc);

  const input = {
    input_poll() { return 0; },
    input_set_cursor_visible() {}, input_set_cursor_shape() {},
    input_warp() {}, input_set_relative() { return 0; },
    input_set_text_input() {}, input_new_cursor_image() { return 0; },
    input_set_cursor_image() {},
  };

  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: host.glImports, love_win: host.winImports,
      love_fs: fs.imports, love_input: input, love_system: system.imports,
    });
    const x = instance.exports;
    shim.bind(x.memory); host.bind(x.memory, x.malloc);
    fs.bind(x.memory); system.bind(x.memory);
    x._initialize();

    const te = new TextEncoder(), td = new TextDecoder();
    const mem = () => new Uint8Array(x.memory.buffer);
    const put = (s) => { const b = te.encode(s); const p = x.pump_in(b.length); mem().set(b, p); return b.length; };
    const out = () => { const p = x.pump_out(); return td.decode(mem().slice(p, p + x.pump_out_len())); };
    const tick = () => new Promise((r) => requestAnimationFrame(r));

    let st = x.pump_boot(put(boot));
    log('pump_boot status ' + st + (st < 0 ? (' out: ' + out()) : ''));
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'boot error: ' + out() };

    for (let i = 0; i < 6 && st >= 0; i++) {
      await tick();
      st = x.pump_frame(put('t'));
    }
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'frame error: ' + out() };

    const stdout = shim.stdout || '';
    for (const line of stdout.split('\n')) if (line.startsWith('SHIMFRAME')) log(line);

    const began = stdout.includes('SHIMFRAME-BEGIN');
    const passed = /SHIMFRAME-PASS \d+ checks/.test(stdout);
    const anyFail = stdout.includes('SHIMFRAME FAIL') || stdout.includes('SHIMFRAME-FAIL');
    log('began: ' + began + '  passed: ' + passed + '  anyFail: ' + anyFail);

    // The game also still draws red, so this leg remains a valid frame witness:
    // if the context were not really live, love.draw could not have painted.
    const [cw, ch] = host.canvasSize();
    const px = host.readPixel(cw >> 1, ch >> 1);
    const near = (v, e) => v != null && Math.abs(v - e) <= 2;
    const isRed = !!px && near(px[0], 255) && near(px[1], 0) && near(px[2], 0);
    log('centre pixel is RED (context really live): ' + isRed);

    return { ok: began && passed && !anyFail && isRed, lines, stdout };
  } catch (e) {
    return { ok: false, lines, stdout: shim.stdout, error: String(e && e.stack || e) };
  }
}

const result = await runInChromium(pageFn, {
  b64, boot, gameSrc: gameLua,
  shimSrc: makeWasiShim.toString(),
  winHostSrc: makeWebGLWinHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  systemHostSrc: makeSystemHost.toString(),
});

console.log('--- frame shim transcript ---');
for (const line of result.lines) console.log(line);
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
