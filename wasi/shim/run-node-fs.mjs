// Node leg of the love.shim witness on the LOVE + DATA + MATH + FILESYSTEM
// artifact (wasi/boot/config). This is the artifact that closes the two tiers
// the physics build cannot reach: love.math.compress/decompress, and the four
// love.filesystem predicates 11.0 replaced with getInfo and 12 removed.
//
// The host fs seeds main.lua / conf.lua, which is what the filesystem legs
// assert against — they check AGREEMENT with getInfo, not mere existence.
// Usage: node run-node-fs.mjs <love-fs2.wasm>
import { readFileSync } from 'node:fs';
import { driveWitness } from '../platform/driver.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';
import { shimBootSrc } from './boot-src.mjs';

const bytes = readFileSync(process.argv[2] ?? 'love-fs2.wasm');
const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, shimBootSrc(), {
  extraImports: { love_fs: fs.imports },
  onInstance: (instance) => fs.bind(instance.exports.memory),
});
process.exit(ok ? 0 : 1);
