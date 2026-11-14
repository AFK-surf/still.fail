// The vault on the station (src/vault/): its formats, on the values the core is tested on too
// (fixtures/vault-vectors.json, made from fixed keys: `VAULT_VECTORS=write` makes it anew); who may write a vault or an
// item, in which order; what a member sees and is told. Keys are fixed or made per run; nothing waits on time.
import assert from "node:assert/strict";
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { type Entry, apply, entryHash, genesis, signedBytes as lockBytes } from "../src/cloud/lock.ts";
import { bring, handover, station as movedStation, world as movedWorld } from "./lock-moved-world.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { routes } from "../src/api/routes/vault.ts";
import { type To, isFor } from "../src/api/events.ts";
import { routes as requestRoutes } from "../src/api/routes/vault-requests.ts";
import { PlainStore } from "../src/vault/plain.ts";
import type { Request } from "../src/api/request.ts";
import {
  type BoxCert, type Grant, type Item, type Sig, type Vault, TAG, boxPublic, decrypt, encryptWith, grantContext, itemContext, itemOk,
  certOk, itemSupersedes, keyContext, newBoxPair, openSeal, recoveryPair, seal, sealWith, signedBytes, signedOk, signerOf, vaultOk, vaultSupersedes,
} from "../src/vault/crypto.ts";
import { VaultStore } from "../src/vault/store.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const VAULT = "v_01HZZZZZZZZZZZZZZZZZZZZZZZ";
const ITEM = "i_01HZZZZZZZZZZZZZZZZZZZZZZZ";
const VECTORS = new URL("./fixtures/vault-vectors.json", import.meta.url);

/// An Ed25519 key from a 32-byte seed (a fixed one for the vectors), as a lock names an app's signing key.
function ed(seed?: Uint8Array) {
  const key = seed ? createPrivateKey({ key: Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]), format: "der", type: "pkcs8" }) : generateKeyPairSync("ed25519").privateKey;
  const hex = Buffer.from(createPublicKey(key).export({ format: "jwk" }).x as string, "base64url").toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, key).toString("hex") };
}
type Key = ReturnType<typeof ed>;
const fill = (b: number, n = 32) => new Uint8Array(n).fill(b);
const hex = (b: Uint8Array) => Buffer.from(b).toString("hex");
const unhex = (h: string) => new Uint8Array(Buffer.from(h, "hex"));

/// A record signed under its tag by `key`.
function signed<T extends Record<string, unknown>>(o: T, tag: string, key: Key): T & { sig: Sig } {
  return { ...o, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(o, tag)) } };
}

const certOf = (key: Key, device: string, box: string, at = 1000): BoxCert => signed({ v: 1 as const, ws: WS, device, box, at }, TAG.box, key);

/// The vectors: fixed keys, fixed ephemerals and nonces, so the core makes the very same bytes.
function vectors() {
  const signer = ed(fill(1));
  const device = ed(fill(9)).hex;
  const boxPriv = fill(2);
  const box = boxPublic(boxPriv);
  const cert = certOf(signer, device, box);
  const vaultKey = fill(4);
  const recoveryEntropy = fill(0x7f);
  const recovery = recoveryPair(recoveryEntropy);
  const wrapped = sealWith(box, vaultKey, keyContext(WS, VAULT, 0), fill(3));
  const vault = signed({ v: 1 as const, ws: WS, id: VAULT, seq: 0, owner: "alice", name: "Personal", members: ["alice"], epoch: 0, keys: [{ cert, wrapped }], recovery: sealWith(recovery.pub, vaultKey, keyContext(WS, VAULT, 0), fill(6)), at: 1000 }, TAG.vault, signer);
  const plain = JSON.stringify({ kind: "token", name: "GitHub", fields: { value: "ghp_abc" }, domains: ["github.com"], notes: "" });
  const ct = encryptWith(vaultKey, new TextEncoder().encode(plain), itemContext(WS, VAULT, ITEM, 0, 0), fill(5, 12));
  const item = signed({ v: 1 as const, ws: WS, vault: VAULT, id: ITEM, version: 0, epoch: 0, ct, listing: { name: "GitHub", kind: "token" as const, modes: ["proxy" as const], hosts: ["api.github.com", "*.github.com"], env: "GH_TOKEN" }, at: 1001 }, TAG.item, signer);
  const requestBox = boxPublic(fill(7));
  const grant = signed({ v: 1 as const, ws: WS, request: "r_01HZZZZZZZZZZZZZZZZZZZZZZZ", vault: VAULT, item: ITEM, mode: "proxy" as const, hosts: ["api.github.com"], scope: "once" as const, exp: 1600, secret: sealWith(requestBox, new TextEncoder().encode(plain), grantContext(WS, "r_01HZZZZZZZZZZZZZZZZZZZZZZZ"), fill(8)), at: 1002 }, TAG.grant, signer);
  const deny = signed({ v: 1 as const, ws: WS, request: "r_01HZZZZZZZZZZZZZZZZZZZZZZZ", at: 1003 }, TAG.deny, signer);
  return {
    ws: WS,
    signer: { seed: hex(fill(1)), key: signer.id },
    device: { seed: hex(fill(9)), id: device },
    box: { priv: hex(boxPriv), pub: box },
    vaultKey: hex(vaultKey),
    eph: { wrap: hex(fill(3)), recovery: hex(fill(6)), grant: hex(fill(8)) },
    nonce: hex(fill(5, 12)),
    plain,
    requestBox: { priv: hex(fill(7)), pub: requestBox },
    // BIP-39's own vectors (the 24 words of 32 bytes), and the recovery key each gives.
    recovery: [fill(0), fill(0x7f), fill(0xff)].map((e) => ({ entropy: hex(e), pub: recoveryPair(e).pub })),
    words: {
      "0000000000000000000000000000000000000000000000000000000000000000": "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
      "7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f": "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth title",
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff": "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote",
    },
    cert,
    vault,
    item,
    grant,
    deny,
  };
}

