// Assemble the pump's boot source for the shim witness: register love.shim as a
// real module through package.preload, then run the witness that requires it.
//
// package.preload is the same door LÖVE's own submodules arrive through (see
// wasi/platform/witness-frame.lua), so the witness exercises the shim exactly as
// the boot wrapper will load it — as a module, not as text pasted into the test.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

export function shimBootSrc() {
  const shim = readFileSync(join(here, 'love-shim.lua'), 'utf8');
  const witness = readFileSync(join(here, 'witness-shim.lua'), 'utf8');
  return `package.preload["love.shim"] = function(...)\n${shim}\nend\n${witness}`;
}
