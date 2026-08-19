// Write the combined shim+witness boot source to a file, for harnesses that
// take a witness path rather than a source string (wasi/graphics/run-browser-love.mjs).
// Usage: node emit-boot.mjs <out.lua>
import { writeFileSync } from 'node:fs';
import { shimBootSrc } from './boot-src.mjs';
writeFileSync(process.argv[2], shimBootSrc());
