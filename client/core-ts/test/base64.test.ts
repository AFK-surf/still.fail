// Base64 as the core reads it from the clients (a file's parts, keys): the bytes back exactly, anything else refused
// (the `base64` crate's STANDARD with its padding), as Node's own decoder reads the same text.
import assert from "node:assert/strict";
import { test } from "node:test";
import { base64, fromBase64 } from "../src/util.ts";

test("what base64 says comes back as the bytes it was, at every length", () => {
  let seed = 7;
  const next = () => (seed = (seed * 1103515245 + 12345) >>> 0) & 255;
  for (let n = 0; n <= 300; n++) {
    const bytes = Uint8Array.from({ length: n }, next);
    const text = base64(bytes);
    assert.equal(text, Buffer.from(bytes).toString("base64"), `length ${n}`);
    assert.deepEqual(fromBase64(text), bytes, `length ${n}`);
  }
  const big = Uint8Array.from({ length: 1 << 20 }, next);
  assert.deepEqual(fromBase64(Buffer.from(big).toString("base64")), big);
});

test("what is not standard base64 with its padding is refused", () => {
  for (const bad of ["A", "AB", "ABC", "AB=C", "A===", "====", "AB==CDEF", "ABC=DEFG", "AB-_", "ABé=", "ABCD\n", "AB=", "AAA=AAAA"]) {
    assert.equal(fromBase64(bad), null, JSON.stringify(bad));
  }
  // Bits left over in the last character: refused, as the crate refuses them.
  assert.equal(fromBase64("AB=="), null);
  assert.equal(fromBase64("ABC="), null);
  assert.deepEqual(fromBase64("AA=="), new Uint8Array([0]));
  assert.deepEqual(fromBase64("AAE="), new Uint8Array([0, 1]));
  assert.deepEqual(fromBase64(""), new Uint8Array(0));
});
