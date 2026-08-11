// Beta step 3: run LÖVE's own conformance corpus (testing/) against this build
// and compare the result, test by test, against the expected-fail list.
//
// The corpus is upstream's, in this repository, so unlike the third-party game
// witness this one depends on nothing outside the tree and belongs in CI.
//
// It runs the union artifact exactly as a game: testing/ IS the project, its own
// conf.lua sizes the canvas, and boot.lua loads its main.lua. The suite runs
// itself across frames (love.update calls love.test:runSuite) and ends by calling
// love.event.quit(0), which the pump reports as PUMP_DONE — so the driver pumps
// until the pump says the game exited rather than guessing a frame count.
//
// The result is not scraped from the console. The suite writes a JUnit report
// through love.filesystem to tempoutput/lovetest_all.xml, which lands in the
// host's SAVE namespace — so the driver reads the bytes straight out of the same
// store the engine wrote them to, and parses per-test names from it.
//
// THE COMPARISON IS THE WITNESS, and it fails three ways:
//   1. a test expected to pass, failed        — a regression
//   2. a test on the expected-fail list, PASSED — the list is stale, which is a
//      good problem and still a failure: an unearned divergence is a lie
//   3. a test that failed and is on no list   — unclassified, so nobody decided
//
// Chromium-only: the corpus drives real love.graphics, so it needs a real WebGL2
// context. Usage: node run-browser-corpus.mjs <wasm> [expected.txt]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeInputHost } from '../host/input-host.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { makeGamepadHost } from '../host/gamepad-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const wasmPath = process.argv[2] ?? join(root, 'wasi/shell/love-game.wasm');
const expectedPath = process.argv[3] ?? join(here, 'expected.txt');
// Bootstrap mode: with no list yet, report what actually failed instead of
// failing on every one of them. Writing the list by hand from the triage would
// mean inventing method names; this prints the real ones.
const BOOTSTRAP = process.env.CORPUS_BOOTSTRAP === '1';

const b64 = readFileSync(wasmPath).toString('base64');
// LÖVE's real boot wrapper, game-agnostic — it requires love, then runs
// love.boot, which reads conf.lua/main.lua from love.filesystem. Reused verbatim
// from the frame and union-game witnesses, so the corpus boots the same way a
// game does.
const boot = readFileSync(join(root, 'wasi/platform/witness-frame.lua'), 'utf8');

// The whole testing/ tree as project-relative path -> base64 bytes. Read as
// bytes, never text: the corpus's resources are PNGs, Ogg and TTF, and a
// reference image that round-trips through UTF-8 would break compareImg in a way
// that looks like a rendering bug.
function collect(dir) {
  const out = {};
  const walk = (d) => {
    for (const name of readdirSync(d)) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) walk(p);
      else out[relative(dir, p).split(sep).join('/')] = readFileSync(p).toString('base64');
    }
  };
  walk(dir);
  return out;
}
const project = collect(join(root, 'testing'));

