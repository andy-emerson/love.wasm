// Browser leg of the UNION "real game" witness — the pre-step-7 capstone. The
// union artifact (LÖVE core + filesystem + window + graphics/WebGL2 + image + font
// + event/keyboard/mouse + timer + system + AUDIO + SOUND + PHYSICS) boots LÖVE's
// real boot.lua under the pump and runs an actual game end to end:
//   conf.lua (real love.filesystem) sizes the canvas -> love.window.setMode opens
//   the WebGL2 context -> love.load DECODES + PLAYS a real Ogg asset (love.sound
//   over love.filesystem, love.audio) and builds a PHYSICS world with a falling
//   body -> love.run's loop steps physics and draws the body red each frame.
//
// The host is the UNION of the sub-step hosts over ONE real WebGL2 context:
//   love_gl + love_win -> webgl-win-host (canvas/context, present, readPixel)
//   love_fs            -> fs-host, its project OVERRIDDEN with this game's
//                         conf.lua + main.lua + the real clickmono.ogg asset
//   love_audio         -> audio-host (source_* + mic_*; taps queued PCM)
//   love_input         -> an empty queue; love_system -> system-host
//
// After pumping the driver asserts the union worked, by transcript + one pixel:
//   (1) stdout has UNION-GAME-LOAD           -> love.load ran through real boot
//   (2) stdout has UNION-SOUND-DECODED n>0   -> love.sound decoded the Ogg read
//                                               through love.filesystem
//   (3) stdout has UNION-PHYSICS-FELL        -> love.physics simulated (body fell)
//   (4) a RED pixel on the canvas            -> love.graphics drew the physics body
//   (bonus) audio host captured a Source's PCM -> playback reached the seam
//
// Chromium-only (needs a real WebGL2 context). Usage: node run-browser-game.mjs <wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const b64 = readFileSync(process.argv[2] ?? join(here, 'love-game.wasm')).toString('base64');
const oggB64 = readFileSync(join(root, 'testing/resources/clickmono.ogg')).toString('base64');
// The boot source is LÖVE's real boot wrapper (game-agnostic): it requires love,
// then runs love.boot, which reads conf.lua/main.lua from love.filesystem — which
// we override below with this game. Reused verbatim from the frame witness.
const boot = readFileSync(join(here, 'witness-frame.lua'), 'utf8');

// The game — a normal LÖVE 12 project (runs identically on desktop LÖVE). It
// reads its sound asset through love.filesystem, decodes + plays it, and draws a
// physics-simulated body. conf.lua disables the modules this build does not link.
const gameConf = `
function love.conf(t)
  t.identity = "uniongame"
  t.window.width = 64
  t.window.height = 64
  t.window.title = "love-wasi union game"
  t.modules.joystick = false
  t.modules.touch = false
  t.modules.sensor = false
  t.modules.video = false
  t.modules.thread = false
end
`;
const gameMain = `
local world, body, startY, frames
function love.load()
  print("UNION-GAME-LOAD")
  -- love.sound decodes a real Ogg asset read through love.filesystem; love.audio
  -- plays it. Passing a filepath string exercises the real filesystem File path.
  local sd = love.sound.newSoundData("sound.ogg")
  print("UNION-SOUND-DECODED samples=" .. tostring(sd:getSampleCount()))
  local src = love.audio.newSource(sd)
  src:play()
  print("UNION-SOUND-PLAYING")
  -- love.physics: a world with downward gravity and a dynamic body that falls.
  world = love.physics.newWorld(0, 400, true)
  body = love.physics.newBody(world, 32, 6, "dynamic")
  love.physics.newRectangleShape(body, 0, 0, 12, 12)
  frames = 0
end
function love.update(dt)
  world:update(1 / 60)
  frames = frames + 1
  if frames == 1 then startY = select(2, body:getPosition()) end
  if frames == 40 then
    local y = select(2, body:getPosition())
    if y > startY + 2 then
      print(("UNION-PHYSICS-FELL %.2f -> %.2f"):format(startY, y))
    end
  end
end
function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 0, 0, 1)
  local x, y = body:getPosition()
  y = math.max(6, math.min(y, 56))   -- keep the drawn body on the 64x64 canvas
  love.graphics.rectangle("fill", 26, y - 6, 12, 12)
end
`;

