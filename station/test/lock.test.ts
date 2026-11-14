// The workspace lock (src/cloud/lock.ts): who may sign what, passkeys, which device a
// connection is; and, once a station pins it, what the control plane can no longer do — swap the grant key, add a
// station to the roster, move the station — while an unlocked station goes on as before. Keys are made per run;
// nothing depends on time or on how fast the machine is.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign, type KeyObject } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type Entry, admit, apply, canonical, devicesFor, endpointBytes, entryHash, fold, genesis, LockRefusal, memberWithEmail, membersWithEmail, shortCode, signedBytes } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { verifyMember } from "../src/mesh/credential.ts";
import { inLock, inLockBringing, lockRoute, personChainsOf, stillIn } from "../src/mesh/serve.ts";
import { GrantKey } from "./fake-control-plane.ts";

const WS = "01HZZZZZZZZZZZZZZZZZZZZZZZ";
const hexOf = (k: KeyObject) => Buffer.from(k.export({ format: "jwk" }).x as string, "base64url").toString("hex");

/// An Ed25519 key: an app's signing key (`ed25519:<hex>`) or a device's base key (its hex id).
function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = hexOf(publicKey);
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}

/// A P-256 key, as a passkey's or a hardware-kept app key's: `p256:<uncompressed point>`.
function p256() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = publicKey.export({ format: "jwk" });
  const point = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x as string, "base64url"), Buffer.from(jwk.y as string, "base64url")]);
  return { id: `p256:${point.toString("base64url")}`, privateKey };
}

type Key = ReturnType<typeof ed>;
const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(entryHash(e as Entry))) } });
const after = (head: { seq: number; head: string }, kind: string, body: unknown, at = 1000): Omit<Entry, "sig"> => ({ v: 1, ws: WS, seq: head.seq + 1, prev: head.head, at, kind, body });

/// A workspace (`ws`, WS by default): owner alice (an app device that signs), admin bob, member carol, two stations.
function workspace(ws = WS) {
  const alice = { sub: "alice", signer: ed(), base: ed() };
  const bob = { sub: "bob", signer: ed(), base: ed() };
  const carol = { sub: "carol", signer: ed(), base: ed() };
  const grant = new GrantKey("k1");
  const stations = [ed(), ed()];
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [grant.jwk] },
    members: [{ sub: "alice", email: "a@x", role: "owner" }, { sub: "bob", email: "b@x", role: "admin" }, { sub: "carol", email: "c@x", role: "member" }],
    devices: [alice, bob, carol].map((p) => ({ id: p.base.hex, sub: p.sub, kind: "app", label: p.sub, sign_key: p.signer.id })),
    passkeys: [], stations: stations.map((s, i) => ({ key: s.hex, name: `s${i}` })), gateways: [],
  };
  const first = signed({ v: 1, ws, seq: 0, prev: null, at: 1000, kind: "genesis", body }, alice.signer);
  return { alice, bob, carol, grant, stations, first, state: genesis(first) };
}

test("the hash is of the canonical entry, the same in the cloud and the core (their tests hold the same values)", () => {
  const e = { v: 1, ws: WS, seq: 3, prev: "ab".repeat(32), at: 1700000000, kind: "device", body: { sub: "s", id: "cd".repeat(32), kind: "web", label: "Chrome · 名字", exp: 1702592000 } } as const;
  assert.equal(canonical(e.body), '{"exp":1702592000,"id":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","kind":"web","label":"Chrome · 名字","sub":"s"}');
  assert.equal(entryHash(e as unknown as Entry), VECTOR_HASH);
  assert.equal(shortCode("cd".repeat(32)), VECTOR_CODE);
  assert.throws(() => canonical({ x: 1.5 }), /integers/);
});

test("a genesis is its owner's, signed by the owner's own device in it", () => {
  const w = workspace();
  assert.equal(w.state.seq, 0);
  assert.equal(w.state.members.get("bob")?.role, "admin");
  // Signed by an admin, not the owner.
  assert.throws(() => genesis(signed({ ...w.first, sig: undefined } as any, w.bob.signer)), /owner/);
  // Changed after signing.
  assert.throws(() => genesis({ ...w.first, body: { ...w.first.body, members: [...w.first.body.members, { sub: "eve", email: "e@x", role: "owner" }] } }), /signed/);
});

test("person and device lookups follow each lock snapshot", () => {
  const w = workspace();
  assert.equal(memberWithEmail(w.state, "b@x")?.sub, "bob");
  assert.deepEqual(devicesFor(w.state, "bob"), [w.bob.base.hex]);
  const changed = apply(w.state, signed(after(w.state, "member", { sub: "bob", email: "New@x", role: "admin" }), w.alice.signer), 2000);
  assert.equal(memberWithEmail(changed, "b@x"), null);
  assert.equal(memberWithEmail(changed, "new@x")?.sub, "bob");
  assert.equal(memberWithEmail(w.state, "b@x")?.sub, "bob", "the earlier snapshot stays as it was");
  const removed = apply(changed, signed(after(changed, "member.remove", { sub: "bob" }), w.alice.signer), 2000);
  assert.equal(memberWithEmail(removed, "new@x"), null);
  assert.deepEqual(devicesFor(removed, "bob"), []);
  assert.deepEqual(devicesFor(changed, "bob"), [w.bob.base.hex]);
  const sameEmail = apply(changed, signed(after(changed, "member", { sub: "carol", email: "NEW@x", role: "member" }), w.alice.signer), 2000);
  assert.deepEqual(membersWithEmail(sameEmail, "new@x").map((m) => m.sub), ["bob", "carol"]);
  assert.equal(memberWithEmail(sameEmail, "new@x")?.sub, "bob");
  assert.deepEqual(membersWithEmail(changed, "new@x").map((m) => m.sub), ["bob"]);
});

test("who may sign what: admins manage, members add only their own devices, owners alone touch owners", () => {
  const w = workspace();
  let s = w.state;
  const step = (kind: string, body: unknown, by: Key) => apply(s, signed(after(s, kind, body), by), 2000);
  // A member adds a device of their own, not someone else's, and no member.
  const carolPhone = ed();
  s = step("device", { id: carolPhone.hex, sub: "carol", kind: "app", label: "phone" }, w.carol.signer);
  assert.ok(s.devices.has(carolPhone.hex));
  assert.throws(() => step("device", { id: ed().hex, sub: "bob", kind: "app", label: "x" }, w.carol.signer), /own devices/);
  assert.throws(() => step("member", { sub: "eve", email: "e@x", role: "member" }, w.carol.signer), /owners and admins/);
  // An admin adds a member, not an owner; the owner does.
  s = step("member", { sub: "dave", email: "d@x", role: "member" }, w.bob.signer);
  assert.throws(() => step("member", { sub: "dave", email: "d@x", role: "owner" }, w.bob.signer), /owners/);
  s = step("member", { sub: "bob", email: "b@x", role: "owner" }, w.alice.signer);
  // The last owner stays.
  s = step("member.remove", { sub: "bob" }, w.alice.signer);
  assert.throws(() => step("member.remove", { sub: "alice" }, w.alice.signer), /keeps an owner/);
  // bob is gone, and so are his devices: his key signs nothing now.
  assert.equal(s.devices.has(w.bob.base.hex), false);
  assert.throws(() => step("station", { key: ed().hex, name: "x" }, w.bob.signer), /not signed by a device/);
  // A web page's device: no signing key, at most 30 days.
  assert.throws(() => step("device", { id: ed().hex, sub: "carol", kind: "web", label: "Chrome", sign_key: ed().id, exp: 2000 + 86400 }, w.alice.signer), /only an app/);
  assert.throws(() => step("device", { id: ed().hex, sub: "carol", kind: "web", label: "Chrome", exp: 2000 + 40 * 86400 }, w.alice.signer), /30 days/);
  s = step("device", { id: ed().hex, sub: "carol", kind: "web", label: "Chrome", exp: 2000 + 30 * 86400 }, w.alice.signer);
  // Only owners change the control plane's keys or turn the lock off.
  assert.throws(() => apply(s, signed(after(s, "disable", {}), w.carol.signer), 2000), /owners/);
  const off = apply(s, signed(after(s, "disable", {}), w.alice.signer), 2000);
  assert.equal(off.disabled, true);
  assert.throws(() => apply(off, signed(after(off, "member", { sub: "x", email: "x", role: "member" }), w.alice.signer), 2000), /turned off/);
});

