// Chromium leg of the step-6.3 love.window witness: the LÖVE core + real
// love.window + love.graphics booting under the pump in real Chromium, with the
// combined love_gl + love_win host (wasi/host/webgl-win-host.mjs) serving both
// import modules over ONE real WebGL2 context. love.window.setMode drives the
// host to create the canvas + context, graphics binds to it, and present() reads
// the presented backbuffer back for the captureScreenshot close of step 4.
//
// This is Chromium-only: it needs a real WebGL2 context (node has no WebGL2),
// the same constraint the graphics real-backend legs carry. The in-page function
// is self-contained (serialized by Playwright): it rebuilds the WASI shim, the
// combined host, and the driver from source, instantiates the reactor with both
// import modules, binds memory + the exported malloc (glGetString needs it), runs
// the ctors, and drives the witness lua.
// Usage: node run-browser-win.mjs <love-win.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const boot = readFileSync(process.argv[3] ?? join(here, 'witness-win.lua'), 'utf8');
const b64 = readFileSync(process.argv[2] ?? join(here, 'love-win.wasm')).toString('base64');

async function loveWinPageFn({ b64, boot, shimSrc, hostSrc, driverSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + hostSrc)())();
  if (!host.haveContext()) return { ok: false, lines: [], error: 'no WebGL2 context' };
  const lines = [];
  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: host.glImports,
      love_win: host.winImports,
    });
    shim.bind(instance.exports.memory);
    host.bind(instance.exports.memory, instance.exports.malloc);
    instance.exports._initialize();
    const drive = (new Function('return ' + driverSrc)());
    const ok = await drive(instance.exports, boot, (cb) => requestAnimationFrame(cb), (l) => lines.push(l));
    // #58 witness taps: the set-display-sleep requests the host observed, the
    // wake lock's real state, and the page's own theme truth to cross-check the
    // guest's getSystemTheme answer against.
    return {
      ok, lines, stdout: shim.stdout,
      winEffects: host.winEffects,
      wakeLock: host.wakeLockState(),
      pageTheme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light',
    };
  } catch (e) {
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, stdout: shim.stdout, error };
  }
}

const result = await runInChromium(loveWinPageFn, {
  b64, boot,
  shimSrc: makeWasiShim.toString(),
  hostSrc: makeWebGLWinHost.toString(),
  driverSrc: driveWitness.toString(),
});

console.log('--- browser transcript ---');
for (const line of result.lines || []) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');

// ── #58 host-side assertions ─────────────────────────────────────────────────
// The Lua checks prove the guest surface; these prove the HOST observed the
// requests and that the guest's answers matched the browser's real state.
let hostOk = true;
const hostCheck = (name, cond, got) => {
  if (cond) { console.log('ok   [host] ' + name); return; }
  hostOk = false;
  console.log('FAIL [host] ' + name + '   got: ' + JSON.stringify(got));
};
if (result.ok) {
  const fx = result.winEffects || {};
  // The guest asked to disable display sleep (0 = request the lock), then to
  // re-enable it (1 = release) — exactly once each, in that order.
  hostCheck('host observed the wake-lock request then the release [0,1]',
    JSON.stringify(fx.displaySleep) === '[0,1]', fx.displaySleep);
  // After the release no lock may remain held, granted or not.
  hostCheck('no wake lock held after release', result.wakeLock && result.wakeLock.held === false, result.wakeLock);
  // The guest's held-report must agree with whether the browser ever granted
  // the lock: claiming "held" without a grant would be the lie the honest
  // request-and-report shape exists to prevent.
  const heldLine = (result.lines || []).find((l) => l.startsWith('wake lock held after request: '));
  const claimedHeld = heldLine === 'wake lock held after request: true';
  hostCheck('the guest claimed the lock held only if the browser granted it',
    !!heldLine && (!claimedHeld || (result.wakeLock && result.wakeLock.everHeld)),
    { heldLine, wakeLock: result.wakeLock });
  console.log('[host] wake-lock grant in this environment: ' + JSON.stringify(result.wakeLock));
  // getSystemTheme must be the page's own matchMedia truth, not a constant.
  hostCheck("getSystemTheme() agrees with the page's prefers-color-scheme",
    (result.lines || []).includes('getSystemTheme() = ' + result.pageTheme),
    { pageTheme: result.pageTheme });
}

process.exit(result.ok && hostOk ? 0 : 1);
