// Validate the loader's local reuse against actual Wasm execution through branches and loop back-edges.
import assert from 'node:assert/strict';
import { compactStart } from './compact.mjs';
const u = value => { const a = []; do { let c = value & 127; value >>>= 7; if (value) c |= 128; a.push(c); } while (value); return a; };
const str = value => [...u(Buffer.byteLength(value)), ...Buffer.from(value)];
const section = (id, body) => [id, ...u(body.length), ...body];
const body = code => [...u(code.length), ...code];
const code = [
  1, 9, 0x7f,                         // nine i32 locals
  0x41, 7, 0x21, 0,                  // local 0 is live across the branches
  0x41, 42, 0x21, 1, 0x20, 1, 0x1a,
  0x10, 0, 0x04, 0x40,               // if choose()
    0x41, 5, 0x21, 2,
    0x20, 2, 0x41, 1, 0x6a, 0x21, 3,
    0x20, 3, 0x24, 0,
  0x05,
    0x41, 9, 0x21, 4,
    0x20, 4, 0x24, 0,
  0x0b,
  0x20, 0, 0x23, 0, 0x6a, 0x24, 0,
  0x20, 5, 0x23, 0, 0x6a, 0x24, 0, // local 5 must retain its initial zero
  0x10, 0, 0x04, 0x40,
    0x41, 8, 0x21, 6,                // a write skipped when choose() is false
  0x0b,
  0x20, 6, 0x23, 0, 0x6a, 0x24, 0,
  0x41, 3, 0x21, 7,
  0x41, 0, 0x21, 8,
  0x02, 0x40, 0x03, 0x40,           // sum 3 + 2 + 1 across loop iterations
    0x20, 7, 0x45, 0x0d, 1,
    0x20, 8, 0x20, 7, 0x6a, 0x21, 8,
    0x20, 7, 0x41, 1, 0x6b, 0x21, 7,
    0x0c, 0,
  0x0b, 0x0b,
  0x20, 8, 0x23, 0, 0x6a, 0x24, 0,
  0x0b,
];
const getter = [0, 0x23, 0, 0x0b];
const fixture = Buffer.from([
  0, 97, 115, 109, 1, 0, 0, 0,
  ...section(1, [2, 0x60, 0, 0, 0x60, 0, 1, 0x7f]),
  ...section(2, [1, ...str('env'), ...str('choose'), 0, 1]),
  ...section(3, [2, 0, 1]),
  ...section(6, [1, 0x7f, 1, 0x41, 0, 0x0b]),
  ...section(7, [1, ...str('result'), 0, 2]),
  ...section(8, [1]),
  ...section(10, [2, ...body(code), ...body(getter)]),
]);
assert(WebAssembly.validate(fixture));
const compacted = compactStart(fixture);
assert(WebAssembly.validate(compacted));
for (const [choice, expected] of [[0, 22], [1, 27]]) {
  const imports = { env: { choose: () => choice } };
  const before = new WebAssembly.Instance(new WebAssembly.Module(fixture), imports).exports.result();
  const after = new WebAssembly.Instance(new WebAssembly.Module(compacted), imports).exports.result();
  assert.equal(before, expected);
  assert.equal(after, expected);
}
assert.throws(() => compactStart(Buffer.from([0, 97, 115, 109, 1, 0, 0, 0])), /no local start/);
assert.throws(() => compactStart(Buffer.from([0, 97, 115])), /not a classic Wasm module/);
const simd = Buffer.from([
  0, 97, 115, 109, 1, 0, 0, 0,
  ...section(1, [1, 0x60, 0, 0]), ...section(3, [1, 0]), ...section(8, [0]),
  ...section(10, [1, ...body([0, 0xfd, 0x0c, ...Array(16).fill(0), 0x1a, 0x0b])]),
]);
assert(WebAssembly.validate(simd));
assert.throws(() => compactStart(simd), /unsupported Wasm instruction fd/);
console.log('compact-test: branch paths, initial zeroes and loop-carried values preserved; unsupported instructions rejected');
