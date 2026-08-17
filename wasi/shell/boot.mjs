// The library entry point (#57). Everything a consumer must wire identically to
// run love.wasm — the eight import modules at instantiate, the memory binds, the
// import-surface check, the pump marshalling, the stdout tap, pump_boot, the
// requestAnimationFrame loop with the blur/visibility pause — is one exported
// call. Before this, that wiring lived only inside player.mjs's main() and could
// be copied but not called, and a copy breaks silently on the consumer's
// timeline whenever the import surface moves (as it did when fs_stat gained
// `readonly`, and again when #51 added glGetStringi).
//
// What genuinely varies per consumer is the parameter list — above all which
// files, which canvas, and where the log goes. player.mjs is the first caller;
// EMBEDDING.md documents this as the recommended consumption shape.
//
//   import { boot } from './boot.mjs';
//   const handle = await boot({ wasm, bootSrc, files, canvas, onLog });
//
// Importable without side effects: nothing here touches the DOM or the network
// until boot() is called.
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeOpfsSaves } from '../host/fs-opfs.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { makeGamepadHost } from '../host/gamepad-host.mjs';
import { makeBrowserInputHost } from '../host/input-host-browser.mjs';

// boot(options) -> handle. Options:
//   wasm     — the artifact: a compiled WebAssembly.Module (compile it yourself
//              to keep compileStreaming), or raw bytes to compile here.
//   bootSrc  — the Lua boot chunk (LÖVE's own boot wrapper,
//              wasi/platform/witness-frame.lua — see EMBEDDING.md §1).
//   files    — path -> Uint8Array, the EMBEDDING.md §2 project contract: the map
//              IS the interface, however the consumer produced it (player.mjs
//              fetches a manifest; an in-page editor fills it directly). A plain
//              object or a Map. Omitted, the reference host's canned project runs.
//   canvas   — (w, h) => HTMLCanvasElement. love.window.setMode decides the
//              size, so the consumer is asked for a canvas when the game asks
//              for a window, not before.
//   onLog    — (line) => void: the game's stdout (print/io.write) and host notes.
//   onStatus — (state, detail) => void: 'running' | 'paused' (detail = why) |
//              'error' (detail = the Lua error + traceback) | 'quit'.
//   opfs     — false disables the OPFS save store (#55) and keeps saves
//              in-memory, the reference-host behaviour; anything else uses OPFS
//              when the browser has it. The knob exists so the durability
//              witness can demonstrate its own failure mode.
//   identity — the save namespace's directory name. Defaults to t.identity as
//              written in the project's conf.lua, which the host must read for
//              itself: hydration has to finish before boot, and the engine only
//              reports the identity after. A consumer whose identity is
//              computed at runtime passes it explicitly.
//
// The handle: stop(), invalidate() and hotswap(path) (the live-edit reload
// primitives, EMBEDDING.md §4), quit(), the fs stores (files to mutate for
// live-edit, saves), and running/paused as live state.
//
// Failure is loud: a boot-time Lua error, a missing import, or an instantiate
// failure all throw — there is no handle to return for a game that never ran.
export async function boot({
  wasm, bootSrc, files = null, canvas,
  onLog = () => {}, onStatus = () => {},
  opfs = true, identity = null,
} = {}) {
  // The game's stdout streams to the consumer as the engine writes it — Lua's
  // print flushes per call — so an agent's probe inside love.update surfaces in
  // the frame it fired rather than whenever a buffer happened to fill. Whole
  // lines only: a write can end mid-line, and splitting one line across two
  // onLog calls corrupts a console that treats each call as an entry.
  let pending = '';
  const shim = makeWasiShim({
    onWrite(text) {
      pending += text;
      let nl;
      while ((nl = pending.indexOf('\n')) >= 0) {
        onLog(pending.slice(0, nl));
        pending = pending.slice(nl + 1);
      }
    },
  });
  const input = makeBrowserInputHost();
  // The consumer says where a canvas comes from; wiring the input listeners to
  // it and focusing it (so keys land without a click) is invariant, so it
  // happens here rather than in every consumer.
  const win = makeWebGLWinHost((w, h) => {
    const c = canvas(w, h);
    input.attach(c);
    c.focus();
    return c;
  });
  let fs = makeFsHost();
  const system = makeSystemHost();
  const audio = makeAudioHost();
  const gamepad = makeGamepadHost();

  if (files) {
    for (const k of Object.keys(fs.files)) delete fs.files[k];
    for (const [name, bytes] of files instanceof Map ? files : Object.entries(files))
      fs.files[name] = bytes;
  }

  // The OPFS save store (#55, D2) — durability across page reloads. Hydration
  // must complete BEFORE pump_boot: love.boot reads conf.lua and main.lua on
  // its very first frame, and a save written last session must already shadow
  // the project when it does. Node-side callers fall through to the in-memory
  // store automatically (no navigator.storage there).
  const haveOpfs = typeof navigator !== 'undefined' && navigator.storage
    && typeof navigator.storage.getDirectory === 'function';
  if (opfs !== false && haveOpfs) {
    const ident = identity || (() => {
      const conf = fs.files['conf.lua'];
      const m = conf && /t\.identity\s*=\s*["']([^"']+)["']/.exec(new TextDecoder().decode(conf));
      return m ? m[1] : 'default';
    })();
    fs = makeOpfsSaves(fs, { identity: ident, onWarn: onLog });
    const h = await fs.hydrate();
    onLog(`saves: OPFS "${ident}" (${h.files} file(s) hydrated)`);
  } else {
    onLog('saves: in-memory (' + (opfs === false ? 'OPFS disabled — saves will not survive a reload' : 'no OPFS in this environment') + ')');
  }

  const module = wasm instanceof WebAssembly.Module ? wasm : await WebAssembly.compile(wasm);

  shim.autostub(module);
  const importObject = {
    wasi_snapshot_preview1: shim.imports,
    love_gl: win.glImports,
    love_win: win.winImports,
    love_fs: fs.imports,
    love_input: input.imports,
    love_gamepad: gamepad.imports,
    love_system: system.imports,
    love_audio: audio.imports,
  };

  // The skew check (#7/#57): when the artifact's import surface outgrows the
  // host, fail HERE with the missing names, not at first call with whatever a
  // LinkError happens to say. autostub has already filled preview1, so anything
  // still missing is a love_* seam the host genuinely does not fulfil.
  const missing = WebAssembly.Module.imports(module)
    .filter((i) => !(importObject[i.module] && i.name in importObject[i.module]))
    .map((i) => i.module + '.' + i.name);
  if (missing.length)
    throw new Error('the host does not fulfil the module\'s import surface: ' + missing.join(', '));

  const instance = await WebAssembly.instantiate(module, importObject);
  const x = instance.exports;
  // Bind before any import can fire.
  shim.bind(x.memory);
  win.bind(x.memory, x.malloc);
  fs.bind(x.memory);
  system.bind(x.memory);
  audio.bind(x.memory);
  gamepad.bind(x.memory);
  input.bind(x.memory);
  x._initialize();

  const te = new TextEncoder(), td = new TextDecoder();
  // pump_in hands back a pointer to write into; take it before viewing memory,
  // since a growth during the call would detach an earlier view.
  const put = (s) => {
    const b = te.encode(s);
    const p = x.pump_in(b.length);
    new Uint8Array(x.memory.buffer).set(b, p);
    return b.length;
  };
  const out = () => {
    const p = x.pump_out();
    return td.decode(new Uint8Array(x.memory.buffer).slice(p, p + x.pump_out_len()));
  };

  // Whole lines already left through onWrite; this flushes a trailing partial
  // line (io.write without a newline) so it is not held back to the next one.
  const drainTap = () => { if (pending) { onLog(pending); pending = ''; } };

  let st = x.pump_boot(put(bootSrc));
  drainTap();
  if (st === -2) throw new Error(out());

  // Frame cadence is the browser's, and a hidden or unfocused tab gets none: a
  // game must not keep simulating in a tab nobody is looking at. love.timer's dt
  // comes from the pump, so a paused tab resumes without a giant time step.
  let running = true, paused = false, raf = 0;
  onStatus('running');

  const pause = (why) => { if (running && !paused) { paused = true; onStatus('paused', why); } };
  const resume = () => { if (running && paused) { paused = false; onStatus('running'); } };
  const onBlur = () => pause('unfocused');
  const onVis = () => (document.visibilityState === 'visible' ? resume() : pause('tab hidden'));
  addEventListener('blur', onBlur);
  addEventListener('focus', resume);
  document.addEventListener('visibilitychange', onVis);
  const detach = () => {
    removeEventListener('blur', onBlur);
    removeEventListener('focus', resume);
    document.removeEventListener('visibilitychange', onVis);
  };

  const frame = () => {
    if (!running) return;
    if (paused) { raf = requestAnimationFrame(frame); return; }
    st = x.pump_frame(put('t'));
    drainTap();
    if (st === -2) { running = false; detach(); onStatus('error', out()); return; }
    if (st < 0) { running = false; detach(); onStatus('quit'); return; }
    raf = requestAnimationFrame(frame);
  };
  raf = requestAnimationFrame(frame);

  return {
    // The fs stores, live: mutate files then invalidate() for live-edit (§4);
    // saves is the writable namespace the game's love.filesystem writes land in.
    files: fs.files,
    saves: fs.saves,
    // Resolves when every save flush issued so far has settled. On the
    // in-memory store there is nothing to wait for.
    flushed: fs.flushed || (() => Promise.resolve()),
    get running() { return running; },
    get paused() { return paused; },
    invalidate: () => x.pump_invalidate(),
    // Function-body hotswap (D4=B, EMBEDDING.md §4): apply an edited file's new
    // function bodies to the running game, live state intact. Put the file's
    // new bytes in `files` first. Returns {ok:true, swapped} or {ok:false,
    // error} carrying the edit's OWN Lua error — the engine performs the swap,
    // it does not validate it, and the game keeps running on the old code
    // either way.
    //
    // D5=E: `swapped` is a count and cannot tell "applied everything" from
    // "applied some", so the engine also reports per binding. `applied` is what
    // took effect; `residue` is what the swap could NOT apply — today that is a
    // binding this file used to define and no longer does, whose old value is
    // still live because nothing overwrote it. A consumer that ignores
    // `residue` shows the user a success for an edit that did not happen.
    hotswap: (path) => {
      const st = x.pump_hotswap(put(path));
      drainTap();
      if (st === -3) return { ok: false, error: 'the pump is not booted' };
      if (st === -2) return { ok: false, error: out() };
      const applied = [], residue = [];
      for (const line of (out() || '').split('\n')) {
        if (!line) continue;
        const [kind, name, status] = line.split('\t');
        (kind === 'residue' ? residue : applied).push({ name, status });
      }
      return { ok: true, swapped: st, applied, residue };
    },
    // A browser tab has no close button the game owns, so quitting is explicit:
    // push the quit event and let love.run wind down normally next frame.
    quit: () => input.quit(),
    stop() { if (!running) return; running = false; cancelAnimationFrame(raf); detach(); },
  };
}
