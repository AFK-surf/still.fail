// The station as where devices find their locks, not the cloud (the root AGENTS.md, The cloud is the
// account system): a person's own lock brought, read and kept level between stations; the locks' changes told on the
// event stream; the devices that came listed for a lock's owner.
import assert from "node:assert/strict";
import { generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type Entry, LockRefusal, entryHash, signedBytes } from "../src/cloud/lock.ts";
import type { Cloud } from "../src/cloud/state.ts";
import { CHAINS_A_PERSON, PersonChains } from "../src/mesh/person-chains.ts";
import { answerPerson, followPersons, personSyncWith } from "../src/mesh/person-sync.ts";
import { tellLocks } from "../src/mesh/lock-events.ts";
import { SEEN_SECS, SeenDevices } from "../src/mesh/seen-devices.ts";
import { lockPartRoute, refusalOf } from "../src/mesh/serve.ts";
import type { Viewer } from "../src/mesh/credential.ts";

function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = (publicKey.export({ format: "der", type: "spki" }) as Buffer).subarray(-32).toString("hex");
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof ed>;
const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(entryHash(e as Entry))) } } as Entry);

/// A person's lock: `chain`, entries of it as made so far; `added()` puts another device on it.
function personal(sub: string) {
  const first = { key: ed(), base: ed() };
  const chain: Entry[] = [];
  const add = (kind: string, body: unknown, by: Key) => {
    const last = chain[chain.length - 1];
    chain.push(signed({ v: 1, ws: `person:${sub}`, seq: chain.length, prev: last ? entryHash(last) : null, at: 1000, kind, body }, by));
  };
  add("genesis", { sub, device: { key: first.key.id, id: first.base.hex, label: "first" } }, first.key);
  const added = () => add("device", { key: ed().id, id: ed().hex, label: `d${chain.length}` }, first.key);
  return { first, chain, add, added, genesis: entryHash(chain[0]!) };
}

const viewer = (sub: string, role = "member", workspace = "w1"): Viewer => ({ sub, email: `${sub}@x`, name: sub, role, workspace, device: "ee".repeat(32) });
const body = (v: unknown) => Buffer.from(JSON.stringify(v));
const fakeCloud = (data: string, extra: Partial<Record<string, unknown>> = {}) => ({ data, ...extra }) as unknown as Cloud;

test("a person's devices bring their lock to the station and read it there, bound or not", () => {
  const cloud = fakeCloud(mkdtempSync(join(tmpdir(), "person-carry-")));
  const carol = personal("carol");
  // Brought, though no workspace lock binds carol here.
  const [status, said] = lockPartRoute(cloud, "person", "POST", body({ chain: carol.chain }), viewer("carol"));
  assert.equal(status, 200);
  assert.deepEqual(said, { genesis: carol.genesis, length: 1 });
  // A device added on it, brought by another of hers.
  carol.added();
  assert.equal(lockPartRoute(cloud, "person", "POST", body({ chain: carol.chain }), viewer("carol"))[0], 200);
  // An older chain brought again is judged as the longer one kept: what is read is the longer.
  assert.equal(lockPartRoute(cloud, "person", "POST", body({ chain: carol.chain.slice(0, 1) }), viewer("carol"))[0], 200);
  const [, read] = lockPartRoute(cloud, "person", "GET", Buffer.alloc(0), viewer("carol")) as [number, any];
  assert.deepEqual(read.chains.map((c: any) => [c.genesis, c.entries.length]), [[carol.genesis, 2]]);
  // Someone else's lock, brought by carol: refused; and bob reads none of carol's.
  const bob = personal("bob");
  assert.equal(lockPartRoute(cloud, "person", "POST", body({ chain: bob.chain }), viewer("carol"))[0], 409);
  assert.deepEqual((lockPartRoute(cloud, "person", "GET", Buffer.alloc(0), viewer("bob"))[1] as any).chains, []);
  // A chain at odds with the one kept (a fork from its first entry): refused, the kept one stays.
  const fork = [carol.chain[0]!, signed({ v: 1, ws: "person:carol", seq: 1, prev: carol.genesis, at: 1000, kind: "device", body: { key: ed().id, id: ed().hex, label: "x" } }, carol.first.key)];
  assert.equal(lockPartRoute(cloud, "person", "POST", body({ chain: fork }), viewer("carol"))[0], 409);
  // One not signed by a device on it: refused.
  const forged = [...carol.chain, signed({ v: 1, ws: "person:carol", seq: 2, prev: entryHash(carol.chain[1]!), at: 1000, kind: "device", body: { key: ed().id, id: ed().hex, label: "y" } }, ed())];
  assert.equal(lockPartRoute(cloud, "person", "POST", body({ chain: forged }), viewer("carol"))[0], 409);
  assert.equal((lockPartRoute(cloud, "person", "GET", Buffer.alloc(0), viewer("carol"))[1] as any).chains[0].entries.length, 2);
});

