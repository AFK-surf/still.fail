// A station keeps every entry of a person's own lock the rules take after a parent it keeps that another keeper took
// (a station, a device saying so: `keep`), and goes by the chain the rules' fork choice gives (cloud/log-keep.ts,
// mesh/person-chains.ts): one vote a device, then a removal, then the tie value; another branch winning later moves it
// there, and a device let in on the one that lost is turned away. What a device brings itself only where it goes on
// from the chain gone by, as before. Kept through a restart; a device told as before where its chain lost; two stations
// that keep different entries come to the same, with a station from before as before. A workspace's statements
// (`ws.*`) are refused as they were.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type Entry, LockRefusal, endpointBytes, entryHash, genesis as lockGenesis, signedBytes } from "../src/cloud/lock.ts";
import { Cloud, writeState } from "../src/cloud/state.ts";
import type { Viewer } from "../src/mesh/credential.ts";
import { Refused } from "../src/mesh/bus.ts";
import { PersonChains } from "../src/mesh/person-chains.ts";
import { answerPerson, personSyncWith } from "../src/mesh/person-sync.ts";
import { inLockBringing, lockPartRoute, lockRoute, personChainsOf, stillIn } from "../src/mesh/serve.ts";

/// What a chain at odds was answered before every branch was kept, and still is.
const AT_ODDS = "this device brought a lock at odds with the one its person has here";

function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof ed>;
const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(entryHash(e as Entry))) } } as Entry);
const tie = (parent: Entry, key: Key) => createHash("sha256").update(`${entryHash(parent)}\0${key.id}`).digest("hex");

/// carol's own lock: her first device `f` names itself in the genesis and puts in `q`; `after` signs one more after an
/// entry of it.
function carols() {
  const dev = () => ({ key: ed(), base: ed() });
  const f = dev(), q = dev();
  const g = signed({ v: 1, ws: "person:carol", seq: 0, prev: null, at: 1000, kind: "genesis", body: { sub: "carol", device: { key: f.key.id, id: f.base.hex, label: "first" } } }, f.key);
  const after = (parent: Entry, kind: string, body: unknown, by: Key) => signed({ v: 1, ws: "person:carol", seq: parent.seq + 1, prev: entryHash(parent), at: 1000, kind, body }, by);
  const added = after(g, "device", { key: q.key.id, id: q.base.hex, label: "q" }, f.key);
  const device = (parent: Entry, d: { key: Key; base: Key }, by: Key) => after(parent, "device", { key: d.key.id, id: d.base.hex, label: d.base.hex.slice(0, 4) }, by);
  return { f, q, g, added, after, device, dev, genesis: entryHash(g) };
}

const viewer = (sub: string, workspace = "w1"): Viewer => ({ sub, email: `${sub}@x`, name: sub, role: "member", workspace, device: "ee".repeat(32) });
const body = (v: unknown) => Buffer.from(JSON.stringify(v));
const fakeCloud = () => ({ data: mkdtempSync(join(tmpdir(), "person-forks-")) }) as unknown as Cloud;
const hashes = (es: unknown[]) => (es as Entry[]).map(entryHash);

test("a person's entry valid after an older parent is kept, and the chain is the fork choice's: a removal first, then the tie value", () => {
  const c = carols();
  const r = c.dev();
  const phone = c.device(c.added, r, c.q.key);
  const removal = c.after(c.added, "device.remove", { key: c.q.key.id }, c.f.key);
  for (const order of [[phone, removal], [removal, phone]]) {
    const chains = new PersonChains(null);
    chains.keep(c.genesis, [c.g, c.added, order[0]!], "w1");
    chains.keep(c.genesis, [c.g, c.added, order[1]!], "w1", true);
    assert.deepEqual(hashes(chains.kept(c.genesis)!), hashes([c.g, c.added, removal]));
    assert.deepEqual(hashes(chains.all(c.genesis)).sort(), hashes([c.g, c.added, removal, phone]).sort());
  }
  // f and q each put a device in after the same entry: the lower tie value goes first.
  const x = c.device(c.added, c.dev(), c.f.key), y = c.device(c.added, c.dev(), c.q.key);
  const first = tie(c.added, c.f.key) < tie(c.added, c.q.key) ? x : y;
  for (const order of [[x, y], [y, x]]) {
    const chains = new PersonChains(null);
    for (const e of order) chains.keep(c.genesis, [c.g, c.added, e], "w1", true);
    assert.deepEqual(hashes(chains.kept(c.genesis)!), hashes([c.g, c.added, first]));
  }
});

