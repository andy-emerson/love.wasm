// Step-4 graphics witness driver, shared by both legs (same pump contract as
// wasi/audio/driver.mjs: self-contained, stringifiable into a page). Pumps the
// resident coroutine until the witness returns its verdict, echoing each yielded
// line into the transcript.
export async function driveGraphics(x, bootSrc, schedule, log) {
  const te = new TextEncoder(), td = new TextDecoder();
  const mem = () => new Uint8Array(x.memory.buffer);
  const put = (s) => {
    const b = te.encode(s);
    mem().set(b, x.pump_in(b.length));
    return b.length;
  };
  const out = () => { const p = x.pump_out(); return td.decode(mem().slice(p, p + x.pump_out_len())); };
  const tick = () => new Promise((r) => schedule(r));

  let st = x.pump_boot(put(bootSrc));
  let frames = 0;
  while (st >= 0 && frames < 1000) {
    log(out());
    await tick();
    st = x.pump_frame(put('t'));
    frames++;
  }
  if (st === -1) {
    const verdict = out();
    log('final: ' + verdict);
    return /: PASS$/.test(verdict);
  }
  log('pump status ' + st + ': ' + out());
  return false;
}
