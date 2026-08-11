// #58 — the host-side half of the 6.4 image-cursor witness, shared by the node
// and browser legs (run-node-input.mjs / run-browser-input.mjs) so both assert
// the SAME facts about the same effects log. witness-input.lua builds a 2x2
// rgba8 ImageData (red, green / blue, white) with hotspot (1,0) and applies it;
// the baked love_input host (wasi/host/input-host.mjs) records what actually
// reached it. These assertions pin that record:
//   - exactly one image cursor was built, 2x2, hotspot (1,0);
//   - its css value is the data-URL cursor with the EXACT pixel bytes and the
//     hotspot in `url(...) 1 0, auto` position;
//   - setCursor applied exactly that cursor's id (and nothing else).
export function assertCursorEffects(effects, log) {
  let ok = true;
  const check = (name, cond, got) => {
    if (cond) { log('ok   [host] ' + name); return; }
    ok = false;
    log('FAIL [host] ' + name + '   got: ' + JSON.stringify(got));
  };

  // The exact bytes the witness's setPixel calls produce, row-major from the
  // top-left: red, green / blue, white.
  const rgba = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255];
  const css = 'url(data:image/x-rgba8;base64,'
    + Buffer.from(rgba).toString('base64') + ') 1 0, auto';

  const built = (effects && effects.newCursor) || [];
  check('host built exactly one image cursor', built.length === 1, built.length);
  const rec = built[0] || {};
  check('image cursor is 2x2 with hotspot (1,0)',
    rec.w === 2 && rec.h === 2 && rec.hotx === 1 && rec.hoty === 0,
    { w: rec.w, h: rec.h, hotx: rec.hotx, hoty: rec.hoty });
  check('data-URL cursor carries the exact pixels and hotspot', rec.css === css,
    rec.css);
  check('setCursor applied the built cursor id (once)',
    JSON.stringify((effects && effects.cursorImage) || []) === JSON.stringify([rec.id]),
    effects && effects.cursorImage);
  return ok;
}