async function corpusPageFn({ b64, boot, project, shimSrc, winHostSrc, fsHostSrc, inputHostSrc, systemHostSrc, audioHostSrc, gamepadHostSrc }) {
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + winHostSrc)())();
  const fs = (new Function('return ' + fsHostSrc)())();
  const system = (new Function('return ' + systemHostSrc)())();
  const audio = (new Function('return ' + audioHostSrc)())();
  const gamepad = (new Function('return ' + gamepadHostSrc)())();
  // The real input host, with its event queue silenced. It exists to satisfy the
  // love_input import surface — love.mouse/love.keyboard read the snapshot the
  // pump maintains, and the corpus drives those state APIs directly rather than
  // through events. Its BAKED SCRIPT must not play: that script is the 6.4/6.5
  // witness fixture and it ends with a QUIT record, which love.run obeys — the
  // corpus quit on its first frame until this was silenced. input_poll always
  // reporting "queue empty" is the honest shape for a run with no user at all.
  const rawInput = (new Function('return ' + inputHostSrc)())();
  const input = { ...rawInput, imports: { ...rawInput.imports, input_poll: () => 0 } };
  const lines = [];
  const log = (s) => lines.push(s);
  const te = new TextEncoder();
  const td = new TextDecoder();

  if (!host.haveContext || !host.haveContext()) return { ok: false, lines, error: 'no WebGL2 context' };

  try {
    // Replace the canned project with the corpus. Same store, same imports —
    // the engine cannot tell this from a game on disk.
    for (const k of Object.keys(fs.files)) delete fs.files[k];
    for (const [name, b] of Object.entries(project))
      fs.files[name] = Uint8Array.from(atob(b), (c) => c.charCodeAt(0));
    log('project: ' + Object.keys(fs.files).length + ' file(s)');

    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: host.glImports,
      love_win: host.winImports,
      love_fs: fs.imports,
      love_input: input.imports,
      love_system: system.imports,
      love_audio: audio.imports,
      love_gamepad: gamepad.imports,
    });
    const x = instance.exports;
    shim.bind(x.memory);
    host.bind(x.memory, x.malloc);
    fs.bind(x.memory);
    input.bind(x.memory);
    system.bind(x.memory);
    audio.bind(x.memory);
    gamepad.bind(x.memory);
    x._initialize();

    const put = (s) => { const b = te.encode(s); const p = x.pump_in(b.length); new Uint8Array(x.memory.buffer).set(b, p); return b.length; };
    const out = () => { const p = x.pump_out(); return td.decode(new Uint8Array(x.memory.buffer).slice(p, p + x.pump_out_len())); };
    const tick = () => new Promise((r) => requestAnimationFrame(r));

    let st = x.pump_boot(put(boot));
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'boot error: ' + out() };

    // Pump until the suite quits. The cap is a runaway guard, not a schedule:
    // reaching it means the suite never finished, which is a failure in itself
    // and must not be mistaken for a clean run with missing results.
    const MAX_FRAMES = 60000;
    let frames = 0;
    while (st >= 0 && frames < MAX_FRAMES) { await tick(); st = x.pump_frame(put('t')); frames++; }
    log('frames: ' + frames + ', final pump status: ' + st + (st < 0 ? (' out: ' + JSON.stringify(out())) : ''));
    if (st === -2) return { ok: false, lines, stdout: shim.stdout, error: 'runtime error after ' + frames + ' frames: ' + out() };
    if (frames >= MAX_FRAMES) return { ok: false, lines, stdout: shim.stdout, error: 'the suite never finished within ' + MAX_FRAMES + ' frames' };

    // The report, read out of the save namespace the engine wrote it to.
    const key = Object.keys(fs.saves).find((k) => /lovetest_all\.xml$/.test(k));
    if (!key) return { ok: false, lines, stdout: shim.stdout, error: 'no JUnit report in the save namespace; keys: ' + Object.keys(fs.saves).join(', ') };
    log('report: ' + key);
    return { ok: true, lines, stdout: shim.stdout, xml: td.decode(fs.saves[key]) };
  } catch (e) {
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, stdout: shim.stdout, error };
  }
}

// ── the expected-fail list ────────────────────────────────────────────────────
// One record per line: `<suite>/<test>  <class>  <reason>`. Blank lines and #
// comments are ignored. The class is what wasi/COMPATIBILITY.md marks the row:
//   divergence — the browser does not have the feature (a blank cell)
//   gesture    — real, but needs a user gesture no test can supply (~)
//   defect     — the browser has it and we do not (✗); the reason names the issue
// The three are not treated differently by the comparison; they exist so the
// list stays readable as a document, and so a defect is never quietly filed as
// a divergence.
function readExpected(path) {
  const map = new Map();
  let text = '';
  try { text = readFileSync(path, 'utf8'); } catch { return map; }
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const m = line.match(/^(\S+)\s+(divergence|gesture|defect)\s+(.*)$/);
    if (!m) { console.log('!! unparseable expected.txt line: ' + line); continue; }
    map.set(m[1], { cls: m[2], reason: m[3] });
  }
  return map;
}