test("the chains kept are read back after a restart, the workspaces they were heard in with them", () => {
  const dir = mkdtempSync(join(tmpdir(), "person-chains-"));
  const path = join(dir, "person-chains.json");
  const carol = personal("carol");
  const kept = new PersonChains(path);
  kept.keep(carol.genesis, carol.chain, "w1");
  kept.keep(carol.genesis, carol.chain, "w2");
  const again = new PersonChains(path);
  assert.deepEqual(again.heardIn("w2").map(([g]) => g), [carol.genesis]);
  assert.deepEqual(again.of("carol").map(([g, c]) => [g, c.length]), [[carol.genesis, 1]]);
  // A file from before the workspaces were kept: the chains alone.
  writeFileSync(path, JSON.stringify({ [carol.genesis]: carol.chain }));
  const before = new PersonChains(path);
  assert.equal(before.kept(carol.genesis)?.length, 1);
  assert.deepEqual(before.heardIn("w1"), []);
  // A person's chains begun anew past the few kept: the oldest go.
  const many = new PersonChains(null);
  const locks = Array.from({ length: CHAINS_A_PERSON + 1 }, () => personal("dan"));
  for (const l of locks) many.keep(l.genesis, l.chain, "w1");
  assert.deepEqual(many.of("dan").map(([g]) => g), locks.slice(1).map((l) => l.genesis));
  assert.ok(JSON.parse(readFileSync(path, "utf8")));
});

test("stations bring each other level in the person locks heard in their workspace", async () => {
  const a = new PersonChains(null), b = new PersonChains(null);
  const carol = personal("carol"), dan = personal("dan"), erin = personal("erin");
  a.keep(carol.genesis, [...carol.chain], "w1");
  dan.added();
  b.keep(dan.genesis, dan.chain.slice(0, 1), "w1");
  a.keep(dan.genesis, [...dan.chain], "w1");
  // Heard in another workspace only: not b's to have.
  a.keep(erin.genesis, erin.chain, "w2");
  const calls: string[] = [];
  const toB = async (_peer: string, ws: string | null, request: any) => {
    calls.push(request.method);
    return answerPerson(b, request, ws!) as any;
  };
  await personSyncWith(a, toB, "b", "w1");
  assert.equal(b.kept(carol.genesis)?.length, 1);
  assert.equal(b.kept(dan.genesis)?.length, 2);
  assert.equal(b.kept(erin.genesis), null);
  // b has more now (another device on carol's): a takes it from b.
  carol.added();
  b.keep(carol.genesis, [...carol.chain], "w1");
  await personSyncWith(a, toB, "b", "w1");
  assert.equal(a.kept(carol.genesis)?.length, 2);
  assert.ok(calls.includes("lock.person.get"));
  // What b says that does not hold is not taken.
  const lying = async () => ({ heads: { [carol.genesis]: 9 }, chain: [...carol.chain, { forged: true }] }) as any;
  await assert.rejects(personSyncWith(a, lying, "b", "w1"));
  assert.equal(a.kept(carol.genesis)?.length, 2);
});

test("a chain kept grows: the other stations are brought level, one that could not be tried again", async () => {
  const listeners = new Set<() => void>();
  const cloud = {
    state: { station: "a" },
    peersCurrent: true,
    memberships: () => [{ workspace: "w1", home: true, peers: [{ id: "a" }, { id: "b" }] }],
    listen: (f: () => void) => (listeners.add(f), () => listeners.delete(f)),
    home: () => "w1", chain: () => null,
  } as unknown as Cloud;
  const a = new PersonChains(null), b = new PersonChains(null);
  let down = true;
  const call = async (_peer: string, ws: string | null, request: any) => {
    if (down) throw new Error("the line is down");
    return answerPerson(b, request, ws!) as any;
  };
  const timers: (() => void)[] = [];
  const stop = followPersons(cloud, a, call, (_ms, f) => (timers.push(f), () => {}));
  const carol = personal("carol");
  a.keep(carol.genesis, carol.chain, "w1");
  await new Promise((r) => setImmediate(r));
  assert.equal(b.kept(carol.genesis), null);
  assert.equal(timers.length > 0, true);
  down = false;
  timers.shift()!();
  for (let i = 0; i < 5; i++) await new Promise((r) => setImmediate(r));
  assert.equal(b.kept(carol.genesis)?.length, 1);
  stop();
});