test("the formats: the vectors the core is tested on are what the station makes and checks", () => {
  const v = vectors();
  if (process.env.VAULT_VECTORS === "write") writeFileSync(VECTORS, JSON.stringify(v, null, 2) + "\n");
  assert.deepEqual(JSON.parse(JSON.stringify(v)), JSON.parse(readFileSync(VECTORS, "utf8")));
  assert.ok(signedOk(v.cert, TAG.box));
  assert.ok(signedOk(v.vault, TAG.vault));
  assert.ok(signedOk(v.item, TAG.item));
  assert.ok(signedOk(v.grant, TAG.grant));
  assert.ok(signedOk(v.deny, TAG.deny));
  // Under another tag, or changed after signing: not.
  assert.equal(signedOk(v.cert, TAG.vault), false);
  assert.equal(signedOk({ ...v.vault, name: "Other" }, TAG.vault), false);
  // What the keys open.
  assert.deepEqual(openSeal(unhex(v.box.priv), v.vault.keys[0]!.wrapped, keyContext(WS, VAULT, 0)), unhex(v.vaultKey));
  assert.deepEqual(openSeal(recoveryPair(fill(0x7f)).priv, v.vault.recovery!, keyContext(WS, VAULT, 0)), unhex(v.vaultKey));
  assert.equal(new TextDecoder().decode(decrypt(unhex(v.vaultKey), v.item.ct, itemContext(WS, VAULT, ITEM, 0, 0))), v.plain);
  assert.equal(new TextDecoder().decode(openSeal(unhex(v.requestBox.priv), v.grant.secret, grantContext(WS, v.grant.request))), v.plain);
});

test("a seal opens with its key, under its context, as sealed", () => {
  const to = newBoxPair();
  const plain = new TextEncoder().encode("the vault's key");
  const sealed = seal(to.pub, plain, "ctx/1");
  assert.deepEqual(openSeal(to.priv, sealed, "ctx/1"), plain);
  // A fresh ephemeral each time.
  assert.notEqual(seal(to.pub, plain, "ctx/1"), sealed);
  assert.throws(() => openSeal(to.priv, sealed, "ctx/2"));
  assert.throws(() => openSeal(newBoxPair().priv, sealed, "ctx/1"));
  const b = Buffer.from(sealed, "base64url");
  b[40]! ^= 1;
  assert.throws(() => openSeal(to.priv, b.toString("base64url"), "ctx/1"));
  assert.throws(() => openSeal(to.priv, "AAAA", "ctx/1"), /not a seal/);
  assert.throws(() => seal("x25519:00", plain, "c"), /not an x25519 key/);
});

/// A lock: owner alice (two app devices), member bob, member carol (one each), and dave's web page (signs nothing).
function lock() {
  const people = ["alice", "bob", "carol"].map((sub) => ({ sub, signer: ed(), base: ed() }));
  const [alice, bob, carol] = people as [(typeof people)[0], (typeof people)[0], (typeof people)[0]];
  const alice2 = { sub: "alice", signer: ed(), base: ed() };
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "a@x", role: "owner" }, { sub: "bob", email: "b@x", role: "member" }, { sub: "carol", email: "c@x", role: "member" }, { sub: "dave", email: "d@x", role: "member" }],
    devices: [...[alice, alice2, bob, carol].map((p) => ({ id: p.base.hex, sub: p.sub, kind: "app", label: p.sub, sign_key: p.signer.id })), { id: ed().hex, sub: "dave", kind: "web", label: "Chrome", exp: 2000 }],
    passkeys: [], stations: [], gateways: [],
  };
  const e = { v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body } as Omit<Entry, "sig">;
  const first = { ...e, sig: { key: alice.signer.id, alg: "Ed25519" as const, sig: alice.signer.sign(lockBytes(entryHash(e as Entry))) } };
  return { alice, alice2, bob, carol, state: genesis(first) };
}
type Person = { sub: string; signer: Key; base: Key };

const boxOf = (p: Person) => certOf(p.signer, p.base.hex, newBoxPair().pub);
const ulid = (n: number) => `01HZZZZZZZZZZZZZZZZZZZZZ${String(n).padStart(2, "0")}`;

/// A vault's version, signed by `by` (alice's first device by default).
function vaultOf(w: ReturnType<typeof lock>, o: { seq?: number; members?: Person[]; epoch?: number; by?: Person; owner?: string; certs?: BoxCert[]; id?: string; deleted?: boolean }): Vault {
  const members = o.members ?? [w.alice];
  const certs = o.certs ?? (o.deleted ? [] : members.map(boxOf));
  return signed({ v: 1 as const, ws: WS, id: o.id ?? VAULT, seq: o.seq ?? 0, owner: o.owner ?? "alice", name: "Team", members: members.map((m) => m.sub), epoch: o.epoch ?? 0, keys: certs.map((cert) => ({ cert, wrapped: seal(cert.box, fill(4), keyContext(WS, o.id ?? VAULT, o.epoch ?? 0)) })), ...(o.deleted ? { deleted: true as const } : {}), at: 1000 }, TAG.vault, (o.by ?? w.alice).signer);
}

function itemOf(o: { version?: number; epoch?: number; by: Person; deleted?: boolean; id?: string; vault?: string }): Item {
  const id = o.id ?? ITEM, version = o.version ?? 0, epoch = o.epoch ?? 0;
  const ct = o.deleted ? "" : encryptWith(fill(4), new TextEncoder().encode("{}"), itemContext(WS, o.vault ?? VAULT, id, version, epoch), fill(5, 12));
  return signed({ v: 1 as const, ws: WS, vault: o.vault ?? VAULT, id, version, epoch, ct, ...(o.deleted ? { deleted: true as const } : {}), at: 1000 }, TAG.item, o.by.signer);
}

