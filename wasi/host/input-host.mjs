// love_input host — the browser/node fulfiller for the step-6.4 input seam. It
// stands in for the DOM event source: on a real page the host attaches
// keydown/keyup/pointer/wheel/resize listeners to the canvas and QUEUES each
// event; here it bakes a FIXED script of events (below) so the witness is
// deterministic on both legs. The wasm Event backend drains the queue one record
// at a time through input_poll(), once per love.event.pump().
//
// Self-contained BY CONTRACT, like wasi-shim.mjs / fs-host.mjs: no imports, no
// outer-scope references, so makeInputHost.toString() stringifies into a
// Playwright page and rebuilds with new Function(), and the SAME host runs under
// node (DataView/TextEncoder are globals in both). So the two legs push the same
// events and compare against the same expectations.
//
//   const input = makeInputHost();
//   ... instantiate with { love_input: input.imports } ...
//   input.bind(instance.exports.memory);   // before any import fires
//
// The record wire format (128 bytes, little-endian) matches the reader in
// wasi/platform/input-backend.cpp exactly:
//   [0] double a  [8] double b  [16] double c  [24] double d
//   [32] i32 type [36] i32 i0   [40] i32 i1    [44] i32 i2
//   [48] char code[40]          [88] char key[40]
export function makeInputHost() {
  let memory;
  const te = new TextEncoder();

  // Event type tags (must match EventType in input-backend.cpp).
  const KEYDOWN = 1, KEYUP = 2, TEXTINPUT = 3, MOUSEMOVED = 4,
        MOUSEPRESSED = 5, MOUSERELEASED = 6, WHEEL = 7, RESIZE = 8,
        FOCUS = 9, MOUSEFOCUS = 10, VISIBLE = 11, QUIT = 12;

  // The baked event script. DOM button codes are 0/1/2 (left/middle/right); the
  // backend remaps to LÖVE 1/3/2. The witness (witness-input.lua) asserts the
  // exact translated sequence + the resulting keyboard/mouse state.
  const script = [
    { type: KEYDOWN, code: 'KeyA', i0: 0 },                       // keypressed a/a/false
    { type: TEXTINPUT, key: 'A' },                                // textinput "A"
    { type: KEYUP, code: 'KeyA' },                                // keyreleased a/a
    { type: KEYDOWN, code: 'ArrowLeft', i0: 0 },                  // keypressed left/left (held)
    { type: MOUSEMOVED, a: 10, b: 20, c: 10, d: 20 },            // mousemoved 10,20,10,20
    { type: MOUSEPRESSED, a: 10, b: 20, i0: 0, i1: 1 },          // mousepressed button1(left)
    { type: MOUSEPRESSED, a: 10, b: 20, i0: 2, i1: 1 },          // mousepressed button2(right)
    { type: MOUSERELEASED, a: 10, b: 20, i0: 0, i1: 1 },         // mousereleased button1(left)
    { type: WHEEL, a: 0, b: 1, i2: 0 },                          // wheelmoved 0,1,standard
    { type: RESIZE, i0: 800, i1: 600 },                          // resize 800,600
    { type: QUIT },                                               // quit
  ];

  const queue = script.slice();

  // Side effects the guest requests, recorded so a leg can assert them.
  const effects = { cursorVisible: [], cursorShape: [], warp: [], relative: [], textInput: [] };

  const writeStr = (dv, off, s) => {
    for (let i = 0; i < 40; i++) dv.setUint8(off + i, 0);
    if (!s) return;
    const bytes = te.encode(s);
    const n = Math.min(bytes.length, 39);
    for (let i = 0; i < n; i++) dv.setUint8(off + i, bytes[i]);
  };

  const imports = {
    // input_poll(rec, cap) -> 1 if an event was written, 0 if the queue is empty.
    input_poll(recPtr, cap) {
      if (cap < 128 || queue.length === 0) return 0;
      const ev = queue.shift();
      const dv = new DataView(memory.buffer);
      dv.setFloat64(recPtr + 0, ev.a || 0, true);
      dv.setFloat64(recPtr + 8, ev.b || 0, true);
      dv.setFloat64(recPtr + 16, ev.c || 0, true);
      dv.setFloat64(recPtr + 24, ev.d || 0, true);
      dv.setInt32(recPtr + 32, ev.type | 0, true);
      dv.setInt32(recPtr + 36, ev.i0 | 0, true);
      dv.setInt32(recPtr + 40, ev.i1 | 0, true);
      dv.setInt32(recPtr + 44, ev.i2 | 0, true);
      writeStr(dv, recPtr + 48, ev.code);
      writeStr(dv, recPtr + 88, ev.key);
      return 1;
    },
    input_set_cursor_visible(v) { effects.cursorVisible.push(v); },
    input_set_cursor_shape(s) { effects.cursorShape.push(s); },
    input_warp(x, y) { effects.warp.push([x, y]); },
    input_set_relative(r) { effects.relative.push(r); return 1; },
    input_set_text_input(enable, x, y, w, h) { effects.textInput.push([enable, x, y, w, h]); },
  };

  return {
    imports,
    bind(m) { memory = m; },
    script,
    effects,
  };
}