// JUnit, as TestSuite.lua/TestMethod.lua emit it: <testsuite name="love.audio">
// wrapping <testcase name="method"> whose failure/skip is a child element.
function parseJUnit(xml) {
  const results = [];
  const suiteRe = /<testsuite name="([^"]+)"[^>]*>([\s\S]*?)<\/testsuite>/g;
  for (let s; (s = suiteRe.exec(xml)); ) {
    const suite = s[1].replace(/^love\./, '');
    const caseRe = /<testcase [^>]*name="([^"]+)"[^>]*>([\s\S]*?)<\/testcase>/g;
    for (let c; (c = caseRe.exec(s[2])); ) {
      const body = c[2];
      const failed = /<failure /.test(body);
      const skipped = /<skipped /.test(body);
      const msg = (body.match(/<failure message="([^"]*)"/) || [])[1] || '';
      results.push({ id: suite + '/' + c[1], failed, skipped, msg });
    }
  }
  return results;
}

const result = await runInChromium(corpusPageFn, {
  b64, boot, project,
  shimSrc: makeWasiShim.toString(),
  winHostSrc: makeWebGLWinHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  inputHostSrc: makeInputHost.toString(),
  systemHostSrc: makeSystemHost.toString(),
  audioHostSrc: makeAudioHost.toString(),
  gamepadHostSrc: makeGamepadHost.toString(),
});

console.log('--- browser transcript ---');
for (const line of result.lines || []) console.log(line);
if (result.error) {
  if (result.stdout) console.log('--- wasm stdout (tail) ---\n' + result.stdout.slice(-20000).trimEnd());
  console.log('--- error: ' + result.error + ' ---');
  console.log('CORPUS-WITNESS: FAIL');
  process.exit(1);
}

const results = parseJUnit(result.xml);
const expected = readExpected(expectedPath);
const pass = results.filter((r) => !r.failed && !r.skipped);
const fail = results.filter((r) => r.failed);
const skip = results.filter((r) => r.skipped);
console.log(`\ncorpus: ${pass.length} pass / ${fail.length} fail / ${skip.length} skip  (${results.length} tests)`);

if (BOOTSTRAP) {
  console.log('\n--- CORPUS_BOOTSTRAP: the failures, as expected.txt lines ---');
  for (const r of fail) console.log(`${r.id}\tdivergence\tTODO — ${r.msg.slice(0, 90)}`);
  console.log('CORPUS-WITNESS: BOOTSTRAP (no verdict)');
  process.exit(0);
}

// The three ways this fails.
const regressed = fail.filter((r) => !expected.has(r.id));
const stale = [...expected.keys()].filter((id) => pass.some((r) => r.id === id));
// A listed test that no longer exists is also a stale list — the name changed
// or the test was removed upstream, and a silently-ignored entry would let a
// real failure hide behind a line nobody notices is dead.
const seen = new Set(results.map((r) => r.id));
const orphan = [...expected.keys()].filter((id) => !seen.has(id));

if (regressed.length) {
  console.log(`\n!! ${regressed.length} FAILING and not classified — decide, then add to expected.txt:`);
  for (const r of regressed) console.log(`   ${r.id}  ${r.msg.slice(0, 110)}`);
}
if (stale.length) {
  console.log(`\n!! ${stale.length} on the expected-fail list but PASSING — the list is stale, remove them:`);
  for (const id of stale) console.log(`   ${id}  (was: ${expected.get(id).cls} — ${expected.get(id).reason})`);
}
if (orphan.length) {
  console.log(`\n!! ${orphan.length} on the expected-fail list but not in the corpus at all — renamed or removed:`);
  for (const id of orphan) console.log(`   ${id}`);
}

const byClass = {};
for (const r of fail) if (expected.has(r.id)) { const c = expected.get(r.id).cls; byClass[c] = (byClass[c] || 0) + 1; }
console.log(`\nexpected failures, by class: ` + (Object.entries(byClass).map(([k, v]) => `${k} ${v}`).join(', ') || 'none'));

const ok = !regressed.length && !stale.length && !orphan.length;
console.log('CORPUS-WITNESS: ' + (ok ? 'PASS' : 'FAIL'));
process.exit(ok ? 0 : 1);
