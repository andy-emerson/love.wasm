// The pump witness transcript, shared verbatim by both legs: run-node.mjs
// imports it; run-browser.mjs stringifies it into the page (so it must stay
// self-contained: no imports, no outer-scope references).
//
// drivePump(x, bootSrc, schedule, now, log) -> Promise<boolean>
//   x        the instantiated pump's exports
//   bootSrc  witness.lua source text
//   schedule cb => void   per-frame scheduler (requestAnimationFrame in the
//            browser leg — the pump's real cadence — setImmediate-ish in node)
//   now      () => ms timestamp (performance.now in both legs)
//   log      line printer
export async function drivePump(x, bootSrc, schedule, now, log) {
  const te = new TextEncoder(), td = new TextDecoder();
  const mem = () => new Uint8Array(x.memory.buffer);
  const put = (s) => {
    const b = te.encode(s);
    mem().set(b, x.pump_in(b.length));
    return b.length;
  };
  const out = () => td.decode(mem().slice(x.pump_out(), x.pump_out() + x.pump_out_len()));
  const tick = () => new Promise((r) => schedule(r));

  let failures = 0;
  const check = (name, cond, got) => {
    log((cond ? 'ok   ' : 'FAIL ') + name + (cond ? '' : '   got: ' + got));
    if (!cond) failures++;
  };

  // Boot: runs to the first yield.
  let st = x.pump_boot(put(bootSrc));
  check('boot yields BOOTED', st >= 0 && out() === 'BOOTED', st + ' ' + out());

  // Five frames on the scheduler's cadence, one resume each.
  for (let i = 1; i <= 5; i++) {
    await tick();
    st = x.pump_frame(put('t=' + now().toFixed(3)));
    const re = new RegExp('^frame ' + i + ' ack t=[0-9.]+$');
    check('frame ' + i + ' yields ack', st >= 0 && re.test(out()), st + ' ' + out());
  }

  // A crashing game: error reported with traceback, VM survives.
  st = x.pump_frame(put('explode'));
  check('explode reports PUMP_ERROR', st === -2, st);
  check('error carries message', out().includes('witness explosion at frame 6'), out());
  check('error carries traceback', out().includes('stack traceback'), out());
  st = x.pump_frame(put('t=0'));
  check('dead coroutine reports PUMP_NOBOOT', st === -3, st);

  // Re-boot on the SAME VM (LÖVE semantics: error ends the loop, not the
  // engine) and run a fresh loop to its normal end.
  st = x.pump_boot(put(bootSrc));
  check('re-boot yields BOOTED', st >= 0 && out() === 'BOOTED', st + ' ' + out());
  await tick();
  st = x.pump_frame(put('t=' + now().toFixed(3)));
  check('post-reboot frame 1', st >= 0 && /^frame 1 ack /.test(out()), st + ' ' + out());
  st = x.pump_frame(put('quit'));
  check('quit reports PUMP_DONE', st === -1 && out() === 'DONE at frame 2', st + ' ' + out());

  // Both EH legs through the one real libc++abi in this artifact.
  const eh = x.pump_eh_selftest();
  check('EH selftest (typed C++ + Lua error through C++ frame)', eh === 0, 'bitmask ' + eh);

  log(failures === 0 ? 'PUMP-WITNESS: PASS' : 'PUMP-WITNESS: FAIL (' + failures + ')');
  return failures === 0;
}