async function gamePageFn({ b64, boot, gameConf, gameMain, oggB64, shimSrc, winHostSrc, fsHostSrc, systemHostSrc, audioHostSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const te = new TextEncoder(), td = new TextDecoder();
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + winHostSrc)())();
  const fs = (new Function('return ' + fsHostSrc)())();
  const system = (new Function('return ' + systemHostSrc)())();
  const audio = (new Function('return ' + audioHostSrc)())();
  const lines = [];
  const log = (s) => lines.push(s);

  if (!host.haveContext()) return { ok: false, lines, error: 'no WebGL2 context' };

  // Override the fs-host's canned project with THIS game + the real Ogg asset.
  fs.files['conf.lua'] = te.encode(gameConf);
  fs.files['main.lua'] = te.encode(gameMain);
  fs.files['sound.ogg'] = Uint8Array.from(atob(oggB64), c => c.charCodeAt(0));

  const input = {
    input_poll() { return 0; },
    input_set_cursor_visible() {}, input_set_cursor_shape() {},
    input_warp() {}, input_set_relative() { return 0; }, input_set_text_input() {},
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
      love_audio: audio.imports,
    });
    const x = instance.exports;
    shim.bind(x.memory);
    host.bind(x.memory, x.malloc);
    fs.bind(x.memory);
    system.bind(x.memory);
    audio.bind(x.memory);
    x._initialize();

    const put = (s) => { const b = te.encode(s); const p = x.pump_in(b.length); new Uint8Array(x.memory.buffer).set(b, p); return b.length; };
    const out = () => { const p = x.pump_out(); return td.decode(new Uint8Array(x.memory.buffer).slice(p, p + x.pump_out_len())); };
    const tick = () => new Promise((r) => requestAnimationFrame(r));

    let st = x.pump_boot(put(boot));
    log('pump_boot status ' + st + (st < 0 ? (' out: ' + out()) : ''));
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'boot error: ' + out() };

    const FRAMES = 50;
    for (let i = 0; i < FRAMES && st >= 0; i++) {
      await tick();
      st = x.pump_frame(put('t'));
    }
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'frame error: ' + out() };

    const stdout = shim.stdout || '';
    const loadSeen = stdout.indexOf('UNION-GAME-LOAD') !== -1;
    const soundMatch = stdout.match(/UNION-SOUND-DECODED samples=(\d+)/);
    const soundOk = !!soundMatch && Number(soundMatch[1]) > 0;
    const physicsSeen = stdout.indexOf('UNION-PHYSICS-FELL') !== -1;

    // Scan the canvas centre column for a RED pixel (the physics body, drawn red).
    const [cw, ch] = host.canvasSize();
    let redSeen = false, redAt = null;
    for (let y = 0; y < ch && !redSeen; y++) {
      const px = host.readPixel(cw >> 1, y);
      if (px && px[0] > 200 && px[1] < 80 && px[2] < 80) { redSeen = true; redAt = y; }
    }

    // Bonus: did any Source's PCM reach the audio host tap?
    let audioSources = 0, audioPcm = 0;
    try { const list = audio.sources ? audio.sources() : []; audioSources = list.length; for (const s of list) audioPcm += (s.pcm ? s.pcm.length : 0); } catch (e) {}

    log('load marker: ' + loadSeen);
    log('sound decoded: ' + soundOk + (soundMatch ? (' (samples=' + soundMatch[1] + ')') : ''));
    log('physics fell: ' + physicsSeen);
    log('red pixel: ' + redSeen + (redAt !== null ? (' at centre-column y=' + redAt) : ''));
    log('audio host: ' + audioSources + ' source(s), ' + audioPcm + ' pcm frames captured');

    const ok = loadSeen && soundOk && physicsSeen && redSeen && st >= 0;
    return { ok, lines, stdout };
  } catch (e) {
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, stdout: shim.stdout, error };
  }
}

const result = await runInChromium(gamePageFn, {
  b64, boot, gameConf, gameMain, oggB64,
  shimSrc: makeWasiShim.toString(),
  winHostSrc: makeWebGLWinHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  systemHostSrc: makeSystemHost.toString(),
  audioHostSrc: makeAudioHost.toString(),
});

console.log('--- browser transcript ---');
for (const line of result.lines || []) console.log(line);
if (result.stdout) console.log('--- wasm stdout (host tap) ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
console.log('UNION-GAME-WITNESS: ' + (result.ok ? 'PASS' : 'FAIL'));
process.exit(result.ok ? 0 : 1);