test("a person's own devices: an admin puts in only their first; one put in under someone else's name signs nothing", () => {
  const w = workspace();
  let s = w.state;
  const step = (kind: string, body: unknown, by: Key) => (s = apply(s, signed(after(s, kind, body), by), 2000));
  // The genesis's devices are each person's own.
  assert.ok([w.alice, w.bob, w.carol].every((p) => s.devices.get(p.base.hex)?.own));
  // bob (an admin) puts a device of his making in under alice's name, the owner: it is in the lock, not hers.
  const fake = { signer: ed(), base: ed() };
  step("device", { id: fake.base.hex, sub: "alice", kind: "app", label: "alice?", sign_key: fake.signer.id }, w.bob.signer);
  assert.equal(s.devices.get(fake.base.hex)?.own, false);
  // What it signs keeps the chain going and changes nothing: no owner made, the lock not turned off, no device put in.
  const head = s.head;
  step("member", { sub: "bob", email: "b@x", role: "owner" }, fake.signer);
  assert.equal(s.members.get("bob")?.role, "admin");
  assert.notEqual(s.head, head);
  step("disable", {}, fake.signer);
  assert.equal(s.disabled, false);
  const more = ed();
  step("device", { id: more.hex, sub: "alice", kind: "app", label: "more", sign_key: ed().id }, fake.signer);
  assert.equal(s.devices.has(more.hex), false);
  // One taken off its own person's signing key by an admin (same id, his key): no longer theirs.
  const swap = ed();
  step("device", { id: w.carol.base.hex, sub: "carol", kind: "app", label: "carol", sign_key: swap.id }, w.bob.signer);
  assert.equal(s.devices.get(w.carol.base.hex)?.own, false);
  // A passkey an admin puts in under alice's name: not hers either.
  step("passkey", { id: "cred-x", sub: "alice", key: p256().id, label: "x" }, w.bob.signer);
  assert.equal([...s.passkeys.values()].find((p) => p.id === "cred-x")?.own, false);
  // A new member: their first device is put in by an admin (face to face), and is theirs; the next one only by them.
  step("member", { sub: "dave", email: "d@x", role: "member" }, w.bob.signer);
  const dave = { signer: ed(), base: ed() };
  step("device", { id: dave.base.hex, sub: "dave", kind: "app", label: "dave", sign_key: dave.signer.id }, w.bob.signer);
  assert.equal(s.devices.get(dave.base.hex)?.own, true);
  const daveAdmins = ed();
  step("device", { id: daveAdmins.hex, sub: "dave", kind: "app", label: "dave 2?", sign_key: ed().id }, w.bob.signer);
  assert.equal(s.devices.get(daveAdmins.hex)?.own, false);
  const davePhone = ed();
  step("device", { id: davePhone.hex, sub: "dave", kind: "app", label: "dave 2", sign_key: ed().id }, dave.signer);
  assert.equal(s.devices.get(davePhone.hex)?.own, true);
  // dave's web page, renewed by an admin under the same (no) key: stays his.
  const page = ed();
  step("device", { id: page.hex, sub: "dave", kind: "web", label: "Chrome", exp: 2000 + 86400 }, dave.signer);
  step("device", { id: page.hex, sub: "dave", kind: "web", label: "Chrome", exp: 2000 + 2 * 86400 }, w.bob.signer);
  assert.equal(s.devices.get(page.hex)?.own, true);
  // Every device of dave's gone (lost): an admin's new one is still not his ...
  for (const id of [dave.base.hex, daveAdmins.hex, davePhone.hex, page.hex]) step("device.remove", { id }, w.bob.signer);
  const again = ed();
  step("device", { id: again.hex, sub: "dave", kind: "app", label: "dave 3?", sign_key: ed().id }, w.bob.signer);
  assert.equal(s.devices.get(again.hex)?.own, false);
  // ... until dave is taken out and made a member again, in the open: then his first is put in as anyone's first.
  step("member.remove", { sub: "dave" }, w.bob.signer);
  step("member", { sub: "dave", email: "d@x", role: "member" }, w.bob.signer);
  step("device", { id: again.hex, sub: "dave", kind: "app", label: "dave 3", sign_key: ed().id }, w.bob.signer);
  assert.equal(s.devices.get(again.hex)?.own, true);
});

test("an entry follows the head it names, signed as it is", () => {
  const w = workspace();
  const e = signed(after(w.state, "station", { key: ed().hex, name: "new" }), w.alice.signer);
  assert.throws(() => apply(w.state, { ...e, prev: "00".repeat(32) }, 2000), /does not follow/);
  assert.throws(() => apply(w.state, { ...e, seq: 5 }, 2000), /does not follow/);
  assert.throws(() => apply(w.state, { ...e, body: { key: ed().hex, name: "other" } }, 2000), /signature invalid/);
  assert.throws(() => apply(w.state, { ...e, ws: "OTHER" }, 2000), /another lock/);
  const s = apply(w.state, e, 2000);
  assert.deepEqual(fold([w.first, e], null).head, s.head);
});

test("a passkey signs as WebAuthn does: on the lock's origin, for its relying party, with the user present", () => {
  const w = workspace();
  const pk = p256();
  const added = signed(after(w.state, "passkey", { id: "cred-1", sub: "bob", key: pk.id, label: "bob's" }), w.bob.signer);
  let s = apply(w.state, added, 2000);
  const e = after(s, "station", { key: ed().hex, name: "by passkey" });
  const hash = entryHash(e as Entry);
  const assertion = (o: { origin?: string; challenge?: string; rp?: string; flags?: number }) => {
    const client = Buffer.from(JSON.stringify({ type: "webauthn.get", challenge: o.challenge ?? Buffer.from(hash, "hex").toString("base64url"), origin: o.origin ?? "https://app.still.fail" }));
    const auth = Buffer.concat([createHash("sha256").update(o.rp ?? "app.still.fail").digest(), Buffer.from([o.flags ?? 1]), Buffer.alloc(4)]);
    const sig = nodeSign("sha256", Buffer.concat([auth, createHash("sha256").update(client).digest()]), { key: pk.privateKey, dsaEncoding: "der" });
    return { ...e, sig: { key: pk.id, alg: "webauthn" as const, authenticator_data: auth.toString("base64url"), client_data: client.toString("base64url"), sig: sig.toString("base64url") } } as Entry;
  };
  s = apply(s, assertion({}), 2000);
  assert.equal(s.stations.get((e.body as any).key)?.name, "by passkey");
  for (const [why, o] of [["another page", { origin: "https://evil.example" }], ["another entry", { challenge: "AAAA" }], ["another site", { rp: "evil.example" }], ["nobody present", { flags: 0 }]] as const) {
    assert.throws(() => apply(apply(w.state, added, 2000), assertion(o), 2000), /signature invalid/, why);
  }
});

test("a connection is the device whose base key vouches for its endpoint, or an older client's endpoint", () => {
  const w = workspace();
  const endpoint = ed().hex;
  const proof = w.carol.base.sign(endpointBytes(WS, endpoint));
  assert.deepEqual(admit(w.state, { sub: "carol", endpoint, base: w.carol.base.hex, proof }, 2000).role, "member");
  // The proof is for one endpoint, in one workspace, by that key.
  assert.throws(() => admit(w.state, { sub: "carol", endpoint: ed().hex, base: w.carol.base.hex, proof }, 2000), LockRefusal);
  assert.throws(() => admit(w.state, { sub: "carol", endpoint, base: w.bob.base.hex, proof }, 2000), LockRefusal);
  // Someone else's device.
  const bobs = w.bob.base.sign(endpointBytes(WS, endpoint));
  assert.throws(() => admit(w.state, { sub: "carol", endpoint, base: w.bob.base.hex, proof: bobs }, 2000), /someone else's/);
  // An older client, by the endpoint the lock lists; a web device that ran out.
  const old = ed().hex;
  let s = apply(w.state, signed(after(w.state, "device", { id: old, sub: "carol", kind: "app", label: "old", endpoints: [old, endpoint] }), w.alice.signer), 2000);
  assert.equal(admit(s, { sub: "carol", endpoint }, 2000).device.id, old);
  const web = ed();
  s = apply(s, signed(after(s, "device", { id: web.hex, sub: "carol", kind: "web", label: "Chrome", exp: 3000 }), w.alice.signer), 2000);
  const webProof = web.sign(endpointBytes(WS, endpoint + ""));
  assert.equal(admit(s, { sub: "carol", endpoint, base: web.hex, proof: webProof }, 2999).device.id, web.hex);
  assert.throws(() => admit(s, { sub: "carol", endpoint, base: web.hex, proof: webProof }, 3000), /ran out/);
});

/// A station's data with cloud.json, in workspace WS at `origin`, its roster `peers`.
function stationData(w: ReturnType<typeof workspace>, me: string) {
  const data = mkdtempSync(join(tmpdir(), "lock-"));
  writeState(data, {
    origin: "https://app.still.fail", station: me, workspace: WS, workspace_name: "Team", name: "s0", relay_url: "", relay_urls: [],
    grant_keys: { keys: [w.grant.jwk] }, peers: w.stations.map((s) => ({ id: s.hex, name: "s" })), revocations: [],
  });
  return new Cloud(data);
}

/// What a compromised control plane pushes: the station moved, its own key, its own station in the roster, a gateway.
function hostile(w: ReturnType<typeof workspace>, evil: GrantKey, intruder: string) {
  return JSON.stringify({
    type: "state", workspace: "01HEVILEVILEVILEVILEVILEVI", workspace_name: "Team", name: "s0", origin: "https://evil.example", relay_urls: [],
    peers: [...w.stations.map((s) => ({ id: s.hex, name: "s" })), { id: intruder, name: "intruder" }], grant_keys: { keys: [evil.jwk] }, revocations: [], gateway_keys: [intruder],
  });
}

const credential = (key: GrantKey, ws: string, device: string, role: string, sub = "carol") =>
  key.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", sub, email: `${sub}@x`, name: sub, ws, role, device, sid: "sid", iat: 1000, exp: 4102444800 });

test("a locked station: the control plane's key swap, roster stuffing and move are refused", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  cloud.takeLock([w.first]);
  const evil = new GrantKey("k2");
  const intruder = ed().hex;
  applyState(cloud, hostile(w, evil, intruder));
  const s = cloud.state!;
  assert.equal(s.workspace, WS, "not moved");
  assert.equal(s.origin, "https://app.still.fail", "nor sent elsewhere");
  assert.deepEqual(s.peers.map((p) => p.id), w.stations.map((x) => x.hex), "the intruder is no peer");
  assert.deepEqual(s.gateway_keys, [], "nor a gateway");
  // A credential the control plane signs with its new key: refused, however it names the device.
  const device = ed();
  const endpoint = device.hex;
  assert.throws(() => verifyMember(credential(evil, WS, endpoint, "owner"), cloud.grantKeys(), s.workspace, endpoint, s.revocations), /unknown credential key|signature invalid/);
  // With the key the lock names but for a device the lock does not: not admitted.
  const admitted = verifyMember(credential(w.grant, WS, endpoint, "owner"), cloud.grantKeys(), s.workspace, endpoint, s.revocations);
  assert.throws(() => inLock(cloud, admitted, "owner", endpoint), LockRefusal);
  // carol's own device: in, but as the member the lock says, though the credential says owner.
  const proof = w.carol.base.sign(endpointBytes(WS, endpoint));
  const carol = verifyMember(credential(w.grant, WS, endpoint, "owner"), cloud.grantKeys(), s.workspace, endpoint, s.revocations);
  carol.viewer.lockDevice = { base: w.carol.base.hex, proof };
  assert.equal(inLock(cloud, carol, "owner", endpoint).viewer.role, "member");
  // The control plane may still lower a role: viewer it says, viewer it is.
  assert.equal(inLock(cloud, carol, "viewer", endpoint).viewer.role, "viewer");
});

