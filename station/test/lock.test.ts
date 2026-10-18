// The workspace lock (docs/workspace-lock.md, src/cloud/lock.ts): who may sign what, passkeys, which device a
// connection is; and, once a station pins it, what the control plane can no longer do — swap the grant key, add a
// station to the roster, move the station — while an unlocked station goes on as before. Keys are made per run;
// nothing depends on time or on how fast the machine is.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign, type KeyObject } from "node:crypto";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type Entry, admit, apply, canonical, endpointBytes, entryHash, fold, genesis, LockRefusal, shortCode, signedBytes } from "../src/cloud/lock.ts";
import { applyState } from "../src/cloud/presence.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import { verifyMember } from "../src/mesh/credential.ts";
import { inLock, inLockBringing, lockRoute } from "../src/mesh/serve.ts";
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
  // In security mode, as the plane says, its lock not pinned here: none of B's members are taken, nor its lock asked.
  applyState(cloud, frame([inB]), (f) => sent.push(f));
  assert.deepEqual(ws(), [WS]);
  assert.equal(sent.length, 0);
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
  // Taken out of B: its lock forgotten here.
  applyState(cloud, frame([], { seq: 0, hash: entryHash(w.first) }));
  assert.deepEqual(ws(), [WS]);
  assert.equal(existsSync(joinedLockPath(cloud.data, B)), false);
});

const VECTOR_HASH = "27e965570b626031e9640b781bdba3b5bb111ba2307b81bd9af8d14158f8578a";
const VECTOR_CODE = "UJV-HA9";

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
