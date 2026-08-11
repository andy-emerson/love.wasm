// Hotswap leg of the live-edit witness (#56, D4=B). Same shape as
// run-durability.mjs — the real shell page in real Chromium — because the claim
// is about a running session: main.lua is edited ON DISK while the game plays,
// and the D4 contract is measured from the game's own transcript.
//
// Four legs, in the order the D4 record states them:
//
//   1. An edit to love.update takes effect at its NEXT calls: after v2 lands on
//      disk, HOT-STATE lines must switch to v=2 (the new draw body) with x now
//      DECREASING (the new update body).
//   2. File-scope state SURVIVES the swap, still shared: the first v=2 counter
//      continues past the last v=1 counter (no reset), x continues from where
//      v1 left it (not the fresh initial 8), and draw keeps seeing what update
//      mutates (x falls across successive v=2 lines — update writes, draw reads,
//      one cell).
//   3. A syntax-broken save fails on the USER's code with the engine intact:
//      the shell must report a Lua error naming main.lua and its line, the game
//      must keep RUNNING the old body (v=2 lines continue), and after a good v3
//      is saved the SAME session must run it (v=3 lines, counter still
//      continuous).
//   4. love.load runs once per SESSION: "HOT-LOAD once" appears exactly once in
//      the whole transcript.
//
// Chromium-only, like every shell witness: it needs a real WebGL2 context.
//
//   node run-hotswap.mjs <wasm> <fixture-dir>
import { spawn } from 'node:child_process';
import { cpSync, writeFileSync, mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolvePlaywright } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const wasm = process.argv[2] || join(here, 'love-game.wasm');
const fixture = process.argv[3] || join(here, 'fixture-hotswap');
const PORT = Number(process.env.SHELL_PORT || 8190);

const { chromium } = resolvePlaywright();

// A scratch copy: the witness rewrites main.lua repeatedly.
const work = mkdtempSync(join(tmpdir(), 'hotswap-witness-'));
cpSync(fixture, work, { recursive: true });

const log = (s) => console.log(s);
let browser, server, failed = null;
const fail = (m) => { if (!failed) failed = m; };
const leg = (name, cond, detail) => {
  log(`HOTSWAP-${name}: ${cond ? 'PASS' : 'FAIL'}${cond ? '' : ' — ' + detail}`);
  if (!cond) fail(`${name}: ${detail}`);
};

// The game body per version: only the movement direction and the version stamp
// change, so the diff is exactly "an edit to love.update/love.draw".
const game = (v, move) => `local counter = 0
local x = 8

function love.load()
  print("HOT-LOAD once")
end

function love.update(dt)
  counter = counter + 1
  x = x ${move} 120 * dt
  if x > 88 then x = 88 end
  if x < 0 then x = 0 end
end

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.rectangle("fill", x, 24, 8, 8)
  if counter % 20 == 0 then
    print(("HOT-STATE v=${v} counter=%d x=%.1f"):format(counter, x))
  end
end
`;

// The broken save: a syntax error, exactly as a user mid-edit would leave it.
const BROKEN = 'function love.update(dt)\n  counter = counter +\n';