test("an unlocked station goes by the control plane as before", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const evil = new GrantKey("k2");
  const intruder = ed().hex;
  applyState(cloud, hostile(w, evil, intruder));
  const s = cloud.state!;
  assert.equal(s.workspace, "01HEVILEVILEVILEVILEVILEVI");
  assert.equal(s.origin, "https://evil.example");
  assert.ok(s.peers.some((p) => p.id === intruder));
  assert.deepEqual(s.gateway_keys, [intruder]);
  const endpoint = ed().hex;
  const admitted = verifyMember(credential(evil, s.workspace, endpoint, "owner"), cloud.grantKeys(), s.workspace, endpoint, s.revocations);
  assert.equal(inLock(cloud, admitted, "owner", endpoint).viewer.role, "owner");
});

test("the lock is pinned by its owner's own device, grows entry by entry, and is taken away only on the machine", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const viewer = (who: { sub: string; base: Key }, role: string) => {
    const endpoint = ed().hex;
    return { sub: who.sub, email: "", name: "", role, workspace: WS, device: endpoint, lockDevice: { base: who.base.hex, proof: who.base.sign(endpointBytes(WS, endpoint)) } };
  };
  const post = (entries: Entry[], v: ReturnType<typeof viewer>) => lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries })), v);
  // Not the owner (by the control plane's word, all an unlocked station has), or not on a device the genesis names.
  assert.equal(post([w.first], viewer(w.bob, "admin"))[0], 403);
  const stranger = { sub: "alice", base: ed() };
  assert.equal(post([w.first], viewer(stranger, "owner"))[0], 409);
  assert.equal(cloud.locked(), null);
  assert.equal(post([w.first], viewer(w.alice, "owner"))[0], 200);
  assert.equal(cloud.locked()?.state?.seq, 0);
  // Pinned: a genesis of another lock is no entry of this one, whoever brings it.
  const other = workspace();
  assert.equal(post([other.first], viewer(w.alice, "owner"))[0], 409);
  // An entry carol may sign, brought by anyone; the same again changes nothing.
  const next = signed(after(cloud.locked()!.state!, "device", { id: ed().hex, sub: "carol", kind: "app", label: "laptop" }), w.carol.signer);
  assert.deepEqual(post([w.first, next], viewer(w.carol, "member")), [200, { taken: 1, head: { seq: 1, hash: entryHash(next), genesis: entryHash(w.first) } }]);
  assert.equal((post([w.first, next], viewer(w.carol, "member"))[1] as any).taken, 0);
  // The machine's own say: kept beside, the control plane trusted again.
  assert.equal(Cloud.resetLock(cloud.data), true);
  cloud.reloadLock();
  assert.equal(cloud.locked(), null);
  // A fresh Cloud over the same data finds no lock either; one over a broken lock.json admits nobody.
  assert.equal(new Cloud(cloud.data).lock, null);
});

test("a lock its owner turned off is not pinned again: the chain up to before the off, brought late by a device, leaves the station as it is", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  cloud.takeLock([w.first]);
  const device = signed(after(cloud.locked()!.state!, "device", { id: ed().hex, sub: "carol", kind: "app", label: "phone" }), w.alice.signer);
  cloud.takeLock([device]);
  const off = signed(after(cloud.locked()!.state!, "disable", {}), w.alice.signer);
  cloud.takeLock([off]);
  assert.equal(cloud.locked(), null, "off");
  // What alice's app brought every station when it approved the phone, come after the off.
  const v = { sub: "alice", email: "", name: "", role: "owner", workspace: WS, device: ed().hex, lockDevice: undefined as any };
  const endpoint = v.device;
  v.lockDevice = { base: w.alice.base.hex, proof: w.alice.base.sign(endpointBytes(WS, endpoint)) };
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first, device] })), v)[0], 409);
  assert.equal(cloud.locked(), null, "still off");
  assert.equal(new Cloud(cloud.data).locked(), null, "and after a restart");
  // A new lock, turned on again: pinned.
  const again = workspace();
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [{ ...again.first }] })), { ...v, lockDevice: { base: again.alice.base.hex, proof: again.alice.base.sign(endpointBytes(WS, endpoint)) } })[0], 200);
  assert.equal(cloud.locked()?.state?.genesis, entryHash(again.first));
});

test("a station is pinned by any of its owner's devices the lock names now, not only one the genesis named", () => {
  // The owner turned the lock on from one device, approved a phone of theirs after, and takes a station in from it.
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const phone = { sub: "alice", signer: ed(), base: ed() };
  const added = signed(after(w.state, "device", { id: phone.base.hex, sub: "alice", kind: "app", label: "phone", sign_key: phone.signer.id }), w.alice.signer);
  const station = signed(after(apply(w.state, added, 2000), "station", { key: ed().hex, name: "new" }), phone.signer);
  const endpoint = ed().hex;
  const from = (who: { base: Key }, role: string) => ({ sub: "alice", email: "", name: "", role, workspace: WS, device: endpoint, lockDevice: { base: who.base.hex, proof: who.base.sign(endpointBytes(WS, endpoint)) } });
  assert.deepEqual(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first, added, station] })), from(phone, "owner"))[0], 200);
  assert.equal(cloud.locked()?.state?.seq, 2);
  // One the lock does not name, or not its owner's, pins nothing.
  const other = stationData(w, w.stations[1]!.hex);
  assert.equal(lockRoute(other, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first, added, station] })), from({ base: ed() }, "owner"))[0], 409);
  const bobs = { sub: "bob", email: "", name: "", role: "admin", workspace: WS, device: endpoint, lockDevice: { base: w.bob.base.hex, proof: w.bob.base.sign(endpointBytes(WS, endpoint)) } };
  assert.equal(lockRoute(other, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first, added, station] })), bobs)[0], 403);
  assert.equal(other.locked(), null);
});

test("the control plane's head: a locked station asks for what it lacks and gives back what the plane lost", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  cloud.takeLock([w.first]);
  const sent: any[] = [];
  const frame = (lock: unknown) => JSON.stringify({ type: "state", workspace: WS, peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock });
  applyState(cloud, frame({ seq: 2, hash: "x" }), (f) => sent.push(f));
  assert.deepEqual(sent.pop(), { type: "lock.get", after: 0 });
  applyState(cloud, frame(null), (f) => sent.push(f));
  assert.deepEqual(sent.pop(), { type: "lock.put", entries: [w.first] });
  // Entries it brings are checked like any: one that does not verify is refused.
  const good = signed(after(cloud.locked()!.state!, "station", { key: ed().hex, name: "x" }), w.alice.signer);
  applyState(cloud, JSON.stringify({ type: "lock", entries: [{ ...good, body: { key: ed().hex, name: "forged" } }] }));
  assert.equal(cloud.locked()?.state?.seq, 0);
  applyState(cloud, JSON.stringify({ type: "lock", entries: [w.first, good] }));
  assert.equal(cloud.locked()?.state?.seq, 1);
});

test("an unlocked station pins no lock the control plane offers, but the one its enrollment named", async () => {
  const { pendingLockPath } = await import("../src/cloud/state.ts");
  const { writeFileSync } = await import("node:fs");
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const sent: any[] = [];
  const frame = JSON.stringify({ type: "state", workspace: WS, peers: [], grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock: { seq: 0, hash: entryHash(w.first) } });
  applyState(cloud, frame, (f) => sent.push(f));
  assert.equal(sent.length, 0, "nothing asked");
  applyState(cloud, JSON.stringify({ type: "lock", entries: [w.first] }));
  assert.equal(cloud.locked(), null, "nothing pinned");
  // Enrolled with another lock's hash: the plane's is not it.
  writeFileSync(pendingLockPath(cloud.data), JSON.stringify({ hash: entryHash(workspace().first) }));
  applyState(cloud, frame, (f) => sent.push(f));
  assert.deepEqual(sent.pop(), { type: "lock.get", after: -1 });
  applyState(cloud, JSON.stringify({ type: "lock", entries: [w.first] }));
  assert.equal(cloud.locked(), null);
  writeFileSync(pendingLockPath(cloud.data), JSON.stringify({ hash: entryHash(w.first) }));
  applyState(cloud, JSON.stringify({ type: "lock", entries: [w.first] }));
  assert.equal(cloud.locked()?.state?.genesis, entryHash(w.first));
});

