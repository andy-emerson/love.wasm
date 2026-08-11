#!/usr/bin/env node
// Embed a binary file as a C header on stdout, so a witness command module can
// carry its test asset (a font, an Ogg clip, a synthesized MOD) inside the wasm
// with no host filesystem. Used by the wasi/vendor/*/run.sh witnesses.
//
//   node embed.mjs <file> <symbol> [len_symbol]
//
// Emits `unsigned char <symbol>[] = {...};` and an `unsigned int` length named
// <len_symbol> (default <symbol>_len). The length symbol is separate because
// libmodplug's witness reads mod_bytes[] with the length mod_len.
import { readFileSync } from "node:fs";

const args = process.argv.slice(2);
if (args.length < 2 || args.length > 3) {
  console.error("usage: embed.mjs <file> <symbol> [len_symbol]");
  process.exit(1);
}

const [path, symbol, lenSymbolArg] = args;
const lenSymbol = lenSymbolArg ?? `${symbol}_len`;

const data = readFileSync(path);
console.log(`unsigned char ${symbol}[] = {${Array.from(data).join(",")}};`);
console.log(`unsigned int ${lenSymbol} = ${data.length};`);