test("a vault is its owner's: signed by one of their devices, its seq one after the last, its keys for members' app devices", () => {
  const w = lock();
  const first = vaultOf(w, {});
  assert.equal(vaultOk(w.state, null, first), null);
  // Any of the owner's devices signs.
  assert.equal(vaultOk(w.state, null, vaultOf(w, { by: w.alice2 })), null);
  // Not the owner, nor someone saying they are.
  assert.match(vaultOk(w.state, null, vaultOf(w, { by: w.bob, members: [w.alice, w.bob] }))!, /owner's devices/);
  assert.equal(vaultOk(w.state, null, vaultOf(w, { by: w.bob, owner: "bob", members: [w.bob] })), null, "bob's own vault is his to sign");
  // Changed after signing.
  assert.match(vaultOk(w.state, null, { ...first, members: ["alice", "carol"] })!, /signature/);
  // The order: 0 first, then one more each time; the owner stays.
  assert.match(vaultOk(w.state, null, vaultOf(w, { seq: 1 }))!, /first version/);
  assert.match(vaultOk(w.state, first, vaultOf(w, { seq: 2 }))!, /seq 1 follows 0/);
  assert.match(vaultOk(w.state, first, vaultOf(w, { seq: 0 }))!, /seq 1 follows 0/);
  const second = vaultOf(w, { seq: 1, members: [w.alice, w.bob] });
  assert.equal(vaultOk(w.state, first, second), null);
  assert.match(vaultOk(w.state, second, vaultOf(w, { seq: 2, owner: "bob", by: w.bob, members: [w.alice, w.bob] }))!, /owner does not change/);
  // Taking bob out takes a new epoch (a new key), and the epoch never goes back.
  assert.match(vaultOk(w.state, second, vaultOf(w, { seq: 2, epoch: 0 }))!, /new epoch/);
  assert.equal(vaultOk(w.state, second, vaultOf(w, { seq: 2, epoch: 1 })), null);
  assert.match(vaultOk(w.state, vaultOf(w, { epoch: 2 }), vaultOf(w, { seq: 1, epoch: 1 }))!, /epoch does not go back/);
  // Members are the lock's.
  assert.match(vaultOk(w.state, null, { ...vaultOf(w, {}), members: ["alice", "eve"] })!, /eve is not in the lock/);
});

test("a vault's keys go to box certificates of members' app devices in the lock, each signed by its own device", () => {
  const w = lock();
  // A device not in the lock (the cloud's own, say), though signed by a key the lock names.
  const stranger = certOf(w.alice.signer, ed().hex, newBoxPair().pub);
  assert.match(vaultOk(w.state, null, vaultOf(w, { certs: [stranger] }))!, /not an app device in the lock/);
  // A device of the lock's, its certificate signed by another device's key.
  const forged = certOf(w.bob.signer, w.alice.base.hex, newBoxPair().pub);
  assert.match(vaultOk(w.state, null, vaultOf(w, { certs: [forged] }))!, /its own device's key/);
  // Changed after signing: another box key.
  const good = boxOf(w.alice);
  assert.match(vaultOk(w.state, null, vaultOf(w, { certs: [{ ...good, box: newBoxPair().pub }] }))!, /signature is invalid/);
  // A member's device, but not a member of this vault.
  assert.match(vaultOk(w.state, null, vaultOf(w, { certs: [good, boxOf(w.carol)] }))!, /member's device/);
  // One key per device.
  assert.match(vaultOk(w.state, null, vaultOf(w, { certs: [good, boxOf(w.alice)] }))!, /one key per device/);
  // Another workspace's.
  assert.match(vaultOk(w.state, null, vaultOf(w, { certs: [{ ...good, ws: "OTHER" }] }))!, /of this workspace/);
  assert.equal(vaultOk(w.state, null, vaultOf(w, { certs: [good, boxOf(w.alice2)] })), null);
});

test("a certificate uses the same rules as the full lock, including removed devices and old keys", () => {
  const w = lock();
  const cert = boxOf(w.alice);
  const original = w.state.devices.get(w.alice.base.hex)!;
  const states = [
    w.state,
    { ...w.state, devices: new Map([...w.state.devices].filter(([id]) => id !== cert.device)) },
    { ...w.state, members: new Map([...w.state.members].filter(([sub]) => sub !== "alice")) },
    { ...w.state, devices: new Map([...w.state.devices].map(([id, d]) => [id, id === cert.device ? { ...d, own: false } : d] as const)) },
    { ...w.state, devices: new Map([...w.state.devices].map(([id, d]) => [id, id === cert.device ? { ...original, sign_key: ed().id } : d] as const)) },
  ];
  const values: unknown[] = [cert, null, {}, { ...cert, device: 4 }, { ...cert, device: ed().hex }, { ...cert, ws: "other" },
    { ...cert, box: "bad" }, { ...cert, box: newBoxPair().pub }, { ...cert, at: -1 }, { ...cert, sig: { ...cert.sig, sig: "00" } }];
  const verify = { recordSigValid: (sig: Sig, tag: string, text: string) => signedOk({ ...JSON.parse(text), sig }, tag) };
  for (const state of states) for (const value of values) for (const ever of [false, true]) {
    assert.equal(certOk(state, value as BoxCert, ever), rules.cert_ok_js(state, value, ever, verify));
  }
});

test("a device back in the lock under a new signing key keeps the key it was given: a vault's keys are checked against every signing key the lock has named for their device, the same on every station", () => {
  const w = lock();
  const [a1, a2] = [boxOf(w.alice), boxOf(w.alice2)];
  const first = vaultOf(w, { certs: [a1, a2] });
  assert.equal(vaultOk(w.state, null, first), null);
  // alice's second device installed anew: in the lock again under the same id with a new signing key (2026-11-03,
  // an iPhone's), so its certificate from before is signed by a key the lock no longer names as its current one.
  const renewed = { ...w.alice2, signer: ed() };
  const body = { id: w.alice2.base.hex, sub: "alice", kind: "app", label: "alice2 again", sign_key: renewed.signer.id };
  const e = { v: 1, ws: WS, seq: 1, prev: w.state.head, at: 1100, kind: "device", body } as Omit<Entry, "sig">;
  const state = apply(w.state, { ...e, sig: { key: w.alice.signer.id, alg: "Ed25519" as const, sig: w.alice.signer.sign(lockBytes(entryHash(e as Entry))) } } as Entry, null);
  assert.equal(state.devices.get(w.alice2.base.hex)!.sign_key, renewed.signer.id);
  assert.deepEqual(state.signKeys.get(w.alice2.base.hex), [w.alice2.signer.id, renewed.signer.id]);
  // The version the owner signs to give a third device its key, the old certificate carried: taken (it was refused
  // for that certificate before, and no device could be given any); as a copy on a station that held no version or an
  // older one all the same (every station folds the same lock); as a first version too.
  const { sig: _, ...v0 } = first;
  const next = (keys: Vault["keys"], members = ["alice", "bob"]) => signed({ ...v0, seq: 1, members, keys }, TAG.vault, w.alice.signer);
  const bob = boxOf(w.bob);
  const third = next([...first.keys, { cert: bob, wrapped: seal(bob.box, fill(4), keyContext(WS, VAULT, 0)) }]);
  assert.equal(vaultOk(state, first, third), null);
  assert.equal(vaultOk(state, null, third, true), null, "a copy, on a station that held none");
  assert.equal(vaultOk(state, null, vaultOf(w, { certs: [a1, a2] })), null, "a first version under the old certificate");
  // The old certificate changed after signing: refused as ever; one signed by a key the lock never named for the
  // device: refused.
  assert.match(vaultOk(state, first, next(first.keys.map((k) => (k.cert.device === w.alice2.base.hex ? { ...k, cert: { ...k.cert, box: newBoxPair().pub } } : k))))!, /signature is invalid/);
  assert.match(vaultOk(state, first, next([...first.keys.filter((k) => k.cert.device !== w.alice2.base.hex), { cert: certOf(ed(), w.alice2.base.hex, a2.box, 1200), wrapped: first.keys[1]!.wrapped }]))!, /its own device's key/);
  // Its fresh certificate (signed by its new key) takes the old one's place as the owner's device next gives a key.
  const fresh = certOf(renewed.signer, w.alice2.base.hex, a2.box, 1200);
  assert.equal(vaultOk(state, first, next(first.keys.map((k) => (k.cert.device === w.alice2.base.hex ? { ...k, cert: fresh } : k)), ["alice"])), null);
  // Published anew (PUT vault/boxes), a certificate is its device's current key's: the old one is not taken there.
  assert.match(certOk(state, a2)!, /its own device's key/);
  assert.equal(certOk(state, fresh), null);
  assert.equal(certOk(state, a2, true), null, "a previously held certificate can use its historical signing key");
  // A device no longer in the lock at all: its key is no key (taking it out takes a new epoch).
  const gone = { ...state, devices: new Map([...state.devices].filter(([id]) => id !== w.alice2.base.hex)) };
  assert.match(vaultOk(gone, first, third)!, /not an app device in the lock/);
  // Taken out of the lock and put back under the same id (the same device) with a third key: the keys it had stay
  // named for it, so a version still carrying its first certificate is taken.
  const out = { v: 1, ws: WS, seq: 2, prev: state.head, at: 1300, kind: "device.remove", body: { id: w.alice2.base.hex } } as Omit<Entry, "sig">;
  const removed = apply(state, { ...out, sig: { key: w.alice.signer.id, alg: "Ed25519" as const, sig: w.alice.signer.sign(lockBytes(entryHash(out as Entry))) } } as Entry, null);
  assert.match(vaultOk(removed, first, third)!, /not an app device in the lock/);
  const third_key = ed();
  const back = { v: 1, ws: WS, seq: 3, prev: removed.head, at: 1400, kind: "device", body: { ...body, label: "alice2 once more", sign_key: third_key.id } } as Omit<Entry, "sig">;
  const again = apply(removed, { ...back, sig: { key: w.alice.signer.id, alg: "Ed25519" as const, sig: w.alice.signer.sign(lockBytes(entryHash(back as Entry))) } } as Entry, null);
  assert.deepEqual(again.signKeys.get(w.alice2.base.hex), [w.alice2.signer.id, renewed.signer.id, third_key.id]);
  assert.equal(vaultOk(again, first, third), null);
  // Who put each device in the lock (`by`): alice2 the owner's, in the genesis and again; the vault's keys and what a
  // station seals to a person's devices go to those they added themselves (vault/secrets.ts `#certsOf`).
  assert.equal(again.devices.get(w.alice2.base.hex)!.by, "alice");
  assert.equal(w.state.devices.get(w.bob.base.hex)!.by, "alice", "the genesis's devices the owner's");
});

test("an item is written by a member's device, version after version, under the vault's epoch", () => {
  const w = lock();
  const vault = vaultOf(w, { members: [w.alice, w.bob] });
  const first = itemOf({ by: w.bob });
  assert.equal(itemOk(w.state, vault, null, first), null);
  assert.match(itemOk(w.state, vault, null, itemOf({ by: w.carol }))!, /member's device/);
  assert.match(itemOk(w.state, vault, null, itemOf({ by: w.bob, version: 1 }))!, /first version is 0/);
  assert.match(itemOk(w.state, vault, first, itemOf({ by: w.alice, version: 2 }))!, /version 1 follows 0/);
  assert.match(itemOk(w.state, vault, null, itemOf({ by: w.bob, epoch: 1 }))!, /epoch 0/);
  assert.match(itemOk(w.state, vault, null, { ...first, ct: first.ct.slice(1) })!, /signature/);
  assert.match(itemOk(w.state, vault, null, { ...itemOf({ by: w.bob }), listing: { name: "x", kind: "token", modes: ["telepathy" as never], hosts: [] } })!, /modes/);
  const gone = itemOf({ by: w.alice, version: 1, deleted: true });
  assert.equal(itemOk(w.state, vault, first, gone), null);
  assert.match(itemOk(w.state, vault, gone, itemOf({ by: w.alice, version: 2 }))!, /deleted/);
  assert.equal(signerOf(w.state, w.bob.signer.id)?.sub, "bob");
  assert.equal(signerOf(w.state, ed().id), null);
});

test("an ES256 key signs as an Ed25519 one does", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" });
  const id = `p256:${Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x as string, "base64url"), Buffer.from(jwk.y as string, "base64url")]).toString("base64url")}`;
  const o = { v: 1, ws: WS, request: "r_x", at: 5 };
  const sig = nodeSign("sha256", signedBytes(o, TAG.deny), { key: privateKey, dsaEncoding: "ieee-p1363" }).toString("base64url");
  assert.ok(signedOk({ ...o, sig: { key: id, alg: "ES256", sig } }, TAG.deny));
  assert.equal(signedOk({ ...o, sig: { key: id, alg: "Ed25519", sig } }, TAG.deny), false);
  assert.equal(signedOk({ ...o, at: 6, sig: { key: id, alg: "ES256", sig } }, TAG.deny), false);
});

// ── the routes ──

function station(w: ReturnType<typeof lock> | null) {
  const told: { event: string; data: any; to: string[] }[] = [];
  const viewers = ["alice", "bob", "carol"].map((sub) => viewer(sub));
  const events = { tell: (event: string, data: unknown, _of: string, to: To) => told.push({ event, data, to: viewers.filter((viewer) => isFor(to, { viewer, lang: "en" })).map((v) => v.sub) }) };
  const all = routes({ vaults: new VaultStore(new DatabaseSync(":memory:")), lock: (ws) => (w !== null && ws === WS ? w.state : null), events: events as any });
  /// `device`: the lock device it comes from (by the endpoint an older client connects with), none by default.
  const ask = async (method: string, path: string, sub: string, body?: unknown, device?: string) => {
    const [p, q] = path.split("?");
    const r: Request = { method, path: p!, query: q ? (q.split("&").map((kv) => kv.split("=")) as [string, string][]) : [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer: viewer(sub, device), lang: "en" };
    for (const route of all) {
      const m = method === route.method ? route.pattern.exec(r.path) : null;
      if (m) {
        const a = await route.handle(r, m.slice(1));
        return { status: a.status, body: JSON.parse((a.body as Buffer).toString()) };
      }
    }
    throw new Error(`no route ${method} ${path}`);
  };
  return { ask, told };
}

const viewer = (sub: string, device = "e".repeat(64)): Viewer => ({ sub, email: `${sub}@x`, name: sub, role: "member", workspace: WS, device });

test("routes: no lock pinned, no vault", async () => {
  const s = station(null);
  for (const [m, p] of [["GET", "/vault/vaults"], ["PUT", "/vault/vaults"], ["GET", "/vault/items"], ["PUT", "/vault/items"], ["GET", "/vault/boxes"], ["PUT", "/vault/boxes"]]) {
    const a = await s.ask(m!, p!, "alice", {});
    assert.equal(a.status, 409);
    assert.equal(a.body.code, "vault_needs_lock");
  }
});

test("routes: a member sees the vaults they are in and their items, and is told of them as they change", async () => {
  const w = lock();
  const s = station(w);
  const v0 = vaultOf(w, { members: [w.alice, w.bob] });
  assert.equal((await s.ask("PUT", "/vault/vaults", "alice", v0)).status, 200);
  assert.deepEqual(s.told.pop(), { event: "vault", data: v0, to: ["alice", "bob"] });
  // Another of alice's, hers alone.
  const own = vaultOf(w, { id: `v_${ulid(1)}` });
  assert.equal((await s.ask("PUT", "/vault/vaults", "bob", own)).status, 200, "whoever brings it: the signature is what counts");
  assert.deepEqual((await s.ask("GET", "/vault/vaults", "alice")).body.vaults.map((v: Vault) => v.id).sort(), [VAULT, own.id].sort());
  assert.deepEqual((await s.ask("GET", "/vault/vaults", "bob")).body.vaults.map((v: Vault) => v.id), [VAULT]);
  assert.deepEqual((await s.ask("GET", "/vault/vaults", "carol")).body.vaults, []);
  // Items: bob writes one; carol neither reads nor writes there.
  const i0 = itemOf({ by: w.bob });
  assert.equal((await s.ask("PUT", "/vault/items", "bob", i0)).status, 200);
  assert.deepEqual(s.told.pop(), { event: "vault-item", data: i0, to: ["alice", "bob"] });
  assert.deepEqual((await s.ask("GET", `/vault/items?vault=${VAULT}`, "alice")).body.items, [i0]);
  assert.deepEqual((await s.ask("GET", "/vault/items", "bob")).body.items, [i0]);
  assert.equal((await s.ask("GET", `/vault/items?vault=${VAULT}`, "carol")).body.code, "vault_unknown");
  assert.equal((await s.ask("PUT", "/vault/items", "carol", itemOf({ by: w.carol }))).body.code, "vault_unknown");
  // Bob taken out (a new epoch): he is told it is gone, and sees it no more.
  const v1 = vaultOf(w, { seq: 1, epoch: 1 });
  assert.equal((await s.ask("PUT", "/vault/vaults", "alice", v1)).status, 200);
  // (told with the version taking him out, signed by its owner: what his device checks it by)
  assert.deepEqual(s.told.slice(-2), [{ event: "vault", data: v1, to: ["alice"] }, { event: "vault-gone", data: { id: VAULT, vault: v1 }, to: ["bob"] }]);
  assert.deepEqual((await s.ask("GET", "/vault/vaults", "bob")).body.vaults, []);
  // A device of his away as it happened asks by the version it holds, naming him: given the latest. Carol, shown no
  // version naming her, is given nothing; nor is bob for a version not its owner's.
  const held0 = v0;
  assert.deepEqual((await s.ask("POST", "/vault/vaults/latest", "bob", { held: [held0] })).body.vaults, [v1]);
  assert.deepEqual((await s.ask("POST", "/vault/vaults/latest", "carol", { held: [held0] })).body.vaults, []);
  assert.deepEqual((await s.ask("POST", "/vault/vaults/latest", "bob", { held: [{ ...held0, owner: "bob" }] })).body.vaults, []);
  assert.equal((await s.ask("GET", `/vault/items?vault=${VAULT}`, "bob")).status, 404);
});

test("routes: a version out of order is a conflict, sent the one held; a bad one is refused why", async () => {
  const w = lock();
  const s = station(w);
  const v0 = vaultOf(w, {});
  await s.ask("PUT", "/vault/vaults", "alice", v0);
  const again = await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, {}));
  assert.equal(again.status, 409);
  assert.equal(again.body.code, "vault_conflict");
  assert.deepEqual(again.body.vault, v0);
  const gap = await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, { seq: 2 }));
  assert.equal(gap.body.code, "vault_conflict");
  // Signed by someone else than the owner: refused, and nothing changes.
  const bobs = await s.ask("PUT", "/vault/vaults", "bob", vaultOf(w, { seq: 1, by: w.bob }));
  assert.equal(bobs.status, 400);
  assert.equal(bobs.body.code, "vault_invalid");
  assert.match(bobs.body.error, /owner's devices/);
  assert.deepEqual((await s.ask("GET", "/vault/vaults", "alice")).body.vaults, [v0]);
  await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice }));
  const stale = await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice }));
  assert.equal(stale.body.code, "vault_conflict");
  assert.equal(stale.body.item.version, 0);
  assert.equal((await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice, version: 1 }))).status, 200);
  // Of another workspace.
  assert.equal((await s.ask("PUT", "/vault/vaults", "alice", { ...vaultOf(w, { id: `v_${ulid(2)}` }), ws: "OTHER" })).body.code, "vault_invalid");
});