test("a workspace that turned its lock on after this station joined it, the station not in it then: pinned once the lock names it", async () => {
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const w = workspace();
  const b = workspace(B);
  const me = w.stations[0]!.hex;
  const cloud = stationData(w, me);
  const sent: any[] = [];
  const frame = (lock: unknown) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock: null, workspaces: [{ workspace: B, workspace_name: "B", name: "s0", peers: [{ id: me }], revocations: [], lock, locked: true }] });
  applyState(cloud, frame({ seq: 0, hash: entryHash(b.first), genesis: entryHash(b.first) }), (f) => sent.push(f));
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [WS], "B's members turned away");
  assert.equal(cloud.leftOut(B), "unpinned");
  // Its owner puts this station in B's lock (lock.joinStation, signed on a trusted device): the plane says so, the
  // station asks for it and pins it.
  const named = signed({ ...after(b.state, "station", { key: me, name: "s0" }, 2000), ws: B }, b.alice.signer);
  sent.length = 0;
  applyState(cloud, frame({ seq: 1, hash: entryHash(named), genesis: entryHash(b.first) }), (f) => sent.push(f));
  assert.deepEqual(sent, [{ type: "lock.get", after: -1, workspace: B }]);
  applyState(cloud, JSON.stringify({ type: "lock", workspace: B, entries: [b.first, named] }));
  assert.equal(cloud.locked(B)?.state?.seq, 1);
  assert.equal(cloud.leftOut(B), null);
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [WS, B], "B's members taken, as its lock says");
});

test("a station in a second workspace pins that one's lock there: none of its members until then, then only those it names", async () => {
  const { joinedPendingPath, joinedLockPath } = await import("../src/cloud/state.ts");
  const { mkdirSync, writeFileSync, existsSync } = await import("node:fs");
  const { dirname } = await import("node:path");
  const { verifyMemberOf } = await import("../src/mesh/credential.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const C = "01HCCCCCCCCCCCCCCCCCCCCCCC";
  const w = workspace();
  const b = workspace(B);
  const me = w.stations[0]!.hex;
  const cloud = stationData(w, me);
  const intruder = ed().hex;
  const sent: any[] = [];
  const frame = (joined: unknown[], lock: unknown = null) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock, workspaces: joined });
  const inB = { workspace: B, workspace_name: "B", name: "s0", peers: [{ id: b.stations[0]!.hex }, { id: intruder }], revocations: [], lock: { seq: 0, hash: entryHash(b.first) }, locked: true };
  const ws = () => cloud.memberships().map((m) => m.workspace);
  // In security mode, as the plane says, its lock not pinned here: none of B's members are taken. Its lock is asked
  // for, and not pinned, as it does not name this station.
  applyState(cloud, frame([inB]), (f) => sent.push(f));
  assert.deepEqual(ws(), [WS]);
  assert.equal(cloud.membership(B), null, "a named workspace with an unpinned lock is not admitted");
  assert.deepEqual(sent.splice(0), [{ type: "lock.get", after: -1, workspace: B }]);
  applyState(cloud, JSON.stringify({ type: "lock", workspace: B, entries: [b.first] }));
  assert.equal(cloud.locked(B), null);
  // Joined naming B's lock: asked for it, pinned once the plane brings that one.
  mkdirSync(dirname(joinedPendingPath(cloud.data, B)), { recursive: true });
  writeFileSync(joinedPendingPath(cloud.data, B), JSON.stringify({ hash: entryHash(b.first) }));
  applyState(cloud, frame([inB]), (f) => sent.push(f));
  assert.deepEqual(sent.pop(), { type: "lock.get", after: -1, workspace: B });
  applyState(cloud, JSON.stringify({ type: "lock", workspace: B, entries: [workspace(B).first] }));
  assert.equal(cloud.locked(B), null, "another lock of B's name is not the one it joined with");
  applyState(cloud, JSON.stringify({ type: "lock", workspace: B, entries: [b.first] }));
  assert.equal(cloud.locked(B)?.state?.genesis, entryHash(b.first));
  assert.equal(cloud.locked(), null, "its home is as it was");
  assert.ok(existsSync(joinedLockPath(cloud.data, B)) && !existsSync(joinedPendingPath(cloud.data, B)));
  assert.deepEqual(ws(), [WS, B]);
  assert.deepEqual(cloud.membership(B)!.peers.map((p) => p.id), [b.stations[0]!.hex], "the stations B's lock names only");
  assert.deepEqual(cloud.membership(B), cloud.memberships().find((m) => m.workspace === B), "single and full roster agree after pinning");
  // B's members: with B's lock's keys, on devices it names, as it says.
  const endpoint = ed().hex;
  const keys = (x: string) => cloud.grantKeys(x === WS ? null : x);
  const carol = verifyMemberOf(credential(b.grant, B, endpoint, "owner"), keys, cloud.memberships(), endpoint);
  assert.throws(() => inLock(cloud, carol, "owner", endpoint), LockRefusal);
  carol.viewer.lockDevice = { base: b.carol.base.hex, proof: b.carol.base.sign(endpointBytes(B, endpoint)) };
  assert.equal(inLock(cloud, carol, "owner", endpoint).viewer.role, "member");
  assert.throws(() => verifyMemberOf(credential(w.grant, B, endpoint, "owner"), keys, cloud.memberships(), endpoint), /unknown credential key|signature invalid/);
  // The home's members go by the plane, as before.
  const home = verifyMemberOf(credential(w.grant, WS, endpoint, "owner"), keys, cloud.memberships(), endpoint);
  assert.equal(inLock(cloud, home, "owner", endpoint).viewer.role, "owner");
  // Its home locked: an unlocked workspace it is in is none of its; the locked one stays.
  cloud.takeLock([w.first]);
  applyState(cloud, frame([inB, { workspace: C, workspace_name: "C", name: "s0", peers: [], revocations: [], lock: null }], { seq: 0, hash: entryHash(w.first) }));
  assert.deepEqual(ws(), [WS, B]);
  // Taken out of B: none of B's members taken, its lock kept here (the plane's word alone lets none go).
  applyState(cloud, frame([], { seq: 0, hash: entryHash(w.first) }));
  assert.deepEqual(ws(), [WS]);
  assert.equal(existsSync(joinedLockPath(cloud.data, B)), true);
});

test("a joined workspace the control plane leaves out of one frame and names again, unlocked by its word: the lock pinned there is kept and goes on deciding", async () => {
  const { existsSync } = await import("node:fs");
  const { joinedLockPath } = await import("../src/cloud/state.ts");
  const { verifyMemberOf } = await import("../src/mesh/credential.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const w = workspace();
  const b = workspace(B);
  const me = w.stations[0]!.hex;
  // Its home not locked; B's lock pinned here, naming carol's device and not the outsider's.
  const cloud = stationData(w, me);
  cloud.takeLock([b.first], B);
  // The plane signs with the one key B's lock names.
  const frame = (joined: unknown[]) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [b.grant.jwk] }, revocations: [], lock: null, workspaces: joined });
  const inB = (said: Record<string, unknown>) => ({ workspace: B, workspace_name: "B", name: "s0", peers: [{ id: b.stations[0]!.hex }], revocations: [], ...said });
  const head = { seq: 0, hash: entryHash(b.first), genesis: entryHash(b.first) };
  const endpoint = ed().hex;
  const keys = (x: string) => cloud.grantKeys(x === WS ? null : x);
  const role = (sub: string, base?: Key) => {
    const admitted = verifyMemberOf(credential(b.grant, B, endpoint, "owner", sub), keys, cloud.memberships(), endpoint);
    if (base !== undefined) admitted.viewer.lockDevice = { base: base.hex, proof: base.sign(endpointBytes(B, endpoint)) };
    return inLock(cloud, admitted, "owner", endpoint).viewer.role;
  };
  const outsider = ed();
  applyState(cloud, frame([inB({ lock: head, locked: true })]));
  assert.equal(role("carol", b.carol.base), "member", "carol on her device, as B's lock says");
  assert.throws(() => role("xavier", outsider), LockRefusal, "the outsider refused");
  // Left out of one frame: B not served meanwhile, its lock kept.
  applyState(cloud, frame([]));
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [WS]);
  const dropped = existsSync(joinedLockPath(cloud.data, B));
  // Named again, unlocked by the plane's word: the lock kept goes on deciding.
  applyState(cloud, frame([inB({ lock: null })]));
  assert.throws(() => role("xavier", outsider), LockRefusal, "the outsider still refused");
  assert.equal(cloud.locked(B)?.state?.genesis, entryHash(b.first));
  assert.ok(dropped, "B's lock was kept on disk while B was left out");
  assert.throws(() => role("xavier"), LockRefusal, "with no device of the lock either");
  assert.equal(role("carol", b.carol.base), "member", "carol as before");
  assert.equal(new Cloud(cloud.data).locked(B)?.state?.genesis, entryHash(b.first), "and so after a restart");
});

