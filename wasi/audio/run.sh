#!/usr/bin/env bash
# One-command step-5 audio witness: build the love.audio artifact and require
# STEP5-AUDIO-WITNESS: PASS under BOTH node and real Chromium (rAF-driven).
#
# With the default webaudio backend the witness also recovers a 440 Hz tone at
# the seam: the node leg taps the PCM handed to the host, the Chromium leg plays
# it through a real OfflineAudioContext and recovers the tone from WebAudio's
# rendered output. With BACKEND=null (the inert fallback) only the Lua contract
# runs (no Sources reach the seam), which still exercises the module wiring.
#
#   PREFIX=/path/to/wasi-eh wasi/audio/run.sh
#   PREFIX=/path/to/wasi-eh BACKEND=null wasi/audio/run.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
BACKEND=${BACKEND:-webaudio}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" BACKEND="$BACKEND" OUT="$TMP/love-audio.wasm" "$HERE/build.sh"

echo "== node =="
node --no-warnings "$HERE/run-node.mjs" "$TMP/love-audio.wasm"

echo "== chromium =="
node "$HERE/run-browser.mjs" "$TMP/love-audio.wasm"

# The webaudio backend also gets the real-capture mic leg: getUserMedia ->
# AudioWorklet against a Chromium fake device, driving RecordingDevice through
# the reactor (the mock legs above use the deterministic mic host).
if [ "$BACKEND" = "webaudio" ]; then
  echo "== chromium (real mic capture) =="
  node "$HERE/run-browser-mic.mjs" "$TMP/love-audio.wasm"
fi

echo "audio witness ($BACKEND): node + browser PASS"
