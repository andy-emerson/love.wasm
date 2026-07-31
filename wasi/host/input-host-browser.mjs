// The REAL browser input host — backs the love_input import surface with actual
// DOM listeners, so a person's key presses and mouse movement reach LÖVE's event
// queue. It is the live counterpart to input-host.mjs, which bakes a fixed event
// script so the 6.4 witness is deterministic on both node and Chromium.
//
// Why a sibling rather than a mode on input-host.mjs: that host is self-contained
// BY CONTRACT so one implementation can run under node:wasi and inside a
// Playwright page, and the two legs can assert the same expectations. Attaching
// DOM listeners there would break the node leg. The tree already splits hosts
// this way for the same reason — gl-host.mjs / gl-host-browser.mjs, and
// mic-host-browser.mjs beside audio-host.mjs.
//
// The record wire format is identical (128 bytes, little-endian) and is defined
// by the reader in wasi/platform/input-backend.cpp:
//   [0] double a  [8] double b  [16] double c  [24] double d
//   [32] i32 type [36] i32 i0   [40] i32 i1    [44] i32 i2
//   [48] char code[40]          [88] char key[40]
//
//   const input = makeBrowserInputHost();
//   ... instantiate with { love_input: input.imports } ...
//   input.bind(instance.exports.memory);   // before any import fires
//   input.attach(canvas);                  // starts listening
//
// Self-contained like wasi-shim.mjs — no imports, no outer-scope references — so
// makeBrowserInputHost.toString() can be stringified into a page and rebuilt with
// new Function(). It needs a DOM, so there is no node leg (expected).
//
// Three deliberate choices, each a declared divergence from desktop SDL:
//
//   1. Keys are identified by the PHYSICAL DOM `code` ("KeyA"), which the backend
//      maps to a US layout. SDL maps the live OS layout. The typed character is
//      not lost: it rides through separately as the textinput payload.
//   2. Text input is derived from keydown when `event.key` is a single character,
//      rather than from a composition-aware path. IME is deferred, so composed
//      input (CJK, dead keys) does not reach the game. An unmapped code is not
//      fatal — the backend reports "unknown".
//   3. Wheel deltas are converted to LÖVE's up-is-positive convention and
//      normalized: pixel-mode deltas are divided by 100 (one notch on typical
//      hardware), line and page modes pass through as lines. DOM wheel magnitude
//      is device-dependent and has no faithful SDL equivalent.
//
// Pointer lock is deferred: input_set_relative reports failure rather than
// pretending, and input_warp is a no-op, because a browser cannot place the
// cursor. Both are reported honestly, never faked.
export function makeBrowserInputHost() {
  let memory;
  const te = new TextEncoder();

  // Event type tags — must match EventType in wasi/platform/input-backend.cpp.
  const KEYDOWN = 1, KEYUP = 2, TEXTINPUT = 3, MOUSEMOVED = 4,
        MOUSEPRESSED = 5, MOUSERELEASED = 6, WHEEL = 7, RESIZE = 8,
        FOCUS = 9, MOUSEFOCUS = 10, VISIBLE = 11, QUIT = 12,
        TOUCHPRESSED = 13, TOUCHMOVED = 14, TOUCHRELEASED = 15;

  const queue = [];
  let target = null;
  let listeners = [];
  let lastX = 0, lastY = 0;
  let cursorVisible = true;

  // Keys a game owns, so the page does not scroll or move focus under the player.
  // Deliberately narrow: anything with a modifier is left to the browser, so
  // reload and devtools keep working while a game has focus.
  const ownedCodes = new Set([
    'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
    'Space', 'Tab', 'Backspace', 'Enter',
    'PageUp', 'PageDown', 'Home', 'End',
    'F1', 'F2', 'F3', 'F4', 'F6', 'F7', 'F8', 'F9', 'F10',
  ]);
  const ownsKey = (e) =>
    ownedCodes.has(e.code) && !e.ctrlKey && !e.metaKey && !e.altKey;

  const writeStr = (dv, off, s) => {
    for (let i = 0; i < 40; i++) dv.setUint8(off + i, 0);
    if (!s) return;
    const bytes = te.encode(s);
    const n = Math.min(bytes.length, 39);
    for (let i = 0; i < n; i++) dv.setUint8(off + i, bytes[i]);
  };

  const push = (ev) => { queue.push(ev); };

  // Canvas-pixel coordinates. The CSS box and the backing store can differ, so a
  // client point is mapped through the bounding rect into the backing store's
  // pixels — which is the space love.mouse reports and love.graphics draws in.
  const toCanvas = (e) => {
    if (!target || !target.getBoundingClientRect) return { x: e.clientX, y: e.clientY };
    const r = target.getBoundingClientRect();
    const sx = r.width ? (target.width || r.width) / r.width : 1;
    const sy = r.height ? (target.height || r.height) / r.height : 1;
    return { x: (e.clientX - r.left) * sx, y: (e.clientY - r.top) * sy };
  };

  const on = (el, type, fn, opts) => {
    el.addEventListener(type, fn, opts || false);
    listeners.push([el, type, fn, opts || false]);
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
      // Touch pressure overlays the (unused) code[] field — see the record
      // layout in input-backend.cpp. Written after the strings, so it wins.
      if (ev.p !== undefined) dv.setFloat64(recPtr + 48, ev.p, true);
      return 1;
    },
    input_set_cursor_visible(v) {
      cursorVisible = !!v;
      if (target && target.style) target.style.cursor = cursorVisible ? '' : 'none';
    },
    input_set_cursor_shape(s) {
      // LÖVE's system cursor set maps onto CSS cursor keywords for the shapes a
      // browser has; anything else falls back to the default rather than faking.
      const shapes = ['default', 'text', 'crosshair', 'progress', 'wait',
                      'not-allowed', 'nwse-resize', 'nesw-resize', 'ew-resize',
                      'ns-resize', 'move', 'pointer'];
      if (target && target.style && cursorVisible)
        target.style.cursor = shapes[s] || 'default';
    },
    // A browser cannot place the cursor, and pointer lock is deferred (it needs a
    // user gesture and changes the event model). Report honestly.
    input_warp(_x, _y) {},
    input_set_relative(_r) { return 0; },
    input_set_text_input(_enable, _x, _y, _w, _h) {},
  };

  return {
    imports,
    bind(m) { memory = m; },

    attach(el) {
      target = el;
      if (el.tabIndex === undefined || el.tabIndex < 0) el.tabIndex = 0;

      on(el, 'keydown', (e) => {
        if (ownsKey(e)) e.preventDefault();
        push({ type: KEYDOWN, code: e.code, i0: e.repeat ? 1 : 0 });
        // Printable characters become textinput, the way SDL_TEXTINPUT follows a
        // keydown. Single-code-unit test keeps modifiers and named keys out.
        if (!e.ctrlKey && !e.metaKey && !e.altKey &&
            typeof e.key === 'string' && Array.from(e.key).length === 1)
          push({ type: TEXTINPUT, key: e.key });
      });
      on(el, 'keyup', (e) => {
        if (ownsKey(e)) e.preventDefault();
        push({ type: KEYUP, code: e.code });
      });

      on(el, 'mousemove', (e) => {
        const p = toCanvas(e);
        push({ type: MOUSEMOVED, a: p.x, b: p.y, c: p.x - lastX, d: p.y - lastY });
        lastX = p.x; lastY = p.y;
      });
      on(el, 'mousedown', (e) => {
        e.preventDefault();          // keep focus on the canvas, suppress selection
        if (el.focus) el.focus();
        const p = toCanvas(e);
        lastX = p.x; lastY = p.y;
        push({ type: MOUSEPRESSED, a: p.x, b: p.y, i0: e.button, i1: e.detail || 1 });
      });
      on(el, 'mouseup', (e) => {
        const p = toCanvas(e);
        push({ type: MOUSERELEASED, a: p.x, b: p.y, i0: e.button, i1: e.detail || 1 });
      });
      on(el, 'contextmenu', (e) => e.preventDefault());  // right-click is a game button

      on(el, 'wheel', (e) => {
        e.preventDefault();
        const div = e.deltaMode === 0 ? 100 : 1;   // pixels -> notches; lines/pages pass through
        push({ type: WHEEL, a: -e.deltaX / div, b: -e.deltaY / div, i2: 0 });
      }, { passive: false });

      // Touch. A browser reports the whole live set on every TouchEvent plus a
      // changedTouches list of what actually moved, and gives no per-touch delta
      // — so the last position of each identifier is remembered here and dx/dy
      // computed from it, which is the shape love.touch reports. preventDefault
      // stops the page scrolling, pinch-zooming, or synthesizing a delayed
      // mouse click on top of a touch the game already handled.
      const lastTouch = new Map();
      const pushTouches = (e, type) => {
        e.preventDefault();
        for (const t of e.changedTouches) {
          const p = toCanvas(t);
          const prev = lastTouch.get(t.identifier);
          const dx = type === TOUCHPRESSED || !prev ? 0 : p.x - prev.x;
          const dy = type === TOUCHPRESSED || !prev ? 0 : p.y - prev.y;
          if (type === TOUCHRELEASED) lastTouch.delete(t.identifier);
          else lastTouch.set(t.identifier, p);
          // force is 0 on hardware that cannot measure it, which is not the same
          // as "not touching"; LÖVE's contract is 1 for a plain press.
          push({ type, a: p.x, b: p.y, c: dx, d: dy, i0: t.identifier | 0,
                 p: t.force > 0 ? t.force : 1 });
        }
      };
      on(el, 'touchstart', (e) => pushTouches(e, TOUCHPRESSED), { passive: false });
      on(el, 'touchmove', (e) => pushTouches(e, TOUCHMOVED), { passive: false });
      on(el, 'touchend', (e) => pushTouches(e, TOUCHRELEASED), { passive: false });
      // A cancelled touch (the browser taking over the gesture) ends it as far as
      // the game is concerned; leaving it live would strand it in getTouches().
      on(el, 'touchcancel', (e) => pushTouches(e, TOUCHRELEASED), { passive: false });

      on(el, 'mouseenter', () => push({ type: MOUSEFOCUS, i0: 1 }));
      on(el, 'mouseleave', () => push({ type: MOUSEFOCUS, i0: 0 }));
      on(el, 'focus', () => push({ type: FOCUS, i0: 1 }));
      // Losing focus releases nothing by itself; the shell pauses the pump, so a
      // key held at blur is still held when focus returns — same as desktop.
      on(el, 'blur', () => push({ type: FOCUS, i0: 0 }));

      const doc = el.ownerDocument;
      if (doc) {
        on(doc, 'visibilitychange', () =>
          push({ type: VISIBLE, i0: doc.visibilityState === 'visible' ? 1 : 0 }));
      }
      return this;
    },

    // Canvas size changes are the shell's to report: it owns the element's box,
    // and love.window is the seam that resizes the backing store.
    resized(w, h) { push({ type: RESIZE, i0: w | 0, i1: h | 0 }); },

    // No DOM event means "the player closed the game", so the shell decides.
    quit() { push({ type: QUIT }); },

    detach() {
      for (const [el, type, fn, opts] of listeners) el.removeEventListener(type, fn, opts);
      listeners = [];
      target = null;
    },

    pending() { return queue.length; },
  };
}