test("a joined workspace's lock kept here: a join naming another lock sets it aside, one its chain holds leaves it; its owner's `disable` lets it go while the station was out", async () => {
  const { existsSync } = await import("node:fs");
  const { joinedLockPath, joinedPendingPath } = await import("../src/cloud/state.ts");
  const { nameJoinedLock } = await import("../src/cli.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const w = workspace();
  const me = w.stations[0]!.hex;
  const frame = (joined: unknown[]) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock: null, workspaces: joined });
  const inB = (said: Record<string, unknown>) => ({ workspace: B, workspace_name: "B", name: "s0", peers: [], revocations: [], ...said });
  const headOf = (first: Entry, last: Entry) => ({ seq: last.seq, hash: entryHash(last), genesis: entryHash(first) });
  const ws = (cloud: Cloud) => cloud.memberships().map((m) => m.workspace);
  /// A station that pinned `b`'s lock in B, left out of B by the plane since.
  const outOfB = (b: ReturnType<typeof workspace>) => {
    const cloud = stationData(w, me);
    cloud.takeLock([b.first], B);
    applyState(cloud, frame([inB({ lock: headOf(b.first, b.first), locked: true })]));
    applyState(cloud, frame([]));
    return cloud;
  };

  // Joined again naming a hash its chain holds: the lock kept goes on, nothing waits to be pinned.
  const b = workspace(B);
  const same = outOfB(b);
  assert.equal(nameJoinedLock(same.data, B, entryHash(b.first)), "kept");
  assert.equal(existsSync(joinedPendingPath(same.data, B)), false);
  applyState(same, frame([inB({ lock: headOf(b.first, b.first), locked: true })]));
  assert.equal(same.locked(B)?.state?.genesis, entryHash(b.first));
  assert.deepEqual(ws(same), [WS, B]);

  // Joined again over the mesh naming another lock: the lock kept stays, nothing waits to be pinned.
  const anew = workspace(B);
  const asked = outOfB(b);
  assert.equal(nameJoinedLock(asked.data, B, entryHash(anew.first)), "kept another");
  asked.reloadJoined();
  assert.equal(asked.locked(B)?.state?.genesis, entryHash(b.first));
  assert.equal(existsSync(joinedPendingPath(asked.data, B)), false);

  // Joined again on the machine naming another lock (turned on anew in B, which the plane never brought the old one's
  // end of): the lock kept is set aside, B waits for that one, takes nobody of B meanwhile, and pins it once the plane
  // brings it. The running station reads it again as its file changes (reloadJoined).
  const other = outOfB(b);
  assert.equal(nameJoinedLock(other.data, B, entryHash(anew.first), true), "set aside");
  assert.equal(other.locked(B)?.state?.genesis, entryHash(b.first), "as read before");
  other.reloadJoined();
  assert.equal(other.locked(B), null);
  assert.equal(existsSync(joinedLockPath(other.data, B)), false);
  applyState(other, frame([inB({ lock: headOf(anew.first, anew.first), locked: true })]));
  assert.equal(other.leftOut(B), "pending");
  assert.deepEqual(ws(other), [WS]);
  applyState(other, JSON.stringify({ type: "lock", workspace: B, entries: [b.first] }));
  assert.equal(other.locked(B), null, "the lock set aside is not the one joining named");
  applyState(other, JSON.stringify({ type: "lock", workspace: B, entries: [anew.first] }));
  assert.equal(other.locked(B)?.state?.genesis, entryHash(anew.first));
  assert.deepEqual(ws(other), [WS, B]);

  // B's owner turned its lock off while the station was out: named again, it asks the plane for the rest of the lock it
  // kept, whose `disable` lets it go; B's members go by the plane then, as in any workspace not locked.
  const off = signed({ ...after(b.state, "disable", {}, 2000), ws: B }, b.alice.signer);
  const sent: any[] = [];
  const turnedOff = outOfB(b);
  applyState(turnedOff, frame([inB({ lock: headOf(b.first, off) })]), (f) => sent.push(f));
  assert.deepEqual(sent.splice(0), [{ type: "lock.get", after: 0, workspace: B }]);
  assert.equal(turnedOff.locked(B)?.state?.genesis, entryHash(b.first), "kept until its own `disable` comes");
  applyState(turnedOff, JSON.stringify({ type: "lock", workspace: B, entries: [b.first, off] }));
  assert.equal(turnedOff.locked(B), null);
  assert.deepEqual(ws(turnedOff), [WS, B]);

  // Turned off and on anew while it was out: the old lock's `disable` asked for by its genesis, then the new lock, once it
  // names this station, pinned (as for a workspace that turned its lock on after this station joined it).
  const named = signed({ ...after(anew.state, "station", { key: me, name: "s0" }, 2000), ws: B }, anew.alice.signer);
  const onAnew = outOfB(b);
  applyState(onAnew, frame([inB({ lock: headOf(anew.first, named), locked: true })]), (f) => sent.push(f));
  assert.deepEqual(sent.splice(0), [{ type: "lock.get", after: 0, genesis: entryHash(b.first), workspace: B }]);
  applyState(onAnew, JSON.stringify({ type: "lock", workspace: B, entries: [b.first, off] }));
  assert.equal(onAnew.leftOut(B), "unpinned");
  applyState(onAnew, frame([inB({ lock: headOf(anew.first, named), locked: true })]), (f) => sent.push(f));
  assert.deepEqual(sent.splice(0), [{ type: "lock.get", after: -1, workspace: B }]);
  applyState(onAnew, JSON.stringify({ type: "lock", workspace: B, entries: [anew.first, named] }));
  assert.equal(onAnew.locked(B)?.state?.genesis, entryHash(anew.first));
  assert.deepEqual(ws(onAnew), [WS, B]);
});

test("a join asked over the mesh, by whom the control plane calls an admin, never sets aside a lock kept for that workspace; one asked on the machine does", async (t) => {
  const { existsSync, readFileSync } = await import("node:fs");
  const { joinedLockPath, joinedPendingPath } = await import("../src/cloud/state.ts");
  const { enroll, joinWorkspace } = await import("../src/cli.ts");
  const { routes } = await import("../src/api/routes/workspaces.ts");
  const { verifyMemberOf } = await import("../src/mesh/credential.ts");
  const { FakeControlPlane } = await import("./fake-control-plane.ts");
  const fake = new FakeControlPlane({ provider: "stillfail", joins: true });
  const origin = await fake.start();
  t.after(() => fake.close());
  const data = mkdtempSync(join(tmpdir(), "lock-"));
  const said = console.log;
  console.log = () => {};
  try {
    await enroll(data, origin, "tok");
  } finally {
    console.log = said;
  }
  // Its home not locked; in w2, whose lock it pinned.
  const B = "w2";
  const b = workspace(B);
  const cloud = new Cloud(data, false);
  assert.equal(cloud.locked(), null);
  cloud.takeLock([b.first], B);
  const file = readFileSync(joinedLockPath(data, B), "utf8");
  // An admin of its home by the plane's word asks it to join w2 again, naming a chain of the plane's own.
  const [, join_] = routes({ cloud, data });
  const admin = { sub: "u", email: "a@x", name: "A", role: "admin", workspace: cloud.home()!, device: "d", home: true };
  const forged = workspace(B);
  const answer = await join_!.handle({ method: "POST", path: "/workspaces/join", query: [], headers: {}, body: Buffer.from(JSON.stringify({ token: `join-${B}`, lock: entryHash(forged.first) })), viewer: admin, lang: "en" } as any, []);
  assert.equal(answer.status, 409);
  assert.match(JSON.parse(String(answer.body)).error, /keeps another security mode record for it.*stillfail lock reset --workspace w2/);
  assert.ok(cloud.state!.joined!.some((j) => j.workspace === B), "joined all the same");
  assert.equal(readFileSync(joinedLockPath(data, B), "utf8"), file, "w2's lock as it was on disk");
  assert.equal(existsSync(joinedPendingPath(data, B)), false, "and nothing named to pin");
  cloud.reloadJoined();
  assert.equal(cloud.locked(B)?.state?.genesis, entryHash(b.first), "and in memory");
  // The plane's chain brought: not taken.
  applyState(cloud, JSON.stringify({ type: "lock", workspace: B, entries: [forged.first] }));
  assert.equal(cloud.locked(B)?.state?.genesis, entryHash(b.first));
  const endpoint = ed().hex;
  const outsider = ed();
  const admitted = verifyMemberOf(credential(b.grant, B, endpoint, "owner", "xavier"), (x: string) => cloud.grantKeys(x === cloud.home() ? null : x), cloud.memberships(), endpoint);
  admitted.viewer.lockDevice = { base: outsider.hex, proof: outsider.sign(endpointBytes(B, endpoint)) };
  assert.throws(() => inLock(cloud, admitted, "owner", endpoint), LockRefusal, "the outsider still refused");
  // On the machine (`enroll --join --lock`): its person sets it aside, and w2 waits for the lock named.
  await joinWorkspace(data, `join-${B}`, entryHash(forged.first), { atMachine: true });
  cloud.reloadJoined();
  assert.equal(cloud.locked(B), null);
  assert.equal(existsSync(joinedLockPath(data, B)), false);
  assert.equal(cloud.pendingLock(B), entryHash(forged.first));
});