test("a winning branch of a person's lock that comes later moves the chain: a device let in on the one that lost is turned away, and that is told", () => {
  // A workspace whose lock binds carol to her own.
  const alice = { signer: ed(), base: ed() }, carolApp = { signer: ed(), base: ed() };
  const ws = "01HPERSONFORKPERSONFORKPER";
  const first = signed({ v: 1, ws, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "alice", origins: [], rp_id: "", cloud_keys: { keys: [] },
    members: [{ sub: "alice", email: "a@x", role: "owner" }, { sub: "carol", email: "c@x", role: "member" }],
    devices: [{ id: alice.base.hex, sub: "alice", kind: "app", label: "a", sign_key: alice.signer.id }, { id: carolApp.base.hex, sub: "carol", kind: "app", label: "c", sign_key: carolApp.signer.id }],
    passkeys: [], stations: [], gateways: [],
  } }, alice.signer);
  const data = mkdtempSync(join(tmpdir(), "person-forks-"));
  writeState(data, { origin: "o", station: ed().hex, workspace: ws, workspace_name: "", name: "", relay_url: "", relay_urls: [], grant_keys: { keys: [] }, peers: [], revocations: [] });
  const cloud = new Cloud(data, false);
  cloud.takeLock([first]);
  const c = carols();
  const s0 = lockGenesis(first);
  cloud.takeLock([signed({ v: 1, ws, seq: 1, prev: s0.head, at: 1000, kind: "person", body: { sub: "carol", person: c.genesis } }, carolApp.signer)]);
  // q puts carol's phone in; the phone is let in on that.
  const r = c.dev();
  const phoneIn = c.device(c.added, r, c.q.key);
  const endpoint = ed().hex;
  const as = (base: Key) => ({ viewer: { sub: "carol", email: "", name: "", role: "member", workspace: ws, device: endpoint, lockDevice: { base: base.hex, proof: base.sign(endpointBytes(ws, endpoint)) } }, exp: 4102444800 }) as any;
  const phone = inLockBringing(cloud, as(r.base), "member", endpoint, { lock: { person: [c.g, c.added, phoneIn] } });
  assert.equal(phone.viewer.role, "member");
  // f took q out after the same entry, told now by f: that goes first, the phone with q's branch is out, and it is told.
  let told = 0;
  const stop = personChainsOf(cloud).listen(() => told++);
  const removal = c.after(c.added, "device.remove", { key: c.q.key.id }, c.f.key);
  const by = as(c.f.base).viewer;
  assert.deepEqual(lockRoute(cloud, "POST", [], body({ person: [c.g, c.added, removal], keep: true }), by), [200, {}]);
  stop();
  assert.equal(told, 1);
  assert.throws(() => stillIn(cloud, phone, "member", endpoint), LockRefusal);
  // The phone's chain brought again: kept aside as it was, answered as a chain at odds was.
  const [status, said] = lockRoute(cloud, "POST", [], body({ person: [c.g, c.added, phoneIn] }), by) as [number, any];
  assert.equal(status, 409);
  assert.equal(said.error, AT_ODDS);
  assert.deepEqual(said.head, { seq: 2, hash: entryHash(removal) });
});

test("a person's lock kept comes back after a restart: the chain gone by under `chains`, as a station from before reads it, the rest beside", () => {
  const path = join(mkdtempSync(join(tmpdir(), "person-forks-")), "person-chains.json");
  const c = carols();
  const phone = c.device(c.added, c.dev(), c.q.key);
  const removal = c.after(c.added, "device.remove", { key: c.q.key.id }, c.f.key);
  const chains = new PersonChains(path);
  chains.keep(c.genesis, [c.g, c.added, phone], "w1");
  chains.keep(c.genesis, [c.g, c.added, removal], "w1", true);
  const raw = JSON.parse(readFileSync(path, "utf8"));
  assert.deepEqual(hashes(raw.chains[c.genesis]), hashes([c.g, c.added, removal]));
  const again = new PersonChains(path);
  assert.deepEqual(hashes(again.kept(c.genesis)!), hashes([c.g, c.added, removal]));
  assert.deepEqual(hashes(again.all(c.genesis)).sort(), hashes([c.g, c.added, removal, phone]).sort());
  assert.deepEqual(again.heardIn("w1").map(([g]) => g), [c.genesis]);
});

