// Witness: the stdout tap delivers whole lines, promptly, and retains nothing
// in a live session. Node-only — it drives wasi-shim.mjs's fd_write directly
// over a bare WebAssembly.Memory, so it needs no artifact and no browser.
//
//   node wasi/host/run-stdout-tap.mjs        # exits non-zero on failure
//
// What it defends (DECISIONS.md D6 — the console channel is plain stdio):
//
//   1. An agent's probe printed from love.update reaches the consumer as a
//      whole line. A write can end mid-line, and a line split across two
//      onLog calls corrupts a console that treats each call as one entry.
//   2. Two lines in one write arrive as two entries.
//   3. A live session retains nothing. The witnesses read shim.stdout once at
//      the end of a run lasting seconds, so accumulating is right for them; a
//      game printing every frame for hours is a leak, which is why a consumer
//      that passes onWrite gets streaming and no retention.
//   4. The default (no onWrite) still accumulates everything, because ~40
//      witnesses match substrings against shim.stdout at the end of a run.
//
// Leg 5 is the demonstration that this can fail: the superseded tap, which
// sliced the accumulated buffer and trimEnd()'d it, merges two lines into one
// entry. It is kept as an executable record of the defect, not as live code.
import { makeWasiShim } from './wasi-shim.mjs';

const te = new TextEncoder();
let failures = 0;

/** Report one comparison; count failures for the exit code. */
function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) failures++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}`);
  if (!ok) console.log(`     got  ${JSON.stringify(got)}\n     want ${JSON.stringify(want)}`);
}

/** A shim bound to fresh memory, plus write(text) issuing one fd_write. */
function bound(opts) {
  const memory = new WebAssembly.Memory({ initial: 1 });
  const shim = makeWasiShim(opts);
  shim.bind(memory);
  const write = (text) => {
    const bytes = te.encode(text);
    const dv = new DataView(memory.buffer);
    const DATA = 1024, IOV = 64, NWRITTEN = 32;
    new Uint8Array(memory.buffer).set(bytes, DATA);
    dv.setUint32(IOV, DATA, true);
    dv.setUint32(IOV + 4, bytes.length, true);
    shim.imports.fd_write(1, IOV, 1, NWRITTEN);
  };
  return { shim, write };
}

/** boot.mjs's line buffer, reproduced so the witness tests the real shape. */
function lineTap() {
  const lines = [];
  let pending = '';
  const onWrite = (text) => {
    pending += text;
    let nl;
    while ((nl = pending.indexOf('\n')) >= 0) {
      lines.push(pending.slice(0, nl));
      pending = pending.slice(nl + 1);
    }
  };
  return { lines, onWrite, flush: () => { if (pending) { lines.push(pending); pending = ''; } } };
}

// 1 + 3 — a line split across two writes rejoins, and nothing is retained.
{
  const tap = lineTap();
  const { shim, write } = bound({ onWrite: tap.onWrite });
  write('alpha\nbra');
  write('vo\ncharlie\n');
  check('a line split across two writes rejoins', tap.lines, ['alpha', 'bravo', 'charlie']);
  check('streaming mode retains nothing', shim.stdout, '');
}

// 2 — two lines in one write are two entries.
{
  const tap = lineTap();
  const { write } = bound({ onWrite: tap.onWrite });
  write('one\ntwo\n');
  check('two lines in one write stay separate', tap.lines, ['one', 'two']);
}

// A trailing partial line is not held back past an explicit flush — io.write
// without a newline still reaches the console at the end of the frame.
{
  const tap = lineTap();
  const { write } = bound({ onWrite: tap.onWrite });
  write('no newline here');
  check('a partial line is withheld until flushed', tap.lines, []);
  tap.flush();
  check('flush releases the partial line', tap.lines, ['no newline here']);
}

// 4 — the default path is byte-for-byte what the ~40 existing witnesses read.
{
  const { shim, write } = bound();
  write('MARKER-A\n');
  write('MARKER-B\n');
  check('default mode accumulates everything', shim.stdout, 'MARKER-A\nMARKER-B\n');
}

// 5 — demonstrated able to fail: the superseded tap merged the two lines.
{
  const { shim, write } = bound();
  const emitted = [];
  let tapped = 0;
  const supersededDrain = () => {
    const s = shim.stdout || '';
    if (s.length > tapped) { emitted.push(s.slice(tapped).trimEnd()); tapped = s.length; }
  };
  write('one\ntwo\n');
  supersededDrain();
  check('the superseded tap merged two lines into one entry (the defect)',
        emitted, ['one\ntwo']);
}

console.log(failures ? `\n${failures} check(s) failed` : '\nSTDOUT-TAP-WITNESS: PASS');
process.exit(failures ? 1 : 0);