test("`lock reset --workspace`: a joined workspace's lock taken away on the machine alone, the running station following; the home one's as before", async () => {
  const { existsSync, readdirSync } = await import("node:fs");
  const { dirname } = await import("node:path");
  const { joinedLockPath, joinedPendingPath, lockPath } = await import("../src/cloud/state.ts");
  const { lockCommand } = await import("../src/cli.ts");
  const { tr, stationLang } = await import("../src/ops/i18n.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const w = workspace();
  const b = workspace(B);
  const cloud = stationData(w, w.stations[0]!.hex);
  cloud.takeLock([w.first]);
  cloud.takeLock([b.first], B);
  const inB = { workspace: B, workspace_name: "B", name: "s0", peers: [], revocations: [], lock: { seq: 0, hash: entryHash(b.first), genesis: entryHash(b.first) }, locked: true };
  applyState(cloud, JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: [], grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock: { seq: 0, hash: entryHash(w.first) }, workspaces: [inB] }));
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [WS, B]);
  assert.equal(lockCommand(cloud.data, "reset", B), tr(stationLang(), "station.cli.lock.resetWorkspace", { workspace: B }));
  assert.equal(existsSync(joinedLockPath(cloud.data, B)), false);
  assert.equal(existsSync(joinedPendingPath(cloud.data, B)), false);
  assert.ok(readdirSync(dirname(joinedLockPath(cloud.data, B))).some((f) => f.includes(".reset-")), "kept beside");
  cloud.reloadJoined();
  // B in security mode as the plane says, its lock gone: none of its members taken; the home's lock as it was.
  assert.equal(cloud.locked(B), null);
  assert.equal(cloud.leftOut(B), "unpinned");
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [WS]);
  assert.equal(cloud.locked()?.state?.genesis, entryHash(w.first));
  assert.equal(lockCommand(cloud.data, "reset", B), tr(stationLang(), "station.cli.lock.noneWorkspace", { workspace: B }));
  // Naming the home workspace, or none: the home's lock, as before.
  assert.equal(lockCommand(cloud.data, "reset", WS), tr(stationLang(), "station.cli.lock.reset"));
  assert.equal(existsSync(lockPath(cloud.data)), false);
});

/// A station whose home is not locked, in B with B's lock pinned (the outsider refused there), and how B's members fare.
async function homeSwap() {
  const { verifyMemberOf } = await import("../src/mesh/credential.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const w = workspace();
  const b = workspace(B);
  const me = w.stations[0]!.hex;
  const head = { seq: 0, hash: entryHash(b.first), genesis: entryHash(b.first) };
  const inB = { workspace: B, workspace_name: "B", name: "s0", peers: [{ id: b.stations[0]!.hex }], revocations: [], lock: head, locked: true };
  const inW = { workspace: WS, workspace_name: "Team", name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), revocations: [], lock: null };
  // The plane signs with the one key B's lock names.
  const atHome = (joined: unknown[]) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: inW.peers, grant_keys: { keys: [b.grant.jwk] }, revocations: [], lock: null, workspaces: joined });
  const bAtHome = (joined: unknown[]) => JSON.stringify({ type: "state", workspace: B, workspace_name: "B", name: "s0", peers: inB.peers, grant_keys: { keys: [b.grant.jwk] }, revocations: [], lock: null, workspaces: joined });
  const endpoint = ed().hex;
  const role = (cloud: Cloud, sub: string, base?: Key) => {
    const admitted = verifyMemberOf(credential(b.grant, B, endpoint, "owner", sub), (x: string) => cloud.grantKeys(x === cloud.home() ? null : x), cloud.memberships(), endpoint);
    if (base !== undefined) admitted.viewer.lockDevice = { base: base.hex, proof: base.sign(endpointBytes(B, endpoint)) };
    return inLock(cloud, admitted, "owner", endpoint).viewer.role;
  };
  const outsider = ed();
  const pinned = () => {
    const cloud = stationData(w, me);
    cloud.takeLock([b.first], B);
    applyState(cloud, atHome([inB]));
    assert.throws(() => role(cloud, "xavier", outsider), LockRefusal);
    return cloud;
  };
  return { pinned, atHome, bAtHome, inW, role, outsider, b, B };
}

test("its home not locked, the control plane makes a joined workspace with a lock kept here the home one, its old home among those it joined: that lock goes along and goes on deciding", async () => {
  const { pinned, bAtHome, inW, role, outsider, b, B } = await homeSwap();
  // B at the top, its old home among those it joined (which the plane says unlocked: the plane's word all it had).
  const swapped = pinned();
  applyState(swapped, bAtHome([inW]));
  assert.equal(swapped.home(), B);
  assert.throws(() => role(swapped, "xavier", outsider), LockRefusal, "the outsider refused once B is home");
  assert.equal(role(swapped, "carol", b.carol.base), "member");
  assert.equal(swapped.locked()?.state?.genesis, entryHash(b.first));
});

test("its home not locked, the control plane leaves out a joined workspace with a lock kept here, then makes it the home one: that lock goes along and goes on deciding", async () => {
  const { pinned, atHome, bAtHome, role, outsider, b, B } = await homeSwap();
  // Left out of a frame first, then B at the top, its old home gone.
  const dropped = pinned();
  applyState(dropped, atHome([]));
  applyState(dropped, bAtHome([]));
  assert.equal(dropped.home(), B);
  assert.throws(() => role(dropped, "xavier", outsider), LockRefusal, "the outsider refused once B is home");
  assert.equal(role(dropped, "carol", b.carol.base), "member");
  assert.equal(new Cloud(dropped.data).locked()?.state?.genesis, entryHash(b.first), "and so after a restart");
});

const VECTOR_HASH = "27e965570b626031e9640b781bdba3b5bb111ba2307b81bd9af8d14158f8578a";
const VECTOR_CODE = "UJV-HA9";

test("taken out of its home, a workspace it joined takes over: that one's lock goes along, its stations still only those it names", async () => {
  const { existsSync } = await import("node:fs");
  const { joinedLockPath } = await import("../src/cloud/state.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const w = workspace();
  const b = workspace(B);
  const me = w.stations[0]!.hex;
  const intruder = ed().hex;
  const inB = { workspace: B, workspace_name: "B", name: "s0", peers: [{ id: b.stations[0]!.hex }, { id: intruder }], revocations: [], lock: { seq: 0, hash: entryHash(b.first) }, locked: true };
  const atHome = (lock: unknown) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: w.stations.map((s) => ({ id: s.hex })), grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock, workspaces: [inB] });
  // What the plane says once the station is taken out of WS: B at the top.
  const takenOver = JSON.stringify({ type: "state", workspace: B, workspace_name: "B", name: "s0", peers: inB.peers, grant_keys: { keys: [b.grant.jwk] }, revocations: [], lock: inB.lock, workspaces: [] });
  const tops = (cloud: Cloud) => cloud.memberships().map((m) => [m.workspace, m.peers.map((p) => p.id)]);
  // Its home locked, B's lock pinned.
  const locked = stationData(w, me);
  locked.takeLock([w.first]);
  locked.takeLock([b.first], B);
  applyState(locked, atHome({ seq: 0, hash: entryHash(w.first) }));
  const sent: unknown[] = [];
  applyState(locked, takenOver, (f) => sent.push(f));
  assert.deepEqual(tops(locked), [[B, [b.stations[0]!.hex]]], "B at home, its roster as B's lock has it");
  assert.equal(locked.locked()?.state?.genesis, entryHash(b.first));
  assert.deepEqual(locked.grantKeys(), { keys: [b.grant.jwk] });
  assert.equal(existsSync(joinedLockPath(locked.data, B)), false);
  assert.deepEqual(sent, [], "level with the plane's lock of B");
  assert.equal(new Cloud(locked.data).locked()?.state?.genesis, entryHash(b.first), "and so after a restart");
  // Moved on by the plane to a workspace it is not in: refused, as any move of a locked station.
  applyState(locked, hostile(b, new GrantKey("k9"), intruder));
  assert.equal(locked.home(), B);
  // Its home unlocked: B's lock goes along all the same, not forgotten with B's place among those it joined.
  const open = stationData(w, me);
  open.takeLock([b.first], B);
  applyState(open, atHome(null));
  applyState(open, takenOver);
  assert.deepEqual(tops(open), [[B, [b.stations[0]!.hex]]]);
  assert.equal(open.locked()?.state?.genesis, entryHash(b.first));
  // Its home locked and B's lock not pinned here: it stays where its lock keeps it.
  const stuck = stationData(w, me);
  stuck.takeLock([w.first]);
  applyState(stuck, atHome({ seq: 0, hash: entryHash(w.first) }));
  applyState(stuck, takenOver);
  assert.equal(stuck.home(), WS);
  assert.equal(stuck.locked()?.state?.genesis, entryHash(w.first));
});