test("routes: a vault its owner deleted is kept as its last version, sealed to no one, its items gone; it stays deleted", async () => {
  const w = lock();
  const s = station(w);
  await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, {}));
  assert.equal((await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice }))).status, 200);
  // Still sealed to someone: not deleted.
  assert.match((await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, { seq: 1, epoch: 1, deleted: true, certs: [boxOf(w.alice)] }))).body.error, /sealed to no one/);
  // Its keys gone under the same epoch: refused as any device taken out is.
  assert.match((await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, { seq: 1, deleted: true }))).body.error, /new epoch/);
  const gone = vaultOf(w, { seq: 1, epoch: 1, deleted: true });
  assert.equal((await s.ask("PUT", "/vault/vaults", "alice", gone)).status, 200);
  assert.deepEqual((await s.ask("GET", "/vault/vaults", "alice")).body.vaults, [gone], "kept, so a station holding an older one is brought it");
  assert.deepEqual((await s.ask("GET", `/vault/items?vault=${VAULT}`, "alice")).body.items, []);
  assert.equal((await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice, version: 1, epoch: 1 }))).body.code, "vault_unknown");
  assert.match((await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, { seq: 2, epoch: 2 }))).body.error, /stays deleted/);
});

test("a copy from another station: any later version, checked as one written here; never an earlier one", () => {
  const w = lock();
  const v0 = vaultOf(w, {});
  const v3 = vaultOf(w, { seq: 3, members: [w.alice, w.bob] });
  // Where none is held: whatever seq, but still its owner's, signed.
  assert.equal(vaultOk(w.state, null, v3, true), null);
  assert.match(vaultOk(w.state, null, vaultOf(w, { seq: 3, by: w.bob, members: [w.alice, w.bob] }), true)!, /owner's devices/);
  assert.match(vaultOk(w.state, null, { ...v3, name: "Other" }, true)!, /signature/);
  // Over one held: later only, the rules between them kept (bob out takes a new epoch).
  assert.equal(vaultOk(w.state, v0, v3, true), null);
  assert.match(vaultOk(w.state, v3, v0, true)!, /later than seq 3/);
  assert.match(vaultOk(w.state, v3, vaultOf(w, { seq: 5 }), true)!, /new epoch/);
  assert.equal(vaultOk(w.state, v3, vaultOf(w, { seq: 5, epoch: 1 }), true), null);
  // Not a copy: the next one only, as before.
  assert.match(vaultOk(w.state, v0, v3)!, /seq 1 follows 0/);
  // Items: a later version, one written under an earlier epoch too; never after a deletion, never by a non-member.
  const v1 = vaultOf(w, { seq: 1, epoch: 1 });
  const old = itemOf({ by: w.alice, version: 2, epoch: 0 });
  assert.equal(itemOk(w.state, v1, null, old, true), null);
  assert.match(itemOk(w.state, v1, null, old)!, /epoch 1/);
  assert.match(itemOk(w.state, v1, itemOf({ by: w.alice, version: 4 }), old, true)!, /later than version 4/);
  assert.match(itemOk(w.state, v1, itemOf({ by: w.alice, version: 1, deleted: true }), old, true)!, /deleted/);
  assert.match(itemOk(w.state, v1, null, itemOf({ by: w.carol, version: 2 }), true)!, /member's device/);
  assert.match(itemOk(w.state, v1, null, itemOf({ by: w.alice, version: 2, epoch: 2 }), true)!, /epoch 1/);
});

test("routes: a copy brought from another station is kept where later, the one held answered where not", async () => {
  const w = lock();
  const s = station(w);
  const v2 = vaultOf(w, { seq: 2, members: [w.alice, w.bob] });
  // Not a copy, seq 2 on a station holding nothing is a conflict, as before.
  assert.equal((await s.ask("PUT", "/vault/vaults", "alice", v2)).body.code, "vault_conflict");
  // As a copy, brought by any member's device: kept, and told.
  assert.equal((await s.ask("PUT", "/vault/vaults?copy=1", "bob", v2)).status, 200);
  assert.deepEqual(s.told.pop(), { event: "vault", data: v2, to: ["alice", "bob"] });
  // An earlier one: the one held, nothing told.
  const told = s.told.length;
  const back = await s.ask("PUT", "/vault/vaults?copy=1", "alice", vaultOf(w, { seq: 1, members: [w.alice, w.bob] }));
  assert.equal(back.status, 200);
  assert.equal(back.body.vault.seq, 2);
  assert.equal(s.told.length, told);
  // Forged: refused.
  assert.equal((await s.ask("PUT", "/vault/vaults?copy=1", "bob", vaultOf(w, { seq: 3, by: w.bob, members: [w.alice, w.bob] }))).body.code, "vault_invalid");
  // Items: version 3 where none is, then an earlier one answered with it; the next write here follows the copy.
  const i3 = itemOf({ by: w.bob, version: 3 });
  assert.equal((await s.ask("PUT", "/vault/items?copy=1", "alice", i3)).status, 200);
  assert.equal((await s.ask("PUT", "/vault/items?copy=1", "alice", itemOf({ by: w.bob, version: 1 }))).body.item.version, 3);
  assert.equal((await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice, version: 4 }))).status, 200);
  assert.deepEqual((await s.ask("GET", `/vault/items?vault=${VAULT}`, "bob")).body.items.map((i: Item) => i.version), [4]);
  // An item of a vault not held here: none to copy it into.
  assert.equal((await s.ask("PUT", "/vault/items?copy=1", "alice", itemOf({ by: w.alice, vault: `v_${ulid(3)}` }))).body.code, "vault_unknown");
});

