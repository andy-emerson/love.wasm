// Durability leg of the save-store witness (#55). Proves the one thing no
// in-page witness can: a file written through love.filesystem SURVIVES A PAGE
// RELOAD. Same shape as run-browser.mjs — the real shell page, real Chromium —
// because durability is a property of the page lifecycle, and only crossing a
// real page.reload() measures it.
//
// Two legs, and the second is the demonstration this witness can fail:
//
//   1. OPFS on (the default): the game writes a per-run payload, the page
//      reloads, and the SAME payload must come back through love.filesystem —
//      hydrated from OPFS before boot, since love.boot reads on frame one.
//   2. ?opfs=0 (the in-memory reference store): the identical sequence must
//      come back EMPTY after the reload. If it did not, leg 1's pass would be
//      caching or luck, not the OPFS store.
//
// Each leg gets its own Chromium launch: a fresh profile means empty OPFS, so
// leg 1 can require "DUR-READ nil" on its first load and nothing leaks between
// legs. The payload is unique per leg anyway, so a stale store cannot fake a
// round-trip.
//
// Chromium-only, like every shell witness: it needs a real WebGL2 context.
//
//   node run-durability.mjs <wasm> <fixture-dir>
import { spawn } from 'node:child_process';
import { cpSync, writeFileSync, mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolvePlaywright } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const wasm = process.argv[2] || join(here, 'love-game.wasm');
const fixture = process.argv[3] || join(here, 'fixture-durability');
const PORT = Number(process.env.SHELL_PORT || 8189);

const { chromium } = resolvePlaywright();

// A scratch copy: the witness rewrites payload.txt per leg.
const work = mkdtempSync(join(tmpdir(), 'durability-witness-'));
cpSync(fixture, work, { recursive: true });

const log = (s) => console.log(s);
let server, failed = null;
const fail = (m) => { if (!failed) failed = m; };

const url = `http://localhost:${PORT}/wasi/shell/`
  + `?project=/__project/&wasm=${encodeURIComponent('/wasi/shell/' + wasm.split('/').pop())}`;

// Drive one write → reload → read pass and return what the reloaded page read.
// expectStore is asserted against the shell's own report of which save store it
// is running, so a leg cannot silently test the wrong one.
async function leg(name, extraQuery, expectStore, payload) {
  writeFileSync(join(work, 'payload.txt'), payload);
  const browser = await chromium.launch(
    process.env.CHROMIUM && existsSync(process.env.CHROMIUM)
      ? { executablePath: process.env.CHROMIUM } : {});
  try {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', (e) => pageErrors.push(e.message));

    const shellLog = () => page.textContent('#log').catch(() => '');
    const waitFor = async (re, what) => {
      for (let i = 0; i < 120; i++) {
        const m = re.exec(await shellLog());
        if (m) return m;
        await page.waitForTimeout(250);
      }
      fail(`${name}: never saw ${what}`);
      log(`--- ${name} shell log ---\n` + (await shellLog()).trimEnd());
      return null;
    };

    await page.goto(url + extraQuery, { waitUntil: 'load' });
    if (!(await waitFor(expectStore, 'the expected save-store report'))) return null;
    const first = await waitFor(/DUR-READ (\S+)/, 'the first DUR-READ');
    if (!first) return null;
    // The first load must find nothing: the profile is fresh, so a non-nil read
    // here means the legs are contaminating each other.
    if (first[1] !== 'nil') fail(`${name}: first load read ${first[1]}, expected nil`);
    if (!(await waitFor(new RegExp('DUR-WROTE ' + payload), 'the write marker'))) return null;

    // The flush is eager but async; give it a beat before tearing the page down.
    await page.waitForTimeout(1000);
    log(`${name}: wrote ${payload}, reloading the page…`);
    await page.reload({ waitUntil: 'load' });

    const back = await waitFor(/DUR-READ (\S+)/, 'the post-reload DUR-READ');
    if (pageErrors.length) fail(`${name}: the page raised an error — ${pageErrors.join('; ')}`);
    return back && back[1];
  } finally {
    await browser.close().catch(() => {});
  }
}

try {
  server = spawn(join(here, 'serve.sh'), [String(PORT), work], { cwd: root, stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 900));

  // Leg 1 — OPFS on: the payload must survive the reload.
  const p1 = `DUR-${Date.now()}-opfs`;
  const r1 = await leg('opfs-on', '', /saves: OPFS "durability-witness"/, p1);
  log(`opfs-on: after reload love.filesystem.read("dur.txt") = ${r1}`);
  if (r1 !== p1) fail(`opfs-on: expected the payload ${p1} back after reload, got ${r1}`);

  // Leg 2 — OPFS disabled: the identical sequence must come back empty. This is
  // the witness demonstrating it can fail — remove the durable store and the
  // round-trip must break, or leg 1 was never measuring the store.
  const p2 = `DUR-${Date.now()}-mem`;
  const r2 = await leg('opfs-off', '&opfs=0', /saves: in-memory \(OPFS disabled/, p2);
  log(`opfs-off: after reload love.filesystem.read("dur.txt") = ${r2}`);
  if (r2 !== 'nil') fail(`opfs-off: expected nil after reload on the in-memory store, got ${r2}`);
} catch (e) {
  fail(e && e.message ? e.message : String(e));
} finally {
  try { server?.kill(); } catch {}
  try { rmSync(work, { recursive: true, force: true }); } catch {}
}

if (failed) console.log('--- failure: ' + failed + ' ---');
console.log('DURABILITY-WITNESS: ' + (failed ? 'FAIL' : 'PASS'));
process.exit(failed ? 1 : 0);