test("joining a locked workspace: the plane's frame comes before the join's answer, and its lock is asked for once joining names it; till then its members are told why", async () => {
  const { joinedPendingPath } = await import("../src/cloud/state.ts");
  const { mkdirSync, writeFileSync } = await import("node:fs");
  const { dirname } = await import("node:path");
  const { pendingAsks } = await import("../src/cloud/presence.ts");
  const { refusalOf } = await import("../src/mesh/serve.ts");
  const B = "01HBBBBBBBBBBBBBBBBBBBBBBB";
  const C = "01HCCCCCCCCCCCCCCCCCCCCCCC";
  const w = workspace();
  const b = workspace(B);
  const cloud = stationData(w, w.stations[0]!.hex);
  const sent: any[] = [];
  const asked = new Set<string>();
  const inB = { workspace: B, workspace_name: "B", name: "s0", peers: [{ id: b.stations[0]!.hex }], revocations: [], lock: { seq: 0, hash: entryHash(b.first) }, locked: true };
  const frame = (joined: unknown[], lock: unknown = null) => JSON.stringify({ type: "state", workspace: WS, workspace_name: "Team", name: "s0", peers: [], grant_keys: { keys: [w.grant.jwk] }, revocations: [], lock, workspaces: joined });
  // B's member, with a credential as the plane signs them, and someone else's.
  const endpoint = ed().hex;
  const hello = { credential: credential(w.grant, B, endpoint, "member") };
  const forged = { credential: credential(new GrantKey("k9"), B, endpoint, "member") };
  const refused = (h: unknown) => refusalOf(cloud, h, endpoint, new Error("credential is for another workspace"));
  // The plane tells the station it is in B as it takes the join, before the join is answered: which lock to pin is not
  // written yet. B's lock is asked for (pinned only once it names this station, which this one does not).
  applyState(cloud, frame([inB]), (f) => sent.push(f));
  assert.deepEqual(sent.splice(0), [{ type: "lock.get", after: -1, workspace: B }]);
  assert.equal(cloud.leftOut(B), "unpinned");
  assert.deepEqual(pendingAsks(cloud, asked), []);
  assert.deepEqual(refused(hello), { error: refused(hello).error, code: "lock_station", why: "unpinned" });
  // Joining answered, naming B's lock: asked for at once (and once), not at the plane's next frame.
  mkdirSync(dirname(joinedPendingPath(cloud.data, B)), { recursive: true });
  writeFileSync(joinedPendingPath(cloud.data, B), JSON.stringify({ hash: entryHash(b.first) }));
  assert.equal(cloud.leftOut(B), "pending");
  assert.equal(refused(hello).why, "pending");
  assert.deepEqual(refused(forged), { error: "credential is for another workspace" }, "one that does not check out is told nothing of B");
  assert.deepEqual(pendingAsks(cloud, asked), [B]);
  assert.deepEqual(pendingAsks(cloud, asked), []);
  applyState(cloud, JSON.stringify({ type: "lock", workspace: B, entries: [b.first] }));
  assert.equal(cloud.leftOut(B), null);
  assert.deepEqual(cloud.memberships().map((m) => m.workspace), [WS, B]);
  // Its home locked later: an unlocked workspace it is in is left out, and its members told why.
  cloud.takeLock([w.first]);
  applyState(cloud, frame([inB, { workspace: C, workspace_name: "C", name: "s0", peers: [], revocations: [], lock: null }], { seq: 0, hash: entryHash(w.first) }));
  assert.equal(cloud.leftOut(C), "home");
  assert.equal(refusalOf(cloud, { credential: credential(w.grant, C, endpoint, "member") }, endpoint, new Error("x")).why, "home");
  // Nothing of a workspace it is not in, nor of its home.
  assert.equal(cloud.leftOut("01HDDDDDDDDDDDDDDDDDDDDDDD"), null);
  assert.equal(cloud.leftOut(WS), null);
});

test("over the stations' own transport: a station the control plane stuffs in is refused, the lock's stations level each other", async () => {
  const { memoryMesh } = await import("./memory-mesh.ts");
  const { PEER_ALPN, peerCall, servePeer } = await import("../src/mesh/peer.ts");
  const { syncWith } = await import("../src/mesh/lock-sync.ts");
  const { randomBytes } = await import("node:crypto");
  const mesh = memoryMesh();
  const bind = (seed: Buffer) => mesh.bind({ secretKey: seed, alpns: [PEER_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const seeds = [randomBytes(32), randomBytes(32), randomBytes(32)];
  const [target, source, intruder] = await Promise.all(seeds.map(bind));
  // The lock names target and source; the control plane's roster names the intruder too.
  const alice = { signer: ed(), base: ed() };
  const grant = new GrantKey("k1");
  const first = signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "alice", origins: [], rp_id: "", cloud_keys: { keys: [grant.jwk] }, members: [{ sub: "alice", email: "a@x", role: "owner" }],
    devices: [{ id: alice.base.hex, sub: "alice", kind: "app", label: "", sign_key: alice.signer.id }], passkeys: [],
    stations: [target, source].map((s) => ({ key: s!.id(), name: "" })), gateways: [],
  } }, alice.signer);
  const cloudOf = (me: string) => {
    const data = mkdtempSync(join(tmpdir(), "lock-peer-"));
    writeState(data, { origin: "o", station: me, workspace: WS, workspace_name: "", name: "", relay_url: "", relay_urls: [], grant_keys: { keys: [grant.jwk] }, peers: [], revocations: [] });
    const c = new Cloud(data);
    applyState(c, JSON.stringify({ type: "state", workspace: WS, peers: [target, source, intruder].map((s) => ({ id: s!.id() })), grant_keys: { keys: [grant.jwk] }, revocations: [] }));
    return c;
  };
  const [targetCloud, sourceCloud, intruderCloud] = [cloudOf(target!.id()), cloudOf(source!.id()), cloudOf(intruder!.id())];
  targetCloud.takeLock([first]);
  sourceCloud.takeLock([first]);
  const ran: string[] = [];
  const remote: any = { handle: async (_ws: string, peer: string, request: any) => (ran.push(peer), { ran: request.method, for: peer }) };
  void (async () => {
    for (;;) {
      const conn = await target!.accept();
      if (!conn) return;
      // As the station's mesh does (mesh.ts): a connection it does not serve is closed.
      void servePeer(conn, targetCloud, remote).catch(() => conn.close(0, "refused"));
    }
  })();
  const port = target!.sockets()[0]!.split(":").at(-1);
  const at = (id: string) => ({ id, ips: [`127.0.0.1:${port}`] });
  try {
    // The intruder, which its (unlocked) control plane told of the target: refused there.
    const intruderCall = peerCall(intruder!, intruderCloud, at);
    await assert.rejects(intruderCall(target!.id(), WS, { method: "task.get", session: "s", key: "k" }), /connection lost|closed|refused/);
    // The lock's own station is answered.
    const sourceCall = peerCall(source!, sourceCloud, at);
    assert.deepEqual(await sourceCall(target!.id(), WS, { method: "describe" }), { ran: "describe", for: source!.id() });
    assert.deepEqual(ran, [source!.id()], "nothing ran for the intruder");
    // The target is behind: the source brings it level.
    const more = signed(after(sourceCloud.locked()!.state!, "member", { sub: "bob", email: "b@x", role: "member" }), alice.signer);
    sourceCloud.takeLock([more]);
    await syncWith(sourceCloud, sourceCall, target!.id());
    assert.equal(targetCloud.locked()?.state?.seq, 1);
  } finally {
    await Promise.all([target!.close(), source!.close(), intruder!.close()]);
  }
});

test("a hello bringing its person's own lock is let in on it where its member bound it, and goes by the longest chain heard", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const owner = ed().hex;
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first] })), { sub: "alice", email: "", name: "", role: "owner", workspace: WS, device: owner, lockDevice: { base: w.alice.base.hex, proof: w.alice.base.sign(endpointBytes(WS, owner)) } } as any)[0], 200);
  const entry = (chain: Entry[], kind: string, body: unknown, key: Key) => {
    const last = chain[chain.length - 1];
    chain.push(signed({ v: 1, ws: "person:carol", seq: chain.length, prev: last ? entryHash(last) : null, at: 1000, kind, body }, key));
  };
  const first = { key: ed(), base: ed() }, phone = { key: ed(), base: ed() };
  const chain: Entry[] = [];
  entry(chain, "genesis", { sub: "carol", device: { key: first.key.id, id: first.base.hex, label: "first" } }, first.key);
  entry(chain, "device", { key: phone.key.id, id: phone.base.hex, label: "phone" }, first.key);
  const endpoint = ed().hex;
  const admitted = (base: Key) => ({ viewer: { sub: "carol", email: "", name: "", role: "member", workspace: WS, device: endpoint, lockDevice: { base: base.hex, proof: base.sign(endpointBytes(WS, endpoint)) } }, exp: 4102444800 }) as any;
  // Not bound yet: the lock it brings counts for nothing.
  assert.throws(() => inLockBringing(cloud, admitted(phone.base), "member", endpoint, { lock: { person: chain } }), LockRefusal);
  cloud.takeLock([signed(after(cloud.locked()!.state!, "person", { sub: "carol", person: entryHash(chain[0]!) }), w.carol.signer)]);
  // No chain brought, or a device not on it: refused.
  assert.throws(() => inLockBringing(cloud, admitted(phone.base), "member", endpoint, {}), LockRefusal);
  assert.throws(() => inLockBringing(cloud, admitted(ed()), "member", endpoint, { lock: { person: chain } }), LockRefusal);
  // On it: in, with the lower of the two roles.
  assert.equal(inLockBringing(cloud, admitted(phone.base), "admin", endpoint, { lock: { person: chain } }).viewer.role, "member");
  // Taken off, the chain from before brought again: judged by the longer one, once the station has heard it.
  const before = [...chain];
  entry(chain, "device.remove", { key: phone.key.id }, first.key);
  assert.equal(inLockBringing(cloud, admitted(first.base), "member", endpoint, { lock: { person: chain } }).viewer.role, "member");
  assert.throws(() => inLockBringing(cloud, admitted(phone.base), "member", endpoint, { lock: { person: before } }), LockRefusal);
  // The station says what it knows, for a device to ask before it writes such an entry.
  const viewer = admitted(first.base).viewer;
  assert.deepEqual((lockRoute(cloud, "GET", [], Buffer.alloc(0), viewer)[1] as { takes: string[] }).takes, ["person"]);
  // Told a device was taken off before anyone brings the chain, and after a restart it remembers.
  const next = [...chain];
  entry(next, "device", { key: phone.key.id, id: phone.base.hex, label: "phone" }, first.key);
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ person: next })), viewer)[0], 200);
  entry(next, "device.remove", { key: phone.key.id }, first.key);
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ person: next })), viewer)[0], 200);
  const restarted = new Cloud(cloud.data);
  assert.throws(() => inLockBringing(restarted, admitted(phone.base), "member", endpoint, { lock: { person: next.slice(0, 4) } }), LockRefusal);
  // Another's lock is not told here, nor one that was not bound.
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ person: next })), { ...viewer, sub: "alice" } as any)[0], 409);
});