test("routes: two versions of one seq written on two stations at once: each brought the other's, both keep the same one", async () => {
  const w = lock();
  const both = async (a: Vault, b: Vault) => {
    const s1 = station(w), s2 = station(w);
    const v0 = vaultOf(w, { members: [w.alice, w.bob] });
    for (const s of [s1, s2]) assert.equal((await s.ask("PUT", "/vault/vaults", "alice", v0)).status, 200);
    assert.equal((await s1.ask("PUT", "/vault/vaults", "alice", a)).status, 200);
    assert.equal((await s2.ask("PUT", "/vault/vaults", "alice", b)).status, 200);
    // (as the devices bring each station what it lacks)
    await s1.ask("PUT", "/vault/vaults?copy=1", "alice", b);
    await s2.ask("PUT", "/vault/vaults?copy=1", "alice", a);
    const held = await Promise.all([s1, s2].map(async (s) => (await s.ask("GET", "/vault/vaults", "alice")).body.vaults[0] as Vault));
    assert.deepEqual(held[0], held[1], "the same one on both");
    return held[0]!;
  };
  // One takes bob out under a new key, the other adds carol under the old: the one under the new key, bob stays out.
  const out = vaultOf(w, { seq: 1, epoch: 1 });
  const added = vaultOf(w, { seq: 1, members: [w.alice, w.bob, w.carol] });
  assert.deepEqual(await both(added, out), out);
  assert.deepEqual(await both(out, added), out);
  // Under one key: the same one, whichever station was given which.
  const x = vaultOf(w, { seq: 1, members: [w.alice, w.bob] }), y = vaultOf(w, { seq: 1, members: [w.alice, w.bob, w.carol] });
  const kept = await both(x, y);
  assert.deepEqual(await both(y, x), kept);
  assert.equal(vaultSupersedes(kept, kept === x ? y : x), true);
  // Deleted on one: deleted on both.
  const gone = vaultOf(w, { seq: 1, epoch: 1, deleted: true });
  assert.equal((await both(gone, x)).deleted, true);
  assert.equal((await both(x, gone)).deleted, true);
});

