// Generic platform-witness driver, shared by every step-6 / issue-#27 platform
// witness and both legs (self-contained + stringifiable into a page, same
// contract as wasi/boot/driver.mjs). It pumps the resident coroutine until it
// finishes and requires a "...: PASS" verdict, echoing each yielded check line.
//
// The witness-specific verdict string (STEP6-FS-WITNESS, STEP6-FS2-WITNESS,
// STEP6-WIN-WITNESS, STEP27-WARN-WITNESS, …) is informational — the driver only
// distinguishes PASS from FAIL — so ONE driver serves witness-fs.lua /
// witness-fs2.lua / witness-win.lua / witness-sensor.lua alike (each leg passes
// its own witness source as bootSrc). This replaced four byte-identical copies
// that differed only in the verdict literal.
export async function driveWitness(x, bootSrc, schedule, log) {
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
    return /:\s*PASS$/.test(verdict);
  }
  log('pump status ' + st + ': ' + out());
  return false;
}