test("POST /lock/person: a chain whose last entry is on the chain gone by answered as before; one that lost, or not going on from it, as a chain at odds was, with the head and why", () => {
  const cloud = fakeCloud();
  const c = carols();
  const phone = c.device(c.added, c.dev(), c.q.key);
  const removal = c.after(c.added, "device.remove", { key: c.q.key.id }, c.f.key);
  const post = (chain: Entry[], keep = false) => lockPartRoute(cloud, "person", "POST", body({ chain, ...(keep ? { keep } : {}) }), viewer("carol"));
  assert.deepEqual(post([c.g, c.added, phone]), [200, { genesis: c.genesis, length: 3 }]);
  // Brought by the device itself, it does not go on from the chain gone by: refused as before, nothing kept.
  assert.deepEqual(post([c.g, c.added, removal]), [409, { error: AT_ODDS, head: { seq: 2, hash: entryHash(phone) }, off: [
    { why: "not on the head", hash: entryHash(removal), seq: 2, kept: false },
  ] }]);
  assert.equal(personChainsOf(cloud).all(c.genesis).length, 3);
  // Said to be taken by another keeper: kept, and it wins.
  assert.deepEqual(post([c.g, c.added, removal], true), [200, { genesis: c.genesis, length: 3 }]);
  assert.deepEqual(post([c.g, c.added, phone]), [409, { error: AT_ODDS, head: { seq: 2, hash: entryHash(removal) }, off: [
    { why: "beaten", winner: entryHash(removal), step: "removal", hash: entryHash(phone), seq: 2, kept: true },
  ] }]);
  // An older chain, part of the one gone by: as before.
  assert.deepEqual(post([c.g, c.added]), [200, { genesis: c.genesis, length: 3 }]);
  // A workspace's statement is a kind this station does not take yet: refused as before, nothing kept of it.
  const statement = c.after(removal, "ws.member", { ws: "w1", sub: "dan", lock: "ab".repeat(32), role: "member" }, c.f.key);
  const [status, said] = post([c.g, c.added, removal, statement]) as [number, any];
  assert.equal(status, 409);
  assert.match(said.error, /unknown entry kind ws\.member/);
  assert.equal(personChainsOf(cloud).all(c.genesis).length, 4);
});

test("two stations that keep different entries of a person's lock give each other what the other lacks and go by the same chain; with a station from before, as before", async () => {
  const c = carols();
  const phone = c.device(c.added, c.dev(), c.q.key);
  const removal = c.after(c.added, "device.remove", { key: c.q.key.id }, c.f.key);
  const a = new PersonChains(null), b = new PersonChains(null);
  a.keep(c.genesis, [c.g, c.added, phone], "w1");
  b.keep(c.genesis, [c.g, c.added, removal], "w1");
  const to = (other: PersonChains) => async (_peer: string, ws: string | null, request: any) => answerPerson(other, request, ws!) as any;
  await personSyncWith(a, to(b), "b", "w1");
  for (const x of [a, b]) {
    assert.deepEqual(hashes(x.kept(c.genesis)!), hashes([c.g, c.added, removal]));
    assert.deepEqual(hashes(x.all(c.genesis)).sort(), hashes([c.g, c.added, removal, phone]).sort());
  }
  // A station from before: lock.person.heads, .get {genesis} and .put alone.
  const d = carols();
  const mine = new PersonChains(null), old = new PersonChains(null);
  mine.keep(d.genesis, [d.g, d.added], "w1");
  old.keep(d.genesis, [d.g], "w1");
  const calls: string[] = [];
  const toOld = async (_peer: string, ws: string | null, request: any) => {
    calls.push(request.method);
    if (!["lock.person.heads", "lock.person.get", "lock.person.put"].includes(request.method) || request.hashes !== undefined) throw new Refused("unknown lock method");
    return answerPerson(old, request, ws!) as any;
  };
  await personSyncWith(mine, toOld, "old", "w1");
  assert.equal(old.kept(d.genesis)?.length, 2);
  assert.deepEqual(calls, ["lock.person.kept", "lock.person.heads", "lock.person.put"]);
});

test("a person's entry a station takes while it brings a peer level is brought to that peer too (followPersons goes by what it had as the sync began)", async () => {
  const { followPersons } = await import("../src/mesh/person-sync.ts");
  const listeners = new Set<() => void>();
  const cloud = {
    state: { station: "a" }, peersCurrent: true,
    memberships: () => [{ workspace: "w1", home: true, peers: [{ id: "a" }, { id: "b" }] }],
    listen: (f: () => void) => (listeners.add(f), () => listeners.delete(f)),
    home: () => "w1", chain: () => null,
  } as unknown as Cloud;
  const c = carols();
  const a = new PersonChains(null), b = new PersonChains(null);
  a.keep(c.genesis, [c.g], "w1");
  let once = true;
  const call = async (_peer: string, ws: string | null, request: any) => {
    if (request.method === "lock.person.offer" && once) {
      once = false;
      a.keep(c.genesis, [c.g, c.added], "w1");
    }
    return answerPerson(b, request, ws!) as any;
  };
  const stop = followPersons(cloud, a, call, () => () => {});
  for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r));
  stop();
  assert.deepEqual(hashes(b.kept(c.genesis) ?? []), hashes([c.g, c.added]));
});
