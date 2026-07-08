// Step-3 boot witness driver, shared by both legs (same contract as
// wasi/pump/driver.mjs: self-contained, stringifiable into a page).
// The assertions live in witness-boot.lua; this just pumps the resident
// coroutine until it finishes and requires the PASS verdict, echoing each
// yielded check line into the transcript.
export async function driveBoot(x, bootSrc, schedule, log) {
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
    return verdict === 'STEP3-WITNESS: PASS';
  }
  log('pump status ' + st + ': ' + out());
  return false;
}
