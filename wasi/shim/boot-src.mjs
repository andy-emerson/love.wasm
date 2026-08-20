// The pump boot source for the shim witness.
//
// It is JUST the witness now. love.shim is preloaded by the ARTIFACT
// (wasi/boot/pump-ext.cpp embeds the Lua and registers it beside `love`), so
// require("love.shim") resolves against the real module rather than a copy this
// harness injected. That distinction is the whole point of the change: an
// earlier version of this file synthesised
//   package.preload["love.shim"] = function(...) <the .lua text> end
// which meant every green run was testing the harness's copy, and the artifact
// itself shipped nothing.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

export function shimBootSrc() {
  return readFileSync(join(here, 'witness-shim.lua'), 'utf8');
}