test("routes: two versions of one item written on two stations at once: both keep the same one", async () => {
  const w = lock();
  const s1 = station(w), s2 = station(w);
  for (const s of [s1, s2]) {
    assert.equal((await s.ask("PUT", "/vault/vaults", "alice", vaultOf(w, { members: [w.alice, w.bob] }))).status, 200);
    assert.equal((await s.ask("PUT", "/vault/items", "alice", itemOf({ by: w.alice }))).status, 200);
  }
  const a = itemOf({ by: w.alice, version: 1 }), b = itemOf({ by: w.bob, version: 1 });
  await s1.ask("PUT", "/vault/items", "alice", a);
  await s2.ask("PUT", "/vault/items", "bob", b);
  await s1.ask("PUT", "/vault/items?copy=1", "alice", b);
  await s2.ask("PUT", "/vault/items?copy=1", "bob", a);
  const held = await Promise.all([s1, s2].map(async (s) => (await s.ask("GET", `/vault/items?vault=${VAULT}`, "alice")).body.items[0] as Item));
  assert.deepEqual(held[0], held[1]);
  assert.deepEqual(held[0], itemSupersedes(a, b) ? a : b);
});

test("routes: box certificates, published by the lock's app devices, the latest of each", async () => {
  const w = lock();
  const s = station(w);
  const bobs = w.bob.base.hex;
  const c1 = certOf(w.bob.signer, w.bob.base.hex, newBoxPair().pub, 1000);
  assert.equal((await s.ask("PUT", "/vault/boxes", "bob", c1, bobs)).status, 200);
  assert.deepEqual(s.told.pop(), { event: "vault-box", data: c1, to: ["alice", "bob", "carol"] });
  // Another device's key, a device not in the lock: refused.
  assert.match((await s.ask("PUT", "/vault/boxes", "bob", certOf(w.bob.signer, w.alice.base.hex, newBoxPair().pub), bobs)).body.error, /own device's key/);
  assert.match((await s.ask("PUT", "/vault/boxes", "bob", certOf(w.bob.signer, ed().hex, newBoxPair().pub), bobs)).body.error, /not an app device/);
  // Brought by anyone but the device itself (alice, or bob from another connection): refused, signed as it is.
  assert.equal((await s.ask("PUT", "/vault/boxes", "alice", certOf(w.bob.signer, w.bob.base.hex, newBoxPair().pub, 1050), w.alice.base.hex)).body.code, "vault_not_device");
  assert.equal((await s.ask("PUT", "/vault/boxes", "bob", certOf(w.bob.signer, w.bob.base.hex, newBoxPair().pub, 1050))).body.code, "vault_not_device");
  // An older one changes nothing; a newer one takes its place.
  await s.ask("PUT", "/vault/boxes", "bob", certOf(w.bob.signer, w.bob.base.hex, newBoxPair().pub, 900), bobs);
  assert.deepEqual((await s.ask("GET", "/vault/boxes", "carol")).body.boxes, [c1]);
  const c2 = certOf(w.bob.signer, w.bob.base.hex, newBoxPair().pub, 1100);
  await s.ask("PUT", "/vault/boxes", "bob", c2, bobs);
  assert.deepEqual((await s.ask("GET", "/vault/boxes", "alice")).body.boxes, [c2]);
});

test("a device an admin put in under someone else's name is not theirs: no box certificate of it is taken, and it signs no vault or item of theirs", async () => {
  const w = lock();
  // alice (the owner) puts a device of her making in under bob's name: bob has his own already.
  const fake = { sub: "bob", signer: ed(), base: ed() };
  const body = { id: fake.base.hex, sub: "bob", kind: "app", label: "bob's?", sign_key: fake.signer.id };
  const e = { v: 1, ws: WS, seq: 1, prev: w.state.head, at: 1100, kind: "device", body } as Omit<Entry, "sig">;
  const state = apply(w.state, { ...e, sig: { key: w.alice.signer.id, alg: "Ed25519" as const, sig: w.alice.signer.sign(lockBytes(entryHash(e as Entry))) } } as Entry, null);
  assert.equal(state.devices.get(fake.base.hex)?.own, false);
  assert.equal(state.devices.get(w.bob.base.hex)?.own, true);
  const theirs = { ...w, state };
  // Its certificate: not one a secret is sealed to, published from that very device or not.
  assert.match(certOk(state, boxOf(fake))!, /put in the lock by someone else/);
  const s = station(theirs);
  assert.equal((await s.ask("PUT", "/vault/boxes", "bob", boxOf(fake), fake.base.hex)).body.code, "vault_invalid");
  // A version of bob's vault it signs (deleting it), an item it writes there: neither counts as bob's.
  const bobs = vaultOf(theirs, { owner: "bob", members: [w.bob], by: w.bob, id: `v_${ulid(7)}` });
  assert.equal(vaultOk(state, null, bobs), null);
  const { sig: _, ...rest } = bobs;
  assert.match(vaultOk(state, bobs, signed({ ...rest, seq: 1, epoch: 1, keys: [], deleted: true as const }, TAG.vault, fake.signer))!, /owner's devices/);
  assert.match(itemOk(state, bobs, null, itemOf({ by: fake, vault: bobs.id }))!, /member's device/);
  assert.equal(itemOk(state, bobs, null, itemOf({ by: w.bob, vault: bobs.id })), null);
  assert.equal(signerOf(state, fake.signer.id), null);
});

test("routes: the plain library (no security mode) is each person's own, version after version, told to them alone; locked, it only empties", async () => {
  let w: ReturnType<typeof lock> | null = null;
  const told: { event: string; data: any; to: string[] }[] = [];
  const viewers = ["alice", "bob"].map((sub) => viewer(sub));
  const events = { tell: (event: string, data: unknown, _of: string, to: To) => told.push({ event, data, to: viewers.filter((viewer) => isFor(to, { viewer, lang: "en" })).map((v) => v.sub) }) };
  const granted: unknown[] = [];
  const secrets = { pending: () => [], uses: () => [], grantPlain: (...a: unknown[]) => (granted.push(a), null), denyPlain: () => null };
  const all = requestRoutes({ secrets: secrets as never, plain: new PlainStore(new DatabaseSync(":memory:")), lock: (ws) => (w !== null && ws === WS ? w.state : null), events: events as any });
  const ask = async (method: string, path: string, sub: string, body?: unknown) => {
    const [p, q] = path.split("?");
    const r: Request = { method, path: p!, query: q ? (q.split("&").map((kv) => kv.split("=")) as [string, string][]) : [], headers: {}, body: Buffer.from(body === undefined ? "" : JSON.stringify(body)), viewer: viewer(sub), lang: "en" };
    for (const route of all) {
      const m = method === route.method ? route.pattern.exec(r.path) : null;
      if (m) {
        const a = await route.handle(r, m.slice(1));
        return { status: a.status, body: JSON.parse((a.body as Buffer).toString()) };
      }
    }
    throw new Error(`no route ${method} ${path}`);
  };
  const id = "i_01JAPLA1N000000000000000GH";
  const item = { id, version: 0, kind: "token", name: "GitHub", fields: { value: "ghp_x" }, notes: "", listing: { name: "GitHub", kind: "token", modes: ["proxy"], hosts: ["api.github.com"], env: "GH_TOKEN" }, at: 5 };
  const put = await ask("PUT", "/vault/plain", "alice", item);
  assert.equal(put.status, 200, JSON.stringify(put.body));
  assert.equal(put.body.item.fields, undefined, "its value is not said back");
  assert.deepEqual(told.map((t) => [t.event, t.data.id, t.data.fields, t.to]), [["vault-plain", id, undefined, ["alice"]]]);
  assert.deepEqual((await ask("GET", "/vault/plain", "alice")).body.items.map((i: any) => [i.name, i.owner, i.fields]), [["GitHub", "alice@x", undefined]]);
  assert.deepEqual((await ask("GET", "/vault/plain", "bob")).body.items, [], "bob's library has none of alice's");
  assert.equal((await ask("GET", `/vault/plain/item?id=${id}`, "alice")).body.item.fields.value, "ghp_x");
  assert.equal((await ask("GET", `/vault/plain/item?id=${id}`, "bob")).status, 404);
  // bob cannot write over it; a version out of order is a conflict; a bad one says why.
  assert.equal((await ask("PUT", "/vault/plain", "bob", { ...item, version: 1 })).status, 404);
  assert.equal((await ask("PUT", "/vault/plain", "alice", { ...item, version: 3 })).body.code, "vault_conflict");
  assert.match((await ask("PUT", "/vault/plain", "alice", { ...item, version: 1, fields: { password: "x" } })).body.error, /fields are value/);
  assert.match((await ask("PUT", "/vault/plain", "alice", { ...item, version: 1, listing: { ...item.listing, hosts: [] } })).body.error, /names its hosts/);
  assert.equal((await ask("PUT", "/vault/plain", "alice", { ...item, version: 1, name: "GitHub 2" })).status, 200);
  // Decided by its owner (the secrets' check), not signed.
  assert.equal((await ask("POST", "/vault/plain/grants", "alice", { request: "r_1", scope: "once" })).status, 200);
  assert.equal(granted.length, 1);
  // Security mode on: nothing new, only deleted (moved into the vault), and then nothing of it kept.
  w = lock();
  assert.equal((await ask("PUT", "/vault/plain", "alice", { ...item, version: 2 })).body.code, "vault_locked");
  assert.equal((await ask("GET", "/vault/plain", "alice")).body.locked, true);
  assert.equal((await ask("PUT", "/vault/plain", "alice", { ...item, version: 2, deleted: true })).status, 200);
  const gone = (await ask("GET", "/vault/plain", "alice")).body.items[0];
  assert.deepEqual([gone.deleted, gone.name, gone.listing], [true, "", undefined]);
  assert.equal((await ask("GET", `/vault/plain/item?id=${id}`, "alice")).status, 404);
});

test("on a lock moved to its people's logs the vault goes by them: their app devices; one taken off its person's log is none", () => {
  const mw = movedWorld(WS);
  handover(mw);
  const phone = { key: ed(), signer: ed(), base: ed() };
  mw.alice.add("device", { key: phone.key.id, id: phone.base.hex, label: "phone", sign_key: phone.signer.id });
  const c = movedStation(mw);
  for (const l of [mw.alice, mw.bob, mw.carol]) bring(c, l, true, WS);
  const person = (sub: string, d: { signer: unknown; base: unknown }) => ({ sub, ...d }) as unknown as Person;
  const w = { alice: person("alice", mw.alice.app), state: c.locked()!.state! } as unknown as ReturnType<typeof lock>;
  const bob = person("bob", mw.bob.app), ph = person("alice", phone);
  assert.equal(vaultOk(w.state, null, vaultOf(w, { members: [w.alice, bob] })), null, "members and devices the people's logs say");
  const both = (st: typeof w.state) => vaultOk(st, null, vaultOf(w, { members: [w.alice], certs: [boxOf(w.alice), boxOf(ph)] }));
  assert.equal(both(w.state), null, "alice's phone, on her own log");
  mw.alice.add("device.remove", { key: phone.key.id });
  bring(c, mw.alice, false, WS);
  assert.match(both(c.locked()!.state!)!, /not an app device in the lock/);
});