test("a lock's change is told on the event stream: the workspace's to its members, a person's to their devices", () => {
  const listeners = new Set<() => void>();
  let head = { seq: 3, head: "h3", genesis: "g" };
  const cloud = {
    memberships: () => [{ workspace: "w1", home: true, peers: [] }],
    locked: () => ({ state: head }),
    chain: () => ({ state: head }),
    forceWord: () => "",
    listen: (f: () => void) => (listeners.add(f), () => listeners.delete(f)),
  } as unknown as Cloud;
  const chains = new PersonChains(null);
  const told: [string, unknown, string, unknown][] = [];
  const stop = tellLocks(cloud, chains, (event, data, of, to) => told.push([event, data, of, to]));
  // Nothing changed yet.
  for (const f of listeners) f();
  assert.deepEqual(told, []);
  head = { seq: 4, head: "h4", genesis: "g" };
  for (const f of listeners) f();
  assert.deepEqual(told, [["lock", { workspace: "w1", head: { seq: 4, hash: "h4", genesis: "g" } }, "lock\0w1", { workspace: "w1" }]]);
  const carol = personal("carol");
  chains.keep(carol.genesis, carol.chain, "w1");
  assert.deepEqual(told[1], ["person", { genesis: carol.genesis, length: 1 }, `person\0${carol.genesis}`, { subs: ["carol"] }]);
  stop();
});

test("the devices that came are listed for the workspace's owners and admins, a member's own for them", () => {
  const dir = mkdtempSync(join(tmpdir(), "seen-devices-"));
  const seen = new SeenDevices(join(dir, "seen.json"));
  seen.saw(1000, { workspace: "w1", sub: "carol", email: "c@x" }, "d1", "b1", { kind: "app", label: "Carol's Mac" });
  seen.saw(1100, { workspace: "w1", sub: "bob", email: "b@x" }, "d2", null, null);
  seen.saw(1200, { workspace: "w2", sub: "carol", email: "c@x" }, "d3", "b3", { kind: "web" });
  // Seen again: its last use moves on, what it said before stays.
  seen.saw(1000 + 7200, { workspace: "w1", sub: "carol", email: "c@x" }, "d1", null, null);
  const all = seen.of("w1", 9000, "alice", true);
  assert.deepEqual(all.map((r) => [r.sub, r.device, r.base, r.kind, r.label, r.first_seen, r.last_seen]), [
    ["bob", "d2", null, null, null, 1100, 1100],
    ["carol", "d1", "b1", "app", "Carol's Mac", 1000, 8200],
  ]);
  assert.deepEqual(seen.of("w1", 9000, "carol", false).map((r) => r.device), ["d1"]);
  // Kept across a restart; past SEEN_SECS, no more.
  const again = new SeenDevices(join(dir, "seen.json"));
  assert.equal(again.of("w2", 9000, "carol", false).length, 1);
  assert.equal(again.of("w1", 1100 + SEEN_SECS + 1, "alice", true).map((r) => r.device).join(), "d1");
  // The route: an owner or admin sees everyone's, a member their own.
  const cloud = fakeCloud(mkdtempSync(join(tmpdir(), "seen-route-")));
  assert.equal(lockPartRoute(cloud, "devices", "GET", Buffer.alloc(0), viewer("carol"))[0], 200);
});

test("a device refused for the lock is told its person's own lock, for a new one to find who may let it in with no cloud", () => {
  const kept = [{ v: 1, ws: "w1", seq: 0, kind: "genesis" }, { v: 1, ws: "w1", seq: 1, kind: "device.remove" }];
  const cloud = fakeCloud(mkdtempSync(join(tmpdir(), "refusal-person-")), { locked: () => null, home: () => null, lockAfter: () => [...kept] });
  const carol = personal("carol");
  lockPartRoute(cloud, "person", "POST", body({ chain: carol.chain }), viewer("carol"));
  const said = refusalOf(cloud, {}, "ee".repeat(32), new LockRefusal("this device is not on the lock its person bound in this workspace"), undefined, "carol");
  assert.deepEqual((said.person as any[]).map((c) => [c.genesis, c.entries.length]), [[carol.genesis, 1]]);
  // And the workspace lock's last entries, for one taken out of it to hear so.
  assert.deepEqual((said.entries as any[]).map((e) => e.seq), [0, 1]);
  // Whose credential did not check out, or another's: nothing of it.
  assert.equal(refusalOf(cloud, {}, "ee".repeat(32), new LockRefusal("x"), undefined, null).person, undefined);
  assert.equal(refusalOf(cloud, {}, "ee".repeat(32), new LockRefusal("x"), undefined, null).entries, undefined);
  assert.equal(refusalOf(cloud, {}, "ee".repeat(32), new LockRefusal("x"), undefined, "bob").person, undefined);
});
