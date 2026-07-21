// love_gamepad host — the browser/node fulfiller for the step-6.5 joystick/
// gamepad seam. It stands in for navigator.getGamepads(): on a real page the host
// reads the live Gamepad array each frame; here it bakes a FIXED script of frames
// so the witness is deterministic on both legs. The wasm joystick backend polls
// this once per love.event.pump() (via the weak hook in the event backend),
// DIFFING successive frames to synthesize joystick/gamepad events.
//
// The seam is POLL-based, not push-based (the Gamepad API has no event stream):
//   - gamepad_count() -> slot count for THIS poll. It ALSO advances the scripted
//     frame, and is called EXACTLY ONCE per poll by the backend, so successive
//     polls (pump()s) observe successive scripted frames. It latches the active
//     frame so the gamepad_read()s of the same poll read that frame.
//   - gamepad_read(slot, rec, cap) -> 1 and writes a 224-byte record for a
//     connected slot, 0 for an empty/absent slot.
//
// Self-contained BY CONTRACT, like wasi-shim.mjs / fs-host.mjs / input-host.mjs:
// no imports, no outer-scope references, so makeGamepadHost.toString() stringifies
// into a Playwright page and rebuilds with new Function(); the SAME host runs
// under node (DataView/TextEncoder are globals in both). So the two legs advance
// the same frames and the witness asserts the same synthesized events + state.
//
// Record wire format (224 bytes, little-endian) — matches the reader in
// wasi/platform/joystick-backend.cpp EXACTLY:
//   [0] i32 index  [4] i32 connected  [8] i32 mapping(0=none,1=standard)
//   [12] i32 axisCount(<=8)  [16] i32 buttonCount(<=24)
//   [20] i32 buttonPressedMask  [24] i32 (pad)
//   [32] f32 axes[8] (32..64)  [64] f32 buttonValues[24] (64..160)
//   [160] char id[64] (160..224)
export function makeGamepadHost() {
  let memory;
  const te = new TextEncoder();

  // A W3C "standard" gamepad has 17 buttons (0..16) and 4 axes. Each scripted
  // frame is an array of slots (gamepads); an empty array means "no gamepads".
  // `pressed` lists the W3C button indices held down that frame; a held button
  // also reports analog value 1.0.
  const frames = [
    // frame0: one standard gamepad, A(0) pressed, left stick X = +0.5.
    [ { id: 'Test Controller', mapping: 1, axisCount: 4, buttonCount: 17,
        axes: [0.5, 0, 0, 0], pressed: [0] } ],
    // frame1: A(0) released, B(1) pressed, left stick X = -1.0.
    [ { id: 'Test Controller', mapping: 1, axisCount: 4, buttonCount: 17,
        axes: [-1.0, 0, 0, 0], pressed: [1] } ],
    // frame2: no gamepads (disconnected).
    [],
  ];

  let frameIndex = 0;
  let activeFrame = [];

  const writeStr = (dv, off, s, cap) => {
    for (let i = 0; i < cap; i++) dv.setUint8(off + i, 0);
    if (!s) return;
    const bytes = te.encode(s);
    const n = Math.min(bytes.length, cap - 1);
    for (let i = 0; i < n; i++) dv.setUint8(off + i, bytes[i]);
  };

  const imports = {
    // Called ONCE per poll: latch this poll's frame, return its slot count, then
    // advance so the next poll sees the next frame. Clamps to the last frame.
    gamepad_count() {
      activeFrame = frames[Math.min(frameIndex, frames.length - 1)];
      frameIndex++;
      return activeFrame.length;
    },
    // Write the 224-byte record for a connected slot; 0 for an empty slot.
    gamepad_read(slot, recPtr, cap) {
      if (cap < 224) return 0;
      const gp = activeFrame[slot];
      if (!gp) return 0;

      const dv = new DataView(memory.buffer);
      // Zero the whole record first (axes/buttons default 0, id NUL-padded).
      for (let i = 0; i < 224; i++) dv.setUint8(recPtr + i, 0);

      let mask = 0;
      for (const b of (gp.pressed || [])) mask |= (1 << b);

      dv.setInt32(recPtr + 0, slot, true);
      dv.setInt32(recPtr + 4, 1, true);                    // connected
      dv.setInt32(recPtr + 8, gp.mapping | 0, true);       // 1 = standard
      dv.setInt32(recPtr + 12, gp.axisCount | 0, true);
      dv.setInt32(recPtr + 16, gp.buttonCount | 0, true);
      dv.setInt32(recPtr + 20, mask | 0, true);
      dv.setInt32(recPtr + 24, 0, true);                   // pad

      const axes = gp.axes || [];
      for (let i = 0; i < 8; i++)
        dv.setFloat32(recPtr + 32 + i * 4, axes[i] || 0, true);

      // A pressed button reports analog value 1.0; others 0.
      for (let i = 0; i < 24; i++) {
        const v = (gp.pressed || []).includes(i) ? 1.0 : 0.0;
        dv.setFloat32(recPtr + 64 + i * 4, v, true);
      }

      writeStr(dv, recPtr + 160, gp.id, 64);
      return 1;
    },
  };

  return {
    imports,
    bind(m) { memory = m; },
    frames,
  };
}

// The joystick witness build links the 6.4 input backend (love.event's pump lives
// there, and it is what calls the gamepad poll), so the love_input imports MUST be
// satisfied at instantiate. But the witness counts ONLY joystick/gamepad messages,
// so any injected DOM event would pollute its assertions. This companion is a
// love_input provider whose input_poll always reports an EMPTY queue and whose
// side-effect imports are inert — so love.event.pump() carries the gamepad poll
// through but adds no DOM events of its own. Self-contained by the same contract.
export function makeEmptyInputHost() {
  const imports = {
    input_poll(/* recPtr, cap */) { return 0; },       // empty DOM queue, always
    input_set_cursor_visible(/* v */) {},
    input_set_cursor_shape(/* s */) {},
    input_warp(/* x, y */) {},
    input_set_relative(/* r */) { return 0; },
    input_set_text_input(/* enable, x, y, w, h */) {},
  };
  return {
    imports,
    bind(/* m */) {},
  };
}
