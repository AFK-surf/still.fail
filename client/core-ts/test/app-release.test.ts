// app-release.ts: the Windows app's installer taken only as its signed words say it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ed25519 } from "@noble/curves/ed25519.js";
import { keyIdOf, winReleaseUnverified } from "../src/app-release.ts";
import { base64, utf8 } from "../src/util.ts";

const secret = ed25519.utils.randomSecretKey();
const pub = ed25519.getPublicKey(secret);
const keys = [base64(pub)];
const sha = "a".repeat(64);

/// A feed's release with `words` signed by the test key (another key's where `by` is given).
function release(words: object, over: object = {}, by: Uint8Array = secret) {
  const bytes = utf8(JSON.stringify(words));
  const signed = { release: base64(bytes), signature: base64(ed25519.sign(bytes, by)), key: keyIdOf(ed25519.getPublicKey(by)) };
  return { versionCode: 5500, versionName: "0.1.5500", file: "desktop/stillfail-0.1.5500-x64-win.exe", sha256: sha, size: 1234, signed, ...over };
}
const words = { kind: "stillfail-desktop-win", version: "0.1.5500", build: 5500, file: "stillfail-0.1.5500-x64-win.exe", sha256: sha, size: 1234 };

test("a release whose signed words are it is taken", () => {
  assert.equal(winReleaseUnverified(release(words), keys), "");
});

test("none signed, or signed by a key not taken, is not", () => {
  const { signed: _, ...bare } = release(words);
  assert.match(winReleaseUnverified(bare, keys), /not signed/);
  assert.match(winReleaseUnverified(release(words, {}, ed25519.utils.randomSecretKey()), keys), /does not take/);
});

test("words changed after signing, or another build, file, hash or size than the feed's, are not", () => {
  const r = release(words);
  r.signed.release = base64(utf8(JSON.stringify({ ...words, size: 9 })));
  assert.match(winReleaseUnverified(r, keys), /does not verify/);
  assert.match(winReleaseUnverified(release(words, { versionCode: 5501 }), keys), /offered as/);
  assert.match(winReleaseUnverified(release(words, { sha256: "b".repeat(64) }), keys), /not the one signed/);
  assert.match(winReleaseUnverified(release(words, { size: 99 }), keys), /not the one signed/);
  assert.match(winReleaseUnverified(release(words, { file: "desktop/other.exe" }), keys), /not the one signed/);
  assert.match(winReleaseUnverified(release({ ...words, kind: "stillfail-desktop-web" }), keys), /not a Windows release/);
});
