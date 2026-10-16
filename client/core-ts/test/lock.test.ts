// The workspace lock on the device (src/lock.ts): the hash the stations and the cloud compute (the same values in
// their tests), the device's claim for an endpoint, an app's signing key, which a web page never has.
import assert from "node:assert/strict";
import { createPrivateKey, createPublicKey, verify } from "node:crypto";
import { test } from "node:test";
import { Effect } from "effect";
import { HostError } from "../src/error.ts";
import { Signer, endpointBytes, entryHash, lockClaim, next, shortCode, signedBytes } from "../src/lock.ts";
import { FakeHost } from "../src/testing.ts";

const PKCS8_ED25519 = Buffer.from("302e020100300506032b657004220420", "hex");
const publicOf = (hex: string) => createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: Buffer.from(hex, "hex").toString("base64url") }, format: "jwk" });

test("the hash and the short code are the stations' and the cloud's", () => {
  const e = { v: 1 as const, ws: "01HZZZZZZZZZZZZZZZZZZZZZZZ", seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字", exp: 1702592000 } };
  assert.equal(entryHash(e), "27e965570b626031e9640b781bdba3b5bb111ba2307b81bd9af8d14158f8578a");
  assert.equal(shortCode("cd".repeat(32)), "UJV-HA9");
  assert.deepEqual(next("w", null, 1.7, "genesis", {}), { v: 1, ws: "w", seq: 0, prev: null, at: 1, kind: "genesis", body: {} });
  assert.deepEqual(next("w", { seq: 4, hash: "h", genesis: "g" }, 9, "member", {}).prev, "h");
});

test("a device's claim: its base key (its iroh id) vouches for one endpoint in one workspace", () => {
  const seed = new Uint8Array(32).fill(7);
  const id = Buffer.from(createPublicKey(createPrivateKey({ key: Buffer.concat([PKCS8_ED25519, seed]), format: "der", type: "pkcs8" })).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  const claim = lockClaim(seed, "ws1", "ef".repeat(32));
  assert.equal(claim.device, id);
  assert.ok(verify(null, Buffer.from(endpointBytes("ws1", "ef".repeat(32))), publicOf(id), Buffer.from(claim.proof, "hex")));
  assert.ok(!verify(null, Buffer.from(endpointBytes("ws2", "ef".repeat(32))), publicOf(id), Buffer.from(claim.proof, "hex")));
});

test("an app keeps a signing key and signs entries with it; a web page has none", async () => {
  const web = new FakeHost();
  assert.equal(await Effect.runPromise(Signer.load(web)), null);
  await assert.rejects(Effect.runPromise(Signer.make(web)), /web page signs nothing/);
  const app = new FakeHost();
  app.appKeys = true;
  const signer = await Effect.runPromise(Signer.make(app));
  assert.equal((await Effect.runPromise(Signer.load(app)))?.id, signer.id, "kept");
  const e = signer.sign(next("ws1", null, 1000, "genesis", { owner: "a" }));
  assert.ok(verify(null, Buffer.from(signedBytes(entryHash(e))), publicOf(signer.id.slice(8)), Buffer.from(e.sig.sig, "hex")));
});

/// An app's host that seals values (Android's Keystore, the desktop's safeStorage), in memory: what it was asked to keep
/// and how, and a failure to give where a test wants one.
class SealingHost extends FakeHost {
  readonly sealed = new Map<string, { value: Uint8Array; user: boolean }>();
  failSet = false;
  constructor() {
    super();
    this.appKeys = true;
  }
  secureGet(key: string, opts: { user: boolean }): Effect.Effect<Uint8Array | null, HostError> {
    return Effect.suspend(() => {
      const kept = this.sealed.get(key);
      if (kept && kept.user !== opts.user) return Effect.fail(new HostError("kept with the other `user`"));
      return Effect.succeed(kept?.value ?? null);
    });
  }
  secureSet(key: string, value: Uint8Array, opts: { user: boolean }): Effect.Effect<void, HostError> {
    return Effect.suspend(() => (this.failSet ? Effect.fail(new HostError("the keystore said no")) : Effect.sync(() => void this.sealed.set(key, { value, user: opts.user }))));
  }
  secureDelete(key: string): Effect.Effect<void, HostError> {
    return Effect.sync(() => void this.sealed.delete(key));
  }
}

test("a host that seals keeps the signing key sealed, read without asking; one in a plain file moves in", async () => {
  // Made new: sealed, no file.
  const fresh = new SealingHost();
  const made = await Effect.runPromise(Signer.make(fresh));
  assert.deepEqual([...fresh.sealed.keys()], ["lock-signer"]);
  assert.equal(fresh.sealed.get("lock-signer")?.user, false);
  assert.equal(fresh.stored("lock-signer"), undefined);
  assert.equal((await Effect.runPromise(Signer.load(fresh)))?.id, made.id);

  // An app from before kept it as a file: the same key, now sealed, and the file gone.
  const before = new FakeHost();
  before.appKeys = true;
  const old = await Effect.runPromise(Signer.make(before));
  const moved = new SealingHost();
  moved.store("lock-signer", before.stored("lock-signer")!);
  assert.equal((await Effect.runPromise(Signer.load(moved)))?.id, old.id);
  assert.equal(moved.stored("lock-signer"), undefined, "the file is gone");
  assert.equal(moved.sealed.get("lock-signer")?.user, false);
  assert.equal((await Effect.runPromise(Signer.make(moved))).id, old.id, "and it is the one used from then on");

  // Sealing fails: the file stays, and nothing is signed with a key of another.
  const stuck = new SealingHost();
  stuck.store("lock-signer", before.stored("lock-signer")!);
  stuck.failSet = true;
  await assert.rejects(Effect.runPromise(Signer.load(stuck)), /keystore said no/);
  await assert.rejects(Effect.runPromise(Signer.make(stuck)), /keystore said no/);
  assert.ok(stuck.stored("lock-signer"), "the file is kept");
  stuck.failSet = false;
  assert.equal((await Effect.runPromise(Signer.load(stuck)))?.id, old.id, "and moves in once sealing works");

  // Both there (a move cut short after sealing): the sealed one is the key, and the file goes.
  const both = new SealingHost();
  both.sealed.set("lock-signer", { value: before.stored("lock-signer")!, user: false });
  both.store("lock-signer", before.stored("lock-signer")!);
  assert.equal((await Effect.runPromise(Signer.load(both)))?.id, old.id);
  assert.equal(both.stored("lock-signer"), undefined);
});