test("bound to a lock of their own, a member's app devices are let in only as they are on it, a web page still by its entry", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const owner = ed().hex;
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first] })), { sub: "alice", email: "", name: "", role: "owner", workspace: WS, device: owner, lockDevice: { base: w.alice.base.hex, proof: w.alice.base.sign(endpointBytes(WS, owner)) } } as any)[0], 200);
  const entry = (chain: Entry[], kind: string, body: unknown, key: Key) => {
    const last = chain[chain.length - 1];
    chain.push(signed({ v: 1, ws: "person:carol", seq: chain.length, prev: last ? entryHash(last) : null, at: 1000, kind, body }, key));
  };
  // carol's device of the workspace's lock is the first of her own; her tablet, also in the workspace's lock, is not on it.
  const own = ed(), tablet = { signer: ed(), base: ed() }, web = ed();
  const now = Math.floor(Date.now() / 1000);
  const chain: Entry[] = [];
  entry(chain, "genesis", { sub: "carol", device: { key: own.id, id: w.carol.base.hex, label: "first" } }, own);
  cloud.takeLock([signed(after(cloud.locked()!.state!, "device", { id: tablet.base.hex, sub: "carol", kind: "app", label: "tablet", sign_key: tablet.signer.id }, now), w.carol.signer)]);
  cloud.takeLock([signed(after(cloud.locked()!.state!, "device", { id: web.hex, sub: "carol", kind: "web", label: "web", exp: now + 86400 }, now), w.carol.signer)]);
  const endpoint = ed().hex;
  const admitted = (base: Key) => ({ viewer: { sub: "carol", email: "", name: "", role: "member", workspace: WS, device: endpoint, lockDevice: { base: base.hex, proof: base.sign(endpointBytes(WS, endpoint)) } }, exp: 4102444800 }) as any;
  // Not bound: each by its entry.
  assert.equal(inLockBringing(cloud, admitted(tablet.base), "member", endpoint, {}).viewer.role, "member");
  cloud.takeLock([signed(after(cloud.locked()!.state!, "person", { sub: "carol", person: entryHash(chain[0]!) }, now), w.carol.signer)]);
  // Bound: the tablet, not on her own lock, is no longer let in on its entry; nor her first, until the lock is heard.
  assert.throws(() => inLockBringing(cloud, admitted(tablet.base), "member", endpoint, { lock: { person: [...chain] } }), LockRefusal);
  assert.throws(() => inLockBringing(cloud, admitted(w.carol.base), "member", endpoint, {}), LockRefusal);
  assert.equal(inLockBringing(cloud, admitted(w.carol.base), "member", endpoint, { lock: { person: [...chain] } }).viewer.role, "member");
  // Heard once: an older client that brings none is let in on what was heard.
  const kept = inLockBringing(cloud, admitted(w.carol.base), "member", endpoint, {});
  assert.equal(kept.viewer.role, "member");
  // A web page holds no key of her own lock: by its entry still.
  assert.equal(inLockBringing(cloud, admitted(web), "member", endpoint, {}).viewer.role, "member");
  // Taken off her own lock (another device of hers on it now): the connection already in is no longer, and the station
  // is told as the chain grows.
  const other = { key: ed(), base: ed() };
  entry(chain, "device", { key: other.key.id, id: other.base.hex, label: "other" }, own);
  entry(chain, "device.remove", { key: own.id }, other.key);
  let told = 0;
  const stop = personChainsOf(cloud).listen(() => told++);
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ person: [...chain] })), kept.viewer)[0], 200);
  stop();
  assert.equal(told, 1);
  assert.throws(() => stillIn(cloud, kept, "member", endpoint), LockRefusal);
  // One let in on her own lock alone stays in as it is on it.
  const otherIn = inLockBringing(cloud, admitted(other.base), "member", endpoint, { lock: { person: [...chain] } });
  assert.equal(stillIn(cloud, otherIn, "member", endpoint).viewer.role, "member");
});

test("a device brings what put it in the lock to a station that has not heard of it yet, taken only as any entry is", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const at = (who: { sub: string; base: Key }, endpoint: string) => ({ sub: who.sub, email: "", name: "", role: "member", workspace: WS, device: endpoint, lockDevice: { base: who.base.hex, proof: who.base.sign(endpointBytes(WS, endpoint)) } });
  const admitted = (v: ReturnType<typeof at>) => ({ viewer: v, exp: 4102444800 }) as any;
  // carol's new phone, approved by alice: the entry is at the cloud, not here.
  const phone = { sub: "carol", base: ed() };
  const endpoint = ed().hex;
  const v = at(phone, endpoint);
  // Unpinned, what a device brings pins nothing.
  const approval = signed(after({ seq: 0, head: entryHash(w.first) }, "device", { id: phone.base.hex, sub: "carol", kind: "app", label: "phone" }), w.alice.signer);
  assert.equal(inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [w.first, approval] } }).viewer.role, "member");
  assert.equal(cloud.locked(), null, "it goes by the control plane, as before, and pins nothing it was brought");
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first] })), { ...at(w.alice, ed().hex), role: "owner" } as any)[0], 200);
  assert.throws(() => inLockBringing(cloud, admitted(v), "member", endpoint, {}), LockRefusal, "nothing brought: refused");
  // Made up, or signed by someone who may not: not taken, refused.
  const forged = signed(after(cloud.locked()!.state!, "device", { id: phone.base.hex, sub: "carol", kind: "app", label: "phone" }), ed());
  assert.throws(() => inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [forged] } }), LockRefusal);
  const forAlice = signed(after(cloud.locked()!.state!, "device", { id: phone.base.hex, sub: "alice", kind: "app", label: "phone" }), w.carol.signer);
  assert.throws(() => inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [forAlice] } }), LockRefusal);
  assert.equal(cloud.locked()?.state?.seq, 0);
  // An approval of another device, or entries out of order: not even checked, nothing taken.
  const someoneElse = signed(after(cloud.locked()!.state!, "device", { id: ed().hex, sub: "carol", kind: "app", label: "tablet" }), w.alice.signer);
  assert.throws(() => inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [someoneElse] } }), LockRefusal);
  assert.throws(() => inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [{ ...approval, seq: 5 }] } }), LockRefusal);
  assert.equal(cloud.locked()?.state?.seq, 0);
  // The approval: taken, and the phone let in on it.
  assert.equal(inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [approval] } }).viewer.role, "member");
  assert.equal(cloud.locked()?.state?.seq, 1);
  // A device it does not name gets nothing from it.
  const other = { sub: "carol", base: ed() };
  const otherEnd = ed().hex;
  assert.throws(() => inLockBringing(cloud, admitted(at(other, otherEnd)), "member", otherEnd, { lock: { entries: [approval] } }), LockRefusal);
});

test("a device brings what made its person a member too: a station takes no device of someone it has not heard of", () => {
  const w = workspace();
  const cloud = stationData(w, w.stations[0]!.hex);
  const at = (who: { sub: string; base: Key }, endpoint: string) => ({ sub: who.sub, email: "", name: "", role: "member", workspace: WS, device: endpoint, lockDevice: { base: who.base.hex, proof: who.base.sign(endpointBytes(WS, endpoint)) } });
  const admitted = (v: ReturnType<typeof at>) => ({ viewer: v, exp: 4102444800 }) as any;
  assert.equal(lockRoute(cloud, "POST", [], Buffer.from(JSON.stringify({ entries: [w.first] })), { ...at(w.alice, ed().hex), role: "owner" } as any)[0], 200);
  // dave, added to the workspace since the lock was turned on: alice approved his first device, here no one has heard.
  const phone = { sub: "dave", base: ed() };
  const endpoint = ed().hex;
  const v = at(phone, endpoint);
  const made = signed(after({ seq: 0, head: entryHash(w.first) }, "member", { sub: "dave", email: "dave@example.com", role: "member" }), w.alice.signer);
  const approval = signed(after({ seq: 1, head: entryHash(made) }, "device", { id: phone.base.hex, sub: "dave", kind: "app", label: "phone" }), w.alice.signer);
  // The approval alone does not go on from what the station has.
  assert.throws(() => inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [approval] } }), LockRefusal);
  assert.equal(cloud.locked()?.state?.seq, 0);
  // With what made him a member: taken, and his phone let in on it, as a member.
  assert.equal(inLockBringing(cloud, admitted(v), "member", endpoint, { lock: { entries: [made, approval] } }).viewer.role, "member");
  assert.equal(cloud.locked()?.state?.seq, 2);
  // His credential calling him more: the lock's the lower.
  assert.equal(inLockBringing(cloud, admitted(v), "admin", endpoint, {}).viewer.role, "member");
});
