// Beta step 2 driver: run a real third-party LÖVE game through the real shell
// page and assert it plays. See run.sh for why this is not in CI.
//
// The bar is "boots, playable, no crash, visually plausible" — deliberately not
// pixel parity, which is step 3's job against the testing/ corpus. So the
// assertions are about the game reaching states, not about exact colours:
//
//   1. The shell reaches "running" and the canvas is the size the GAME's own
//      conf.lua asked for (1920x1080), not the shell's default.
//   2. The title screen has drawn TEXT — many distinct colours over a dark
//      background, which a blank or single-cleared frame cannot produce.
//   3. It is not showing LÖVE's error screen. That screen is a specific blue
//      and it renders text too, so "something is drawn" alone would pass on a
//      crashed game. This is the assertion that makes the others mean anything.
//   4. Pressing the key the game's own title screen says starts it, and the
//      frame changes wholesale — a world, not a menu.
//   5. Held input moves something.
//   6. GL reports no error, and the page raised no exception.
//
//   node run-browser-game.mjs <wasm> <game-dir>
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolvePlaywright } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const wasm = process.argv[2];
const game = process.argv[3];
const PORT = Number(process.env.GAME_PORT || 8191);

const { chromium } = resolvePlaywright();

const lines = [];
const log = (s) => { lines.push(s); console.log(s); };
let browser, server, failed = null;
const fail = (m) => { if (!failed) failed = m; };

// LÖVE's error screen: (89,157,220). If the game crashed, boot.lua's handler
// clears to this and prints the traceback, so a naive "is anything drawn" check
// would pass. Recognising it by colour is what separates ran from crashed.
const ERROR_BLUE = [89, 157, 220];
const near = (px, c) => Math.abs(px[0] - c[0]) < 8 && Math.abs(px[1] - c[1]) < 8 && Math.abs(px[2] - c[2]) < 8;

