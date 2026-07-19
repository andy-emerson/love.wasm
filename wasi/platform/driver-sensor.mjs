// Issue-#27 sensor/preview-warn witness driver, shared by both legs (same
// contract as wasi/platform/driver.mjs: self-contained, stringifiable into a
// page). The assertions live in witness-sensor.lua; this pumps the resident
// coroutine until it finishes and requires the PASS verdict, echoing each
// yielded check line. The ONE-TIME preview-warning count is asserted by each
// leg's runner from the host tap after this returns (the driver never sees the
// shim's stderr tap).
export async function driveSensor(x, bootSrc, schedule, log) {
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
    return verdict === 'STEP27-WARN-WITNESS: PASS';
  }
  log('pump status ' + st + ': ' + out());
  return false;
}
