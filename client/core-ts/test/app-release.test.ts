// app-release.ts: the Windows app's installer taken only as its signed words say it; the deltas a feed offers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { ed25519 } from "@noble/curves/ed25519.js";
import { deltaFrom, feedDeltas, keyIdOf, winReleaseUnverified, winReleaseWords } from "../src/app-release.ts";
import { conform } from "../src/conform.ts";
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
  // 0.<m>.<n>: any m (the stable releases before it, only said), n its build.
  assert.equal(winReleaseUnverified(release({ ...words, version: "0.34.5500" }), keys), "");
  assert.match(winReleaseUnverified(release({ ...words, version: "0.34.5501" }), keys), /not a Windows release/);
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

test("the signed words are had where they verify, with what they say beside the feed", () => {
  const r = winReleaseWords(release({ ...words, raw: { sha256: "c".repeat(64), size: 3000 } }), keys);
  assert.ok("words" in r);
  assert.deepEqual(r.words.raw, { sha256: "c".repeat(64), size: 3000 });
  assert.deepEqual(winReleaseWords(release(words, { size: 99 }), keys), { why: "the feed's installer is not the one signed" });
});

const apk = { versionCode: 8147, versionName: "0.1.8147", file: "android/stillfail-8147.apk", sha256: "a".repeat(64), size: 10_000 };
const delta = (from: number, over: object = {}) => ({ from, file: `android/stillfail-8147.apk.from-${from}.delta`, sha256: "d".repeat(64), size: 900, ...over });

test("a feed's deltas: each from its build, what they make the feed's raw package or else the file itself", () => {
  const feed = { ...apk, deltas: [delta(8142), delta(8140, { size: 1200 })] };
  const own = feedDeltas(feed, apk);
  assert.deepEqual(deltaFrom(own, 8142), { file: "android/stillfail-8147.apk.from-8142.delta", sha256: "d".repeat(64), size: 900, makesSha256: "a".repeat(64), makesSize: 10_000 });
  assert.equal(deltaFrom(own, 8140)!.size, 1200);
  assert.equal(deltaFrom(own, 8141), null);
  assert.equal(deltaFrom(feedDeltas(apk, apk), 8142), null);
  const raw = feedDeltas({ ...feed, raw: { sha256: "b".repeat(64), size: 20_000 } }, apk);
  assert.deepEqual([deltaFrom(raw, 8142)!.makesSha256, deltaFrom(raw, 8142)!.makesSize], ["b".repeat(64), 20_000]);
  // a raw package said wrong: no delta (never the file's hash for what is not the file)
  assert.equal(feedDeltas({ ...feed, raw: { sha256: "B".repeat(64), size: 20_000 } }, apk).deltas.length, 0);
  assert.equal(feedDeltas({ ...feed, raw: { sha256: "b".repeat(64), size: 0 } }, apk).deltas.length, 0);
});

test("a delta malformed, or not smaller than the package, is not offered; the others are", () => {
  const bad = [
    delta(0), delta(-1), delta(1.5), delta(2 ** 53), { ...delta(1), from: "1" },
    delta(2, { file: "/etc/x.delta" }), delta(3, { file: "android/../x.delta" }), delta(4, { file: "https://x.test/a.delta" }),
    delta(5, { file: "a b.delta" }), delta(6, { file: "" }), delta(7, { file: 7 }), delta(8, { file: ".." }),
    delta(9, { sha256: "D".repeat(64) }), delta(10, { sha256: "d".repeat(63) }), delta(11, { sha256: null }),
    delta(12, { size: 0 }), delta(13, { size: 1.5 }), delta(14, { size: "900" }),
    delta(15, { size: 10_000 }), delta(16, { size: 10_001 }), null, 3, "x",
  ];
  const got = feedDeltas({ ...apk, deltas: [...bad, delta(8142)] }, apk);
  assert.deepEqual(got.deltas.map((d) => d.from), [8142]);
  assert.equal(feedDeltas({ ...apk, deltas: { from: 8142 } }, apk).deltas.length, 0);
  // on Windows, what the signed words say it makes or none
  assert.equal(feedDeltas({ ...apk, deltas: [delta(8142)], raw: { sha256: "b".repeat(64), size: 20_000 } }, apk, null).deltas.length, 0);
  assert.equal(deltaFrom(feedDeltas({ ...apk, deltas: [delta(8142)] }, apk, { sha256: "c".repeat(64), size: 30_000 }), 8142)!.makesSha256, "c".repeat(64));
});

test("a feed with raw and deltas still conforms to AppRelease, and they are dropped (as a core from before drops them)", () => {
  const shaped = conform("AppRelease", { ...apk, raw: { sha256: "b".repeat(64), size: 20_000 }, deltas: [delta(8142)] });
  assert.ok("ok" in shaped);
  const ok = (shaped as { ok: Record<string, unknown> }).ok;
  assert.deepEqual([ok.raw, ok.deltas, ok.delta, ok.versionCode], [undefined, undefined, null, 8147]);
  // and one without them, as before
  assert.ok("ok" in conform("AppRelease", apk));
});
