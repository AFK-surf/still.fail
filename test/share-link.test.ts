import assert from "node:assert/strict";
import { test } from "node:test";
import { fromBase64url, linkHash, parseLink, toBase64url } from "../web/src/share/link.ts";

// A published chat's link (web/src/share/link.ts): https://share.still.fail/#<station>.<id>.<key>.

const station = "4f6a1c9e0b2d3a5f7e8c9d0a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4";
const id = "AbCdEfGhIjKlMn_-";
const key = "k".repeat(42) + "A";

test("a link names the station by its key in hex, the snapshot and what reads it", () => {
  const hash = linkHash(station, id, key);
  assert.match(hash, /^#[A-Za-z0-9_-]{43}\.AbCdEfGhIjKlMn_-\.k{42}A$/);
  assert.deepEqual(parseLink(hash), { station, id, key });
  // As location.hash gives it, or without its #; spaces copied around it go.
  assert.deepEqual(parseLink(hash.slice(1)), { station, id, key });
  assert.deepEqual(parseLink(` ${hash}\n`), { station, id, key });
  // Every key: the bytes iroh dials by, round and back.
  for (const hex of ["00".repeat(32), "ff".repeat(32), "80".repeat(31) + "01"]) assert.equal(parseLink(linkHash(hex, id, key))?.station, hex);
});

test("a link cut short, mangled or of something else is none", () => {
  const hash = linkHash(station, id, key);
  for (const bad of ["", "#", hash.slice(0, -1), `${hash}x`, hash.replace(".", ""), hash.replace(/\./g, "/"), `#${"A".repeat(43)}.${id}`, hash.replace("-", "+"), `#${station}.${id}.${key}`]) {
    assert.equal(parseLink(bad), null, bad);
  }
  // 43 characters with bits to spare in the last: not a key's base64url.
  const loose = toBase64url(new Uint8Array(32)).slice(0, 42) + "B";
  assert.equal(parseLink(`#${loose}.${id}.${key}`), null);
});

test("base64url both ways", () => {
  const bytes = Uint8Array.from({ length: 32 }, (_, i) => (i * 37 + 251) % 256);
  assert.deepEqual(fromBase64url(toBase64url(bytes)), bytes);
  assert.equal(toBase64url(Uint8Array.of(0xfb, 0xff)), "-_8");
  for (const bad of ["a", "a+b", "ab=", "A".repeat(5)]) assert.equal(fromBase64url(bad), null, bad);
});
