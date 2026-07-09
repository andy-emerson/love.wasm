#!/usr/bin/env python3
# Step-0 EH witness, third leg: run eh-typed-catch.cpp's artifact in wasmtime
# (issue #5). node:wasi and Chromium are both V8; wasmtime is Cranelift — a
# fully independent implementation, so agreement here lifts the EH-encoding
# claim to the durability scale's top rung (cross-checked, not just observed).
#
#   python3 run-wasmtime.py <module.wasm> [pass-sentinel]
#
# Requires the `wasmtime` PyPI package (pip install wasmtime). The module is a
# wasm32-wasi COMMAND (has _start, writes the transcript to stdout, proc_exits
# 0/1). We enable the exception-handling proposal explicitly — the standardized
# exnref encoding this repo emits needs it (the bare default rejects try_table).
# The optional second arg is the transcript sentinel to require (default the
# EH witness's); the SjLj witness passes its own.
import sys

try:
    import wasmtime
except ModuleNotFoundError:
    print("wasmtime not installed (pip install wasmtime); skipping", file=sys.stderr)
    sys.exit(0)

def main(path: str, sentinel: str) -> int:
    cfg = wasmtime.Config()
    cfg.wasm_exceptions = True          # the exnref proposal our artifacts use
    engine = wasmtime.Engine(cfg)
    store = wasmtime.Store(engine)
    module = wasmtime.Module.from_file(engine, path)
    linker = wasmtime.Linker(engine)
    linker.define_wasi()

    import tempfile, os
    with tempfile.NamedTemporaryFile("r+", delete=False) as tf:
        outp = tf.name
    try:
        wasi = wasmtime.WasiConfig()
        wasi.stdout_file = outp
        store.set_wasi(wasi)

        instance = linker.instantiate(store, module)
        start = instance.exports(store)["_start"]
        code = 0
        try:
            start(store)
        except wasmtime.ExitTrap as e:
            code = e.code

        with open(outp) as fh:
            transcript = fh.read()
    finally:
        os.unlink(outp)   # clean up even if instantiate/run raised
    sys.stdout.write(transcript)

    ok = code == 0 and sentinel in transcript
    print(f"--- wasmtime exit: {code} ---")
    return 0 if ok else 1

if __name__ == "__main__":
    if not 2 <= len(sys.argv) <= 3:
        print("usage: run-wasmtime.py <module.wasm> [pass-sentinel]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "EH-WITNESS: PASS"))