try {
  server = spawn(join(here, 'serve.sh'), [String(PORT), work], { cwd: root, stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 900));

  const exe = process.env.CHROMIUM && existsSync(process.env.CHROMIUM) ? process.env.CHROMIUM : null;
  browser = await chromium.launch(exe ? { executablePath: exe } : {});
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(e.message));

  const url = `http://localhost:${PORT}/wasi/shell/`
    + `?project=/__project/&wasm=${encodeURIComponent('/wasi/shell/' + wasm.split('/').pop())}`;
  await page.goto(url, { waitUntil: 'load' });

  const shellLog = () => page.textContent('#log').catch(() => '');
  const status = () => page.textContent('#status').catch(() => '');
  const waitFor = async (pred, what, tries = 160) => {
    for (let i = 0; i < tries; i++) {
      const txt = await shellLog();
      const r = pred(txt);
      if (r) return r;
      await page.waitForTimeout(250);
    }
    fail(`never saw ${what}`);
    log(`--- shell log ---\n` + (await shellLog()).trimEnd());
    return null;
  };
  // All HOT-STATE lines of one version, parsed. The transcript only grows, so
  // re-reading it is idempotent.
  const states = (txt, v) =>
    [...txt.matchAll(new RegExp(`HOT-STATE v=${v} counter=(\\d+) x=([\\d.]+)`, 'g'))]
      .map((m) => ({ counter: Number(m[1]), x: Number(m[2]) }));

  // Boot: the load marker, then enough v1 play that x sits at its clamp (88)
  // and counter is well away from anything a reset could reproduce quickly.
  if (!(await waitFor((t) => /HOT-LOAD once/.test(t), 'the love.load marker'))) throw new Error('no boot');
  if (!(await waitFor((t) => states(t, 1).some((s) => s.counter >= 120), 'v1 play (counter >= 120)')))
    throw new Error('v1 never played');
  const v1 = states(await shellLog(), 1);
  const lastV1 = v1[v1.length - 1];
  log(`v1 played: last HOT-STATE v=1 counter=${lastV1.counter} x=${lastV1.x}`);

  // ── the edit: v2 reverses love.update's movement ──────────────────────────
  log('editing main.lua on disk: v2 (update now moves LEFT)');
  writeFileSync(join(work, 'main.lua'), game(2, '-'));

  const swapped = await waitFor((t) => /main\.lua hotswapped — \d+ binding\(s\) applied/.test(t), 'the hotswap report');
  if (swapped) log('the shell reported the hotswap');
  const v2ready = await waitFor((t) => states(t, 2).length >= 3, 'three v=2 HOT-STATE lines');
  const txt2 = await shellLog();
  const v2 = states(txt2, 2);
  const maxV1 = Math.max(...states(txt2, 1).map((s) => s.counter));

  // Leg 1 — the NEXT calls run the new bodies (draw stamps v=2, update moves left).
  leg('LEG1 (next frames run the new body)', !!v2ready && v2.length >= 3,
    'no v=2 HOT-STATE lines — the edit never took effect');

  // Leg 2 — state survived, still shared. counter continued (a reset would
  // restart at 20); x continued from the v1 clamp at 88 (a reset would restart
  // near the initial 8); and x FALLS across v2 lines — the new update mutates
  // the very cell the new draw reads.
  if (v2.length >= 3) {
    leg('LEG2 (file-scope state survived, still shared)',
      v2[0].counter > maxV1 && v2[0].x > 40 && v2[1].x < v2[0].x && v2[2].x < v2[1].x,
      `first v2 counter=${v2[0].counter} (last v1 ${maxV1}), v2 x: ${v2[0].x}, ${v2[1].x}, ${v2[2].x}`);
  } else {
    leg('LEG2 (file-scope state survived, still shared)', false, 'no v2 lines to judge');
  }

  // ── the broken save ───────────────────────────────────────────────────────
  log('saving a syntax-broken main.lua');
  const v2linesBefore = states(await shellLog(), 2).length;
  writeFileSync(join(work, 'main.lua'), BROKEN);

  const errLine = await waitFor((t) => {
    const m = /main\.lua:(\d+):[^\n]*/.exec(t);
    return m ? m[0] : null;
  }, "the edit's own Lua error naming main.lua:<line>");
  if (errLine) log(`the shell surfaced the user's error: ${errLine.split('\n')[0]}`);
  // The engine survived: still running, old body still producing v2 lines.
  const ranOn = await waitFor((t) => states(t, 2).length > v2linesBefore, 'v2 lines continuing past the broken save');
  const stillRunning = /running/.test(await status());

  // ── the recovery: a good v3 into the SAME session ─────────────────────────
  log('restoring a good main.lua: v3 (update moves RIGHT again)');
  writeFileSync(join(work, 'main.lua'), game(3, '+'));
  const v3ready = await waitFor((t) => states(t, 3).length >= 2, 'v=3 HOT-STATE lines');
  const txt3 = await shellLog();
  const v3 = states(txt3, 3);
  const maxV2 = Math.max(...states(txt3, 2).map((s) => s.counter));

  // Leg 3 — the broken save failed on the user's code, engine intact.
  leg('LEG3 (broken edit fails on the user\'s code, engine intact)',
    !!errLine && !!ranOn && stillRunning && !!v3ready && v3[0].counter > maxV2,
    `error=${!!errLine} ranOn=${!!ranOn} running=${stillRunning} v3=${v3.length} `
    + `firstV3counter=${v3[0] && v3[0].counter} (last v2 ${maxV2})`);

  // Leg 4 — love.load ran once for the whole session, across three swaps and
  // one broken save.
  const loads = ((await shellLog()).match(/HOT-LOAD once/g) || []).length;
  leg('LEG4 (love.load did not re-run)', loads === 1, `the load marker printed ${loads} time(s)`);

  if (pageErrors.length) { log('--- page errors ---\n' + pageErrors.join('\n')); fail('the page raised an error'); }
} catch (e) {
  fail(e && e.message ? e.message : String(e));
} finally {
  try { await browser?.close(); } catch {}
  try { server?.kill(); } catch {}
  try { rmSync(work, { recursive: true, force: true }); } catch {}
}

if (failed) console.log('--- failure: ' + failed + ' ---');
console.log('HOTSWAP-WITNESS: ' + (failed ? 'FAIL' : 'PASS'));
process.exit(failed ? 1 : 0);
