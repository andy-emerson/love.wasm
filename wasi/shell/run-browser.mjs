// Browser leg of the interactive-shell witness (Beta step 1). Drives the REAL
// shell page in real Chromium — the same page a person opens — and asserts the
// three things the shell exists to do, none of which any earlier witness covers:
//
//   1. It runs a REAL PROJECT from disk. The fixture's own conf.lua sizes the
//      canvas 96x64, where fs-host.mjs's canned project is 64x64, so the size is
//      what proves whose conf.lua ran; and love.filesystem reads an asset out of
//      a SUBDIRECTORY of the project.
//   2. LIVE INPUT reaches the game. Playwright dispatches real DOM key events at
//      the focused canvas — not a queued script — and the rectangle moves,
//      recovered as a pixel that was background before the key went down. This is
//      the live love_input path; the 6.4 witness proves the seam with a baked
//      queue, and cannot prove the DOM half.
//   3. LIVE EDIT reaches the running game. colour.lua is rewritten on disk and
//      the SAME running instance draws the new colour, with no page reload; then
//      main.lua is touched and the shell reports it as restart-only, which is
//      what keeps the #47 (D4) deferral honest rather than a silent no-op.
//
// Chromium-only: it needs a real WebGL2 context, like every graphics witness.
// The project is copied to a temp directory first, because the live-edit half
// rewrites files and a witness must not dirty the working tree.
//
//   node run-browser.mjs <wasm> <fixture-dir>
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { cpSync, writeFileSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const wasm = process.argv[2] || join(here, 'love-game.wasm');
const fixture = process.argv[3] || join(here, 'fixture');
const PORT = Number(process.env.SHELL_PORT || 8188);

let chromium;
for (const base of [process.cwd(), '/root/.love.wasm/npm', process.env.HOME || '/root']) {
  try { chromium = createRequire(base + '/x.js')('playwright-core').chromium; break; } catch {}
}
if (!chromium) { console.error('playwright-core is not resolvable'); process.exit(1); }

// A scratch copy: the live-edit assertions rewrite project files.
const work = mkdtempSync(join(tmpdir(), 'shell-witness-'));
cpSync(fixture, work, { recursive: true });

const lines = [];
const log = (s) => { lines.push(s); console.log(s); };
let browser, server, failed = null;
const fail = (m) => { if (!failed) failed = m; };

try {
  server = spawn(join(here, 'serve.sh'), [String(PORT), work], { cwd: root, stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 900));

  browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium',
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(e.message));

  const url = `http://localhost:${PORT}/wasi/shell/`
    + `?project=/__project/&wasm=${encodeURIComponent('/wasi/shell/' + wasm.split('/').pop())}`;
  await page.goto(url, { waitUntil: 'load' });

  // The shell reports its own state; wait for it rather than guessing a delay.
  let status = '';
  for (let i = 0; i < 400; i++) {
    status = await page.textContent('#status').catch(() => '');
    if (/running|error|failed|quit/.test(status)) break;
    await page.waitForTimeout(250);
  }
  log('status: ' + status);
  if (!/running/.test(status)) {
    log('--- shell log ---\n' + (await page.textContent('#log').catch(() => '')));
    throw new Error('the shell never reached "running"');
  }

  const canvas = await page.evaluate(() => {
    const c = document.querySelector('#stage canvas');
    return c ? { w: c.width, h: c.height, inDoc: document.contains(c) } : null;
  });
  log('canvas: ' + JSON.stringify(canvas));
  if (!canvas) throw new Error('no canvas in the document');
  if (!canvas.inDoc) fail('the canvas is not in the document — a player could not see it');
  // 96x64 is the FIXTURE's conf.lua; the canned project would be 64x64.
  if (!(canvas.w === 96 && canvas.h === 64))
    fail(`canvas is ${canvas.w}x${canvas.h}, expected 96x64 from the project's conf.lua`);

  // Scan a row and report the drawn rectangle's left edge and colour. Scanning
  // rather than sampling fixed points: the rectangle's position is exactly what
  // the input assertions are about, so finding it is the measurement, and a fixed
  // point silently passes or fails depending on how far the thing moved.
  const findRect = (y = 32) => page.evaluate((y) => {
    const c = document.querySelector('#stage canvas');
    const gl = c.getContext('webgl2');
    const row = new Uint8Array(c.width * 4);
    gl.readPixels(0, y, c.width, 1, gl.RGBA, gl.UNSIGNED_BYTE, row);
    for (let x = 0; x < c.width; x++) {
      const r = row[x * 4], g = row[x * 4 + 1], b = row[x * 4 + 2];
      if (r > 60 || g > 60 || b > 60) return { x, px: [r, g, b] };
    }
    return { x: -1, px: null };
  }, y);

  await page.waitForTimeout(600);
  const shellLog = () => page.textContent('#log');

  // (1) the project is what is running
  if (!/SHELL-LOAD hello from an asset/.test(await shellLog()))
    fail('the project could not read assets/note.txt through love.filesystem');

  const rest = await findRect();
  log('at rest: ' + JSON.stringify(rest));
  if (rest.x < 0) fail('the rectangle is not drawn at rest');
  if (!(rest.px && rest.px[1] > 200)) fail(`the rectangle is not green at rest (${rest.px})`);

  // (2) LIVE INPUT: real DOM key events at the focused canvas, not a queued
  //     script. Held briefly, because the game clamps at x=80 and a long hold
  //     would prove only that it reached the clamp.
  await page.focus('#stage canvas');
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(300);
  await page.keyboard.up('ArrowRight');
  await page.waitForTimeout(200);
  const moved = await findRect();
  log('after holding ArrowRight: ' + JSON.stringify(moved));
  if (moved.x <= rest.x)
    fail(`the rectangle did not move right under a real DOM key event (${rest.x} -> ${moved.x})`);

  // It must also STOP. If keyup never reached love.keyboard the game keeps
  // moving, which a single after-the-fact sample would not notice.
  await page.waitForTimeout(600);
  const stopped = await findRect();
  log('after keyup + 600ms: ' + JSON.stringify(stopped));
  if (stopped.x !== moved.x)
    fail(`the rectangle kept moving after keyup (${moved.x} -> ${stopped.x}) — the release did not reach love.keyboard`);

  // And it must move back, so the assertion is about the key and not about drift.
  await page.keyboard.down('ArrowLeft');
  await page.waitForTimeout(300);
  await page.keyboard.up('ArrowLeft');
  await page.waitForTimeout(200);
  const back = await findRect();
  log('after holding ArrowLeft: ' + JSON.stringify(back));
  if (back.x >= stopped.x)
    fail(`the rectangle did not move left under ArrowLeft (${stopped.x} -> ${back.x})`);

  // (3) LIVE EDIT: rewrite a module on disk; the running instance must change.
  log('editing colour.lua on disk: green -> blue');
  writeFileSync(join(work, 'colour.lua'), 'return { 0, 0, 1 }\n');
  let blue = null;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(250);
    blue = await findRect();
    if (blue.px && blue.px[2] > 200 && blue.px[1] < 80) break;
  }
  log('after the edit: ' + JSON.stringify(blue));
  if (!(blue.px && blue.px[2] > 200 && blue.px[1] < 80))
    fail(`the running game did not pick up the module edit (reads ${JSON.stringify(blue)})`);
  const editLog = await shellLog();
  if (!/live-edit: colour\.lua/.test(editLog)) fail('the shell did not report the live edit');
  if (!/module\(s\) invalidated/.test(editLog)) fail('pump_invalidate() was not reported');
  if (!/running/.test(await page.textContent('#status')))
    fail('the game stopped running across the live edit');

  // main.lua is restart-only (#47/D4) and must be REPORTED, not silently ignored.
  log('touching main.lua (restart-only per #47)');
  writeFileSync(join(work, 'main.lua'), readFileSync(join(work, 'main.lua'), 'utf8') + '\n-- touched\n');
  let sawRestart = false;
  for (let i = 0; i < 40; i++) {
    await page.waitForTimeout(250);
    if (/main\.lua changed — reload the page/.test(await shellLog())) { sawRestart = true; break; }
  }
  if (!sawRestart) fail('a main.lua edit was silently ignored instead of reported as restart-only');
  log('main.lua reported restart-only: ' + sawRestart);

  if (pageErrors.length) { log('--- page errors ---\n' + pageErrors.join('\n')); fail('the page raised an error'); }
  log('--- shell log ---\n' + (await shellLog()).trimEnd());
} catch (e) {
  fail(e && e.message ? e.message : String(e));
} finally {
  try { await browser?.close(); } catch {}
  try { server?.kill(); } catch {}
  try { rmSync(work, { recursive: true, force: true }); } catch {}
}

if (failed) console.log('--- failure: ' + failed + ' ---');
console.log('SHELL-WITNESS: ' + (failed ? 'FAIL' : 'PASS'));
process.exit(failed ? 1 : 0);
