#!/usr/bin/env node
// Synthesize a minimal, audible 4-channel ProTracker MOD for the libmodplug
// witness: one 64-byte square-wave sample at full volume, one pattern whose
// first row triggers it (note C-2, Amiga period 428). Deterministic -- the
// same bytes every run -- so the witness has a stable, auditable input
// without committing a binary blob. Writes the raw MOD to stdout.

function be16(v) {
  const b = Buffer.alloc(2);
  b.writeUInt16BE(v, 0);
  return b;
}

const chunks = [];
chunks.push(Buffer.from("modplug witness".padEnd(20, "\0"), "binary")); // 20-byte song title

// 31 sample descriptors, 30 bytes each. Only sample 1 is real.
for (let i = 0; i < 31; i++) {
  const name = Buffer.alloc(22); // zero-filled
  let lengthWords, vol, repStart, repLen;
  if (i === 0) {
    [lengthWords, vol, repStart, repLen] = [32, 64, 0, 1]; // 64 bytes, full vol, no loop
  } else {
    [lengthWords, vol, repStart, repLen] = [0, 0, 0, 1];
  }
  chunks.push(name, be16(lengthWords), Buffer.from([0, vol]), be16(repStart), be16(repLen));
}

chunks.push(Buffer.from([1]));            // song length: 1 pattern in the order
chunks.push(Buffer.from([127]));          // restart position
chunks.push(Buffer.alloc(128, 0));        // order table (pattern 0 first)
chunks.push(Buffer.from("M.K.", "binary")); // 4-channel ProTracker tag

// Pattern 0: 64 rows x 4 channels x 4 bytes. Row 0, channel 0 plays sample 1.
const pat = Buffer.alloc(1024);
const period = 428, sample = 1;
pat[0] = (sample & 0xf0) | ((period >> 8) & 0x0f);
pat[1] = period & 0xff;
pat[2] = ((sample << 4) & 0xf0) | 0x00;
pat[3] = 0x00;
chunks.push(pat);

// Sample data: a 64-byte square wave (signed 8-bit).
chunks.push(Buffer.from([...Array(32).fill(0x7f), ...Array(32).fill(0x81)]));

process.stdout.write(Buffer.concat(chunks));
