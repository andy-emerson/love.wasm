#!/usr/bin/env python3
# Embed a binary file as a C header on stdout, so a witness command module can
# carry its test asset (a font, an Ogg clip, a synthesized MOD) inside the wasm
# with no host filesystem. Used by the wasi/vendor/*/run.sh witnesses.
#
#   embed.py <file> <symbol> [len_symbol]
#
# Emits `unsigned char <symbol>[] = {...};` and an `unsigned int` length named
# <len_symbol> (default <symbol>_len). The length symbol is separate because
# libmodplug's witness reads mod_bytes[] with the length mod_len.
import sys

if not (3 <= len(sys.argv) <= 4):
    sys.exit("usage: embed.py <file> <symbol> [len_symbol]")

path, symbol = sys.argv[1], sys.argv[2]
len_symbol = sys.argv[3] if len(sys.argv) == 4 else symbol + "_len"

data = open(path, "rb").read()
print("unsigned char %s[] = {%s};" % (symbol, ",".join(str(b) for b in data)))
print("unsigned int %s = %d;" % (len_symbol, len(data)))