try {
  server = spawn(join(root, 'wasi/shell/serve.sh'), [String(PORT), game], { cwd: root, stdio: 'ignore' });
  await new Promise((r) => setTimeout(r, 900));

  const exe = process.env.CHROMIUM && existsSync(process.env.CHROMIUM) ? process.env.CHROMIUM : null;
  browser = await chromium.launch(exe ? { executablePath: exe } : {});
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(e.message));

  const url = `http://localhost:${PORT}/wasi/shell/?project=/__project/`
    + `&wasm=${encodeURIComponent('/wasi/shell/' + wasm.split('/').pop())}`;
  await page.goto(url, { waitUntil: 'load' });

  let status = '';
  for (let i = 0; i < 480; i++) {
    status = await page.textContent('#status').catch(() => '');
    if (/running|error|failed|quit/.test(status)) break;
    await page.waitForTimeout(250);
  }
  log('status: ' + status);
  if (!/running/.test(status)) {
    log('--- shell log ---\n' + (await page.textContent('#log').catch(() => '')));
    throw new Error('the shell never reached "running"');
  }

  // (1) the GAME's conf.lua sized the canvas
  const canvas = await page.evaluate(() => {
    const c = document.querySelector('#stage canvas');
    return c ? { w: c.width, h: c.height } : null;
  });
  log('canvas: ' + JSON.stringify(canvas));
  if (!canvas) throw new Error('no canvas in the document');
  if (!(canvas.w === 1920 && canvas.h === 1080))
    fail(`canvas is ${canvas.w}x${canvas.h}, expected 1920x1080 from the game's own conf.lua`);

  // A histogram of the whole frame: distinct colours, how much is lit, and the
  // most common colour — enough to tell a title screen from a world from a
  // crash, without pinning any exact pixel.
  const frame = () => page.evaluate(() => {
    const c = document.querySelector('#stage canvas');
    const gl = c.getContext('webgl2');
    const px = new Uint8Array(c.width * c.height * 4);
    gl.readPixels(0, 0, c.width, c.height, gl.RGBA, gl.UNSIGNED_BYTE, px);
    const seen = new Map();
    let lit = 0;
    for (let i = 0; i < px.length; i += 4) {
      const k = `${px[i]},${px[i + 1]},${px[i + 2]}`;
      seen.set(k, (seen.get(k) || 0) + 1);
      if (px[i] > 40 || px[i + 1] > 40 || px[i + 2] > 40) lit++;
    }
    const top = [...seen.entries()].sort((a, b) => b[1] - a[1])[0];
    return {
      distinct: seen.size,
      litPct: +(100 * lit / (px.length / 4)).toFixed(1),
      dominant: top[0].split(',').map(Number),
      dominantPct: +(100 * top[1] / (px.length / 4)).toFixed(1),
    };
  });

  await page.waitForTimeout(2500);
  const title = await frame();
  log('title screen: ' + JSON.stringify(title));

  // (3) FIRST: not the error screen. Everything below is meaningless otherwise.
  if (near(title.dominant, ERROR_BLUE))
    fail(`the game crashed — the canvas is LÖVE's error screen (${title.dominant}); see the shell log`);
  // (2) text is drawn: a cleared frame has one colour, antialiased glyphs have many.
  if (title.distinct < 20)
    fail(`the title screen has ${title.distinct} distinct colours, expected text — nothing is being drawn`);

  // (4) start it. The game's own title screen says "Press the Spacebar to start".
  await page.focus('#stage canvas');
  await page.keyboard.press('Space');
  await page.waitForTimeout(2500);
  const world = await frame();
  log('after Space: ' + JSON.stringify(world));

  if (near(world.dominant, ERROR_BLUE))
    fail(`the game crashed on starting — the canvas is LÖVE's error screen (${world.dominant})`);
  if (world.dominant.join() === title.dominant.join())
    fail('the frame did not change on Space — the game did not leave its title screen');
  // A world fills the screen; the title screen is text on near-black.
  if (!(world.litPct > 50))
    fail(`only ${world.litPct}% of the frame is lit after starting, expected a drawn world`);

  // (5) it responds to held input.
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(1200);
  await page.keyboard.up('ArrowRight');
  await page.waitForTimeout(400);
  const moved = await frame();
  log('after holding ArrowRight: ' + JSON.stringify(moved));
  if (near(moved.dominant, ERROR_BLUE))
    fail(`the game crashed on input — the canvas is LÖVE's error screen (${moved.dominant})`);
  if (moved.dominantPct === world.dominantPct && moved.distinct === world.distinct)
    fail('the frame statistics (dominant-colour share and distinct-colour count) are unchanged after holding a movement key — nothing responded');

  // (6) the engine is not limping along with a broken GL state.
  const glError = await page.evaluate(() => {
    const c = document.querySelector('#stage canvas');
    return c.getContext('webgl2').getError();
  });
  log('gl error: ' + glError);
  if (glError !== 0) fail(`GL reports error 0x${glError.toString(16)} after play`);

  const shellLog = await page.textContent('#log').catch(() => '');
  const notices = shellLog.match(/\[love\.wasm preview\][^\n]*/g) || [];
  log('preview notices: ' + (notices.length ? '\n  ' + notices.join('\n  ') : 'none'));

  if (pageErrors.length) { log('--- page errors ---\n' + pageErrors.join('\n')); fail('the page raised an error'); }
  if (/Error:/.test(shellLog)) { log('--- shell log ---\n' + shellLog); fail('the game reported a Lua error'); }
} catch (e) {
  fail(e && e.message ? e.message : String(e));
} finally {
  try { await browser?.close(); } catch {}
  try { server?.kill(); } catch {}
}

if (failed) console.log('--- failure: ' + failed + ' ---');
console.log('GAME-WITNESS: ' + (failed ? 'FAIL' : 'PASS'));
process.exit(failed ? 1 : 0);
