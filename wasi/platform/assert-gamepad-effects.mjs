// #58 — the host-side half of the 6.5 rumble witness, shared by the node and
// browser legs (run-node-joystick.mjs / run-browser-joystick.mjs) so both
// assert the SAME facts about the same effects log. witness-joystick.lua calls
// setVibration(1, 0.5, 0.25) then setVibration() (stop) on the scripted pad;
// the love_gamepad host (wasi/host/gamepad-host.mjs) records every request it
// received and whether it drove the actuator. These assertions pin that record:
//   - exactly two requests reached the host, in order: the rumble, the stop;
//   - the rumble carried the exact dual-rumble magnitudes (strong=left=1,
//     weak=right=0.5) and the 250ms duration, and the actuator WAS driven;
//   - the stop zeroed both magnitudes and was applied too.
export function assertVibrationEffects(effects, log) {
  let ok = true;
  const check = (name, cond, got) => {
    if (cond) { log('ok   [host] ' + name); return; }
    ok = false;
    log('FAIL [host] ' + name + '   got: ' + JSON.stringify(got));
  };

  const vib = (effects && effects.vibration) || [];
  check('host observed exactly two vibration requests (rumble, stop)',
    vib.length === 2, vib.length);
  const [rumble, stop] = [vib[0] || {}, vib[1] || {}];
  check('rumble request: slot 0, strong(left)=1, weak(right)=0.5, 250ms, applied',
    rumble.slot === 0 && rumble.left === 1 && rumble.right === 0.5
      && rumble.durationMs === 250 && rumble.stop === false && rumble.applied === true,
    rumble);
  check('stop request: slot 0, zero magnitudes, applied',
    stop.slot === 0 && stop.left === 0 && stop.right === 0
      && stop.stop === true && stop.applied === true,
    stop);
  return ok;
}
