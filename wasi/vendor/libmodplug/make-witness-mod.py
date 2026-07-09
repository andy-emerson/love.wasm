#!/usr/bin/env python3
# Synthesize a minimal, audible 4-channel ProTracker MOD for the libmodplug
# witness: one 64-byte square-wave sample at full volume, one pattern whose
# first row triggers it (note C-2, Amiga period 428). Deterministic — the same
# bytes every run — so the witness has a stable, auditable input without
# committing a binary blob. Writes the raw MOD to stdout.
import sys, struct

def be16(v):
    return struct.pack('>H', v)

out = bytearray()
out += b'modplug witness'.ljust(20, b'\0')          # 20-byte song title

# 31 sample descriptors, 30 bytes each. Only sample 1 is real.
for i in range(31):
    name = b''.ljust(22, b'\0')
    if i == 0:
        length_words, vol, rep_start, rep_len = 32, 64, 0, 1   # 64 bytes, full vol, no loop
    else:
        length_words, vol, rep_start, rep_len = 0, 0, 0, 1
    out += name + be16(length_words) + bytes([0, vol]) + be16(rep_start) + be16(rep_len)

out += bytes([1])          # song length: 1 pattern in the order
out += bytes([127])        # restart position
out += bytes([0]) * 128    # order table (pattern 0 first)
out += b'M.K.'             # 4-channel ProTracker tag

# Pattern 0: 64 rows x 4 channels x 4 bytes. Row 0, channel 0 plays sample 1.
pat = bytearray(1024)
period, sample = 428, 1
pat[0] = (sample & 0xF0) | ((period >> 8) & 0x0F)
pat[1] = period & 0xFF
pat[2] = ((sample << 4) & 0xF0) | 0x00
pat[3] = 0x00
out += pat

# Sample data: a 64-byte square wave (signed 8-bit).
out += bytes([0x7F] * 32 + [0x81] * 32)

sys.stdout.buffer.write(bytes(out))
