// A test program built for Wasm (moon test --target wasm-gc --release --build-only), run as scripts/test.sh runs a
// native one through tools/testexe: `node scripts/wasmtest.mjs PROGRAM.wasm PACKAGE FILE:FROM-TO[/FILE:FROM-TO…]`
// asks moonrun for those tests as moon test asks it (--test-args); they say what they said (the driver's markers,
// which testexe reads).
import { spawnSync } from 'node:child_process';

const [program, pkg, arg] = process.argv.slice(2);
if (!arg) {
  process.stderr.write('usage: node scripts/wasmtest.mjs PROGRAM.wasm PACKAGE FILE:FROM-TO[/…]\n');
  process.exit(2);
}
const files = arg.split('/').map(part => {
  const m = /^(.*):(\d+)-(\d+)$/.exec(part);
  if (!m) {
    process.stderr.write(`wasmtest: not FILE:FROM-TO: ${part}\n`);
    process.exit(2);
  }
  return [m[1], [{ start: Number(m[2]), end: Number(m[3]) }]];
});
const run = spawnSync('moonrun', ['--test-args', JSON.stringify({ package: pkg, file_and_index: files }), program, '--'],
  { stdio: 'inherit' });
if (run.error) {
  process.stderr.write(`wasmtest: moonrun: ${run.error.message}\n`);
  process.exit(2);
}
process.exit(run.status ?? 1);
