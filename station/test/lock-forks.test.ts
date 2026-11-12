// A station keeps every entry of the workspace's lock the rules take after a parent it keeps that another keeper took
// (a station of the lock, a device saying so), and goes by the chain the rules' fork choice gives (cloud/log-keep.ts,
// cloud/state.ts `keepLock`): by weight, then a removal, then the tie value; another branch winning later moves it
// there, and what was let in on the lost one is turned away. What a device brings itself, a hello, the control plane:
// only what goes on from the head, as before. Kept through a restart; a device told as before where its entry lost;
// two stations that keep different entries come to the same, with a station from before as before; at most
// ASIDE_MOST kept aside. Keys are made per run; nothing depends on time.
import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, sign as nodeSign, type KeyObject } from "node:crypto";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { type Entry, LockRefusal, endpointBytes, entryHash, fold, signedBytes } from "../src/cloud/lock.ts";
import { Cloud, lockPath, writeState } from "../src/cloud/state.ts";
import { tellLocks } from "../src/mesh/lock-events.ts";
import { answerLock, syncWith } from "../src/mesh/lock-sync.ts";
import { PersonChains } from "../src/mesh/person-chains.ts";
import { inLock, lockRoute } from "../src/mesh/serve.ts";
import { Refused } from "../src/mesh/bus.ts";

const WS = "01HFORKFORKFORKFORKFORKFOR";
/// What a fork was answered before every branch was kept, and still is (an app from before reads its words).
const FORK = "the entry disagrees with this station's lock (a fork)";
/// The bound on what a log keeps aside (cloud/log-keep.ts), 256 where the station has none.
const ASIDE_MOST: number = await import("../src/cloud/log-keep.ts").then((m) => m.ASIDE_MOST, () => 256);

const hexOf = (k: KeyObject) => Buffer.from(k.export({ format: "jwk" }).x as string, "base64url").toString("hex");
function ed() {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const hex = hexOf(publicKey);
  return { hex, id: `ed25519:${hex}`, sign: (bytes: Buffer) => nodeSign(null, bytes, privateKey).toString("hex") };
}
type Key = ReturnType<typeof ed>;
const signed = (e: Omit<Entry, "sig">, key: Key): Entry => ({ ...e, sig: { key: key.id, alg: "Ed25519", sig: key.sign(signedBytes(entryHash(e as Entry))) } });
/// An entry after `parent`, signed by `key`.
const child = (parent: Entry, kind: string, body: unknown, key: Key): Entry => signed({ v: 1, ws: WS, seq: parent.seq + 1, prev: entryHash(parent), at: 1000, kind, body }, key);
/// The fork choice's tie value (rules/src/lock/chain.mbt `tie_of`): sha256 of the parent's hash and the signing key's id.
const tie = (parent: Entry, key: Key) => createHash("sha256").update(`${entryHash(parent)}\0${key.id}`).digest("hex");

/// A workspace: owner alice, admins bob and dan, members carol (with a tablet that signs too) and gus; two stations.
function workspace() {
  const p = (sub: string) => ({ sub, signer: ed(), base: ed() });
  const alice = p("alice"), bob = p("bob"), dan = p("dan"), carol = p("carol"), gus = p("gus");
  const tablet = { signer: ed(), base: ed() };
  const stations = [ed(), ed()];
  const body = {
    owner: "alice", origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] },
    members: [["alice", "owner"], ["bob", "admin"], ["dan", "admin"], ["carol", "member"], ["gus", "member"]].map(([sub, role]) => ({ sub, email: `${sub}@x`, role })),
    devices: [
      ...[alice, bob, dan, carol, gus].map((d) => ({ id: d.base.hex, sub: d.sub, kind: "app", label: d.sub, sign_key: d.signer.id })),
      { id: tablet.base.hex, sub: "carol", kind: "app", label: "tablet", sign_key: tablet.signer.id },
    ],
    passkeys: [], stations: stations.map((s, i) => ({ key: s.hex, name: `s${i}` })), gateways: [],
  };
  const first = signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body }, alice.signer);
  return { alice, bob, dan, carol, gus, tablet, stations, first };
}
type W = ReturnType<typeof workspace>;
/// A member added by `by` after `parent` (what any admin may sign).
const member = (parent: Entry, sub: string, by: Key) => child(parent, "member", { sub, email: `${sub}@x`, role: "member" }, by);

/// A station of the workspace with its lock pinned.
function station(w: W, i = 0): Cloud {
  const data = mkdtempSync(join(tmpdir(), "lock-forks-"));
  writeState(data, {
    origin: "https://app.still.fail", station: w.stations[i]!.hex, workspace: WS, workspace_name: "Team", name: `s${i}`, relay_url: "", relay_urls: [],
    grant_keys: { keys: [] }, peers: w.stations.map((s) => ({ id: s.hex, name: "s" })), revocations: [],
  });
  const c = new Cloud(data, false);
  c.takeLock([w.first]);
  return c;
}

/// Each entry `take` was given, taken one call at a time as another station of the lock gives it; what refused one says.
function take(c: Cloud, ...entries: Entry[]): string[] {
  const said: string[] = [];
  for (const e of entries) {
    try {
      c.takeLock([e], null, true);
    } catch (error) {
      said.push((error as Error).message);
    }
  }
  return said;
}

const hashes = (es: Entry[]) => es.map(entryHash);
const chainOf = (c: Cloud) => hashes(c.lockAfter(-1));
/// What lock.json keeps: its chain (`entries`, as every reader from before reads it) and what is kept beside it.
function onDisk(c: Cloud): { entries: string[]; aside: string[] } {
  const raw = JSON.parse(readFileSync(lockPath(c.data), "utf8"));
  return { entries: hashes(raw.entries), aside: hashes(raw.aside ?? []).sort() };
}

const viewerOf = (who: { sub: string; base: Key }, role = "member") => {
  const endpoint = ed().hex;
  return { sub: who.sub, email: `${who.sub}@x`, name: who.sub, role, workspace: WS, device: endpoint, lockDevice: { base: who.base.hex, proof: who.base.sign(endpointBytes(WS, endpoint)) } };
};
/// A device's POST /lock; `keep`: saying a station took them already.
const post = (c: Cloud, entries: Entry[], by: { sub: string; base: Key }, keep = false) => lockRoute(c, "POST", [], Buffer.from(JSON.stringify({ entries, ...(keep ? { keep } : {}) })), viewerOf(by)) as [number, any];

test("an entry valid after an older parent is kept, and the chain is the fork choice's: an owner's before an admin's, whichever came first", () => {
  const w = workspace();
  const bobs = member(w.first, "erin", w.bob.signer);
  const alices = member(w.first, "fay", w.alice.signer);
  const a = station(w), b = station(w);
  assert.deepEqual(take(a, bobs, alices), [], "both taken, in that order");
  assert.deepEqual(take(b, alices, bobs), [], "and in the other");
  for (const c of [a, b]) {
    assert.deepEqual(chainOf(c), hashes([w.first, alices]));
    assert.deepEqual(onDisk(c), { entries: hashes([w.first, alices]), aside: [entryHash(bobs)] });
    assert.equal(c.locked()?.state?.members.has("fay"), true);
    assert.equal(c.locked()?.state?.members.has("erin"), false, "what lost says nothing");
  }
});

test("between equal weights a removal goes first, then the lower tie value, whichever came first", () => {
  const w = workspace();
  // carol takes her tablet out; gus, as much a member, adds a laptop of his: the removal goes first.
  const removal = child(w.first, "device.remove", { id: w.tablet.base.hex }, w.carol.signer);
  const laptop = child(w.first, "device", { id: ed().hex, sub: "gus", kind: "app", label: "laptop" }, w.gus.signer);
  for (const order of [[removal, laptop], [laptop, removal]]) {
    const c = station(w);
    assert.deepEqual(take(c, ...order), []);
    assert.deepEqual(chainOf(c), hashes([w.first, removal]));
    assert.equal(c.locked()?.state?.devices.has(w.tablet.base.hex), false);
  }
  // bob and dan, both admins, each add a member: the lower tie value goes first, whatever the entries say.
  const bobs = member(w.first, "erin", w.bob.signer), dans = member(w.first, "fay", w.dan.signer);
  const first = tie(w.first, w.bob.signer) < tie(w.first, w.dan.signer) ? bobs : dans;
  for (const order of [[bobs, dans], [dans, bobs]]) {
    const c = station(w);
    assert.deepEqual(take(c, ...order), []);
    assert.deepEqual(chainOf(c), hashes([w.first, first]));
  }
});

test("a winning branch that comes later moves the chain: a device let in on the one that lost is turned away, and that is told", () => {
  const w = workspace();
  const c = station(w);
  const told: unknown[] = [];
  const stop = tellLocks(c, new PersonChains(null), (event, data) => told.push([event, data]));
  // bob approves carol's phone; the station takes it and lets the phone in.
  const phone = { sub: "carol", base: ed() };
  const approval = child(w.first, "device", { id: phone.base.hex, sub: "carol", kind: "app", label: "phone" }, w.bob.signer);
  assert.deepEqual(take(c, approval), []);
  const v = viewerOf(phone);
  const admitted = { viewer: v, exp: 4102444800, iat: 1000, sid: "s" } as any;
  assert.equal(inLock(c, admitted, "member", v.device).viewer.role, "member");
  // alice, after the same genesis, signed something else, which comes now: it wins, and the phone is out.
  const alices = member(w.first, "fay", w.alice.signer);
  told.length = 0;
  assert.deepEqual(take(c, alices), []);
  assert.throws(() => inLock(c, admitted, "member", v.device), LockRefusal);
  assert.deepEqual(told, [["lock", { workspace: WS, head: { seq: 1, hash: entryHash(alices), genesis: entryHash(w.first) } }]]);
  stop();
});

test("what a station keeps comes back after a restart: lock.json's entries the chain gone by, as every reader from before reads them, the rest beside", () => {
  const w = workspace();
  const c = station(w);
  const bobs = member(w.first, "erin", w.bob.signer);
  const below = member(bobs, "gil", w.bob.signer);
  const alices = member(w.first, "fay", w.alice.signer);
  assert.deepEqual(take(c, bobs, below, alices), []);
  const raw = JSON.parse(readFileSync(lockPath(c.data), "utf8"));
  assert.equal(fold(raw.entries, null).head, entryHash(alices), "an older station reads the chain gone by");
  const again = new Cloud(c.data, false);
  assert.deepEqual(chainOf(again), hashes([w.first, alices]));
  assert.deepEqual(onDisk(again).aside, hashes([bobs, below]).sort());
  // Back after a restart, what goes on from the chain goes on, and what is aside stays.
  const next = member(alices, "hal", w.alice.signer);
  assert.deepEqual(take(again, next), []);
  assert.deepEqual(chainOf(again), hashes([w.first, alices, next]));
  assert.deepEqual(onDisk(new Cloud(c.data, false)), { entries: hashes([w.first, alices, next]), aside: hashes([bobs, below]).sort() });
});

test("a device that says a station took its entries is answered as before where its entry is on the chain after taking; where it lost, with the refusal of a fork, and why", () => {
  const w = workspace();
  const c = station(w);
  const g = entryHash(w.first);
  const bobs = member(w.first, "erin", w.bob.signer);
  const alices = member(w.first, "fay", w.alice.signer);
  const dans = member(w.first, "gil", w.dan.signer);
  assert.deepEqual(post(c, [w.first, bobs], w.bob), [200, { taken: 1, head: { seq: 1, hash: entryHash(bobs), genesis: g } }]);
  // alice's wins at the genesis: taken, as before.
  assert.deepEqual(post(c, [w.first, alices], w.alice, true), [200, { taken: 1, head: { seq: 1, hash: entryHash(alices), genesis: g } }]);
  // dan's loses to alice's by weight: kept aside, answered as a fork was, with the head and why.
  const head = { seq: 1, hash: entryHash(alices), genesis: g };
  assert.deepEqual(post(c, [w.first, dans], w.dan, true), [409, { error: FORK, head, off: [{ why: "beaten", winner: entryHash(alices), step: "weight", hash: entryHash(dans), seq: 1, kept: true }] }]);
  // bob's again, and one of bob's below it: lost, and below one that lost.
  const below = member(bobs, "hal", w.bob.signer);
  assert.deepEqual(post(c, [w.first, bobs, below], w.bob, true), [409, { error: FORK, head, off: [
    { why: "beaten", winner: entryHash(alices), step: "weight", hash: entryHash(bobs), seq: 1, kept: true },
    { why: "below", under: entryHash(bobs), hash: entryHash(below), seq: 2, kept: true },
  ] }]);
  // One the rules refuse (signed by no device on the lock): as before, with why.
  const forged = member(alices, "ivy", ed());
  const [status, said] = post(c, [w.first, alices, forged], w.bob);
  assert.equal(status, 409);
  assert.equal(said.off?.[0]?.why, "refused");
  assert.equal(said.off[0].refusal, said.error);
  assert.deepEqual(chainOf(c), hashes([w.first, alices]));
});

test("GET /lock?after=N says the hash of the chain's entry at N, for a device holding another there to see it parted", () => {
  const w = workspace();
  const c = station(w);
  const alices = member(w.first, "fay", w.alice.signer);
  assert.deepEqual(take(c, member(w.first, "erin", w.bob.signer), alices), []);
  const get = (after: number) => lockRoute(c, "GET", [["after", String(after)]], Buffer.alloc(0), viewerOf(w.bob))[1] as any;
  assert.equal(get(0).after_hash, entryHash(w.first));
  assert.deepEqual(hashes(get(0).entries), [entryHash(alices)]);
  assert.equal(get(1).after_hash, entryHash(alices));
  assert.equal(get(5).after_hash, undefined);
  assert.equal(get(-1).after_hash, undefined);
});

test("two stations that keep different entries give each other what the other lacks and go by the same chain; with a station from before, as before", async () => {
  const w = workspace();
  const a = station(w, 0), b = station(w, 1);
  const bobs = member(w.first, "erin", w.bob.signer), below = member(bobs, "gil", w.bob.signer);
  const alices = member(w.first, "fay", w.alice.signer);
  assert.deepEqual(take(a, bobs, below), []);
  assert.deepEqual(take(b, alices), []);
  const asked: string[] = [];
  const to = (other: Cloud) => async (_peer: string, ws: string | null, request: any) => (asked.push(request.method), answerLock(other, request, ws) as any);
  await syncWith(a, to(b), "b");
  const all = (c: Cloud) => [...chainOf(c), ...onDisk(c).aside].sort();
  for (const c of [a, b]) assert.deepEqual(chainOf(c), hashes([w.first, alices]));
  assert.deepEqual(all(a), all(b), "the same kept, the branch that lost too");
  assert.equal(all(a).length, 4);
  // A station from before knows lock.head, lock.get {after} and lock.put alone: brought level as before.
  const c = station(w, 0), old = station(w, 1);
  const more = member(w.first, "fay", w.alice.signer);
  assert.deepEqual(take(c, more), []);
  const before = new Set(["lock.head", "lock.get", "lock.put"]);
  const calls: string[] = [];
  const toOld = async (_peer: string, ws: string | null, request: any) => {
    calls.push(request.method);
    if (!before.has(request.method) || request.hashes !== undefined) throw new Refused("unknown lock method");
    return answerLock(old, request, ws) as any;
  };
  await syncWith(c, toOld, "old");
  assert.deepEqual(chainOf(old), hashes([w.first, more]));
  assert.deepEqual(calls, ["lock.kept", "lock.head", "lock.put"]);
});

test("at most ASIDE_MOST entries are kept aside a lock: what would land aside past it is not kept, and the chain is the same and goes on", () => {
  const w = workspace();
  const c = station(w);
  const alices = member(w.first, "fay", w.alice.signer);
  assert.deepEqual(take(c, alices), []);
  // bob, out of the lock or not, signs more after the genesis than any history leaves.
  const many = Array.from({ length: ASIDE_MOST + 3 }, (_, i) => member(w.first, `x${i}`, w.bob.signer));
  c.takeLock(many, null, true);
  assert.deepEqual(chainOf(c), hashes([w.first, alices]));
  assert.equal(onDisk(c).aside.length, ASIDE_MOST);
  // One more: answered as a fork, not kept.
  const one = member(w.first, "late", w.bob.signer);
  const [status, said] = post(c, [w.first, one], w.bob, true);
  assert.equal(status, 409);
  assert.equal(said.error, FORK);
  assert.deepEqual(said.off.map((o: any) => [o.why, o.kept]), [["beaten", false]]);
  assert.equal(onDisk(c).aside.length, ASIDE_MOST);
  // What goes on from the chain is taken as ever.
  const next = member(alices, "hal", w.alice.signer);
  assert.equal(post(c, [w.first, alices, next], w.alice)[0], 200);
  assert.deepEqual(chainOf(c), hashes([w.first, alices, next]));
});

test("over the fork-choice model's worlds, a station given what a keeper stores, in batches as they may come, goes by the keeper's chain", async () => {
  const { G, VARIANTS, World, drawSteps } = await import("./lock-fork-choice-model.ts");
  const { Rng, stationKeys } = await import("./lock-world-sim.ts");
  const v = { ...VARIANTS.find((x) => x.votes === "roles" && x.removal === "device" && x.offers === "all" && x.resign === "on" && x.hashfield === "as-is")!, tie: "signer" as const };
  let compared = 0, branched = 0;
  const differ: string[] = [];
  for (const family of ["free", "faults"] as const) {
    for (let seed = 1; seed <= 2; seed++) {
      const w = new World(seed, v, family);
      w.run(drawSteps(seed, 120));
      w.finish();
      const r = new Rng(seed ^ 0xf0);
      for (const k of w.keepers) {
        // (a chain gone by that ends turned off is let go by a station: nothing to compare)
        if (k.active.some((h) => k.store.get(h)!.kind === "disable")) continue;
        const data = mkdtempSync(join(tmpdir(), "lock-forks-model-"));
        writeState(data, { origin: "o", station: stationKeys[0]!.hex, workspace: G.ws, workspace_name: "", name: "", relay_url: "", relay_urls: [], grant_keys: { keys: [] }, peers: [], revocations: [] });
        const c = new Cloud(data, false);
        c.takeLock([G]);
        // Parents before children, in any order else, in batches of one to eight.
        const rest = [...k.store.values()].filter((e) => e.seq > 0).map((e) => ({ e, n: r.next() })).sort((a, b) => a.e.seq - b.e.seq || a.n - b.n).map((x) => x.e);
        for (let i = 0; i < rest.length;) {
          const n = 1 + r.int(8);
          try {
            c.takeLock(rest.slice(i, i + n), null, true);
          } catch {}
          i += n;
        }
        compared++;
        if (k.active.length < k.store.size) branched++;
        if (chainOf(c).join() !== k.active.join()) differ.push(`seed ${seed} ${family} ${k.name}: the station's chain ${c.lockAfter(-1).length}, the keeper's ${k.active.length}`);
      }
    }
  }
  assert.deepEqual(differ, []);
  assert.ok(compared > 10 && branched > 0, `${compared} compared, ${branched} with entries off the chain`);
});

test("an owner's disable that lost its place to an entry after the same one, taken first elsewhere: the station that took the disable is on again; one that missed it, off", () => {
  const w = workspace();
  // alice's phone, an owner's own device as her app is: as much weight.
  const phone = { signer: ed(), base: ed() };
  const g0 = w.first;
  const body = { ...(g0.body as any), devices: [...(g0.body as any).devices, { id: phone.base.hex, sub: "alice", kind: "app", label: "phone", sign_key: phone.signer.id }] };
  const first = signed({ v: 1, ws: WS, seq: 0, prev: null, at: 1000, kind: "genesis", body }, w.alice.signer);
  const v = { ...w, first };
  const disable = child(first, "disable", {}, w.alice.signer);
  const other = member(first, "fay", phone.signer);
  const disableFirst = tie(first, w.alice.signer) < tie(first, phone.signer);
  // a took the disable, b the other.
  const a = station(v, 0), b = station(v, 1);
  assert.deepEqual(take(a, disable), []);
  assert.equal(a.locked(), null, "off at a");
  assert.deepEqual(take(b, other), []);
  // b offers a what it lacks; a gives b what b lacks (lock-sync.ts offerOff, as followLock does).
  answerLock(a, { method: "lock.offer", entries: [other] });
  answerLock(b, { method: "lock.offer", entries: [disable] });
  if (disableFirst) {
    assert.equal(a.locked(), null);
    assert.equal(b.locked(), null, "b hears the disable and lets the lock go");
  } else {
    assert.deepEqual(chainOf(a), hashes([first, other]), "a is on again, as b");
    assert.deepEqual(chainOf(b), hashes([first, other]));
  }
});

test("what a device brings itself, its hello and the control plane are taken only where they go on from the head: one signer's two entries after one parent, the second answered a fork as before, nothing kept aside", async () => {
  const { applyState } = await import("../src/cloud/presence.ts");
  const { inLockBringing } = await import("../src/mesh/serve.ts");
  const w = workspace();
  const c = station(w);
  const g = entryHash(w.first);
  // carol's app signs two after the same entry, one a moment after the other (run 2 of the station's end to end, 2026-11-12).
  const tab = { sub: "carol", base: ed() };
  const device = child(w.first, "device", { id: tab.base.hex, sub: "carol", kind: "app", label: "tab" }, w.carol.signer);
  const other = child(w.first, "device", { id: ed().hex, sub: "carol", kind: "app", label: "laptop" }, w.carol.signer);
  assert.deepEqual(post(c, [w.first, device], w.carol), [200, { taken: 1, head: { seq: 1, hash: entryHash(device), genesis: g } }]);
  const head = { seq: 1, hash: entryHash(device), genesis: g };
  assert.deepEqual(post(c, [w.first, other], w.carol), [409, { error: FORK, head, off: [{ why: "not on the head", hash: entryHash(other), seq: 1, kept: false }] }]);
  // Brought in a hello, or by the control plane: not kept either.
  const v = viewerOf({ sub: "carol", base: ed() });
  const third = child(w.first, "device", { id: ed().hex, sub: "carol", kind: "app", label: "phone" }, w.carol.signer);
  const asked = { viewer: { ...v, sub: "carol" }, exp: 4102444800, iat: 1000, sid: "s" } as any;
  // (what put it in, after the entry the station did not take: as a device on that branch would bring it)
  const hello = child(other, "device", { id: v.lockDevice.base, sub: "carol", kind: "app", label: "hello" }, w.carol.signer);
  assert.throws(() => inLockBringing(c, asked, "member", v.device, { lock: { entries: [other, hello] } }));
  applyState(c, JSON.stringify({ type: "lock", entries: [w.first, third] }));
  assert.deepEqual(chainOf(c), hashes([w.first, device]));
  assert.deepEqual(onDisk(c), { entries: hashes([w.first, device]), aside: [] });
  assert.equal(c.lockKept().length, 2, "nothing kept aside");
});

test("a control plane whose chain parted from the station's (it took the entry that lost): given, once for that head, what the station goes by from where they part, as another keeper's (`keep`); its own entries still taken only on the head", async () => {
  const { applyState } = await import("../src/cloud/presence.ts");
  const w = workspace();
  const c = station(w);
  const bobs = member(w.first, "erin", w.bob.signer);
  const alices = member(w.first, "fay", w.alice.signer);
  assert.deepEqual(take(c, bobs, alices), []);
  assert.deepEqual(chainOf(c), hashes([w.first, alices]), "the owner's wins");
  const after = member(alices, "gil", w.alice.signer);
  assert.deepEqual(take(c, after), []);
  const g = entryHash(w.first);
  const state = (lock: unknown) => JSON.stringify({
    type: "state", workspace: WS, workspace_name: "Team", name: "s0", origin: "https://app.still.fail", relay_urls: [],
    peers: w.stations.map((s, i) => ({ id: s.hex, name: `s${i}` })), grant_keys: { keys: [] }, revocations: [], lock,
  });
  const sent: any[] = [];
  const send = (f: unknown) => void sent.push(f);
  // The plane's head the entry that lost, kept aside here: given the chain from its parent on.
  applyState(c, state({ seq: 1, hash: entryHash(bobs), genesis: g }), send);
  assert.deepEqual(sent.map((f) => [f.type, f.keep, hashes(f.entries)]), [["lock.put", true, hashes([alices, after])]]);
  // The same head said again (a plane from before refusing it says its head again): nothing more.
  applyState(c, state({ seq: 1, hash: entryHash(bobs), genesis: g }), send);
  assert.equal(sent.length, 1, "once a head");
  // A head this station keeps nothing of (an entry no station took): the last of its chain, from the genesis here.
  const nobodys = member(bobs, "hal", w.bob.signer);
  const elsewhere = member(w.first, "ivy", w.dan.signer);
  applyState(c, state({ seq: 1, hash: entryHash(elsewhere), genesis: g }), send);
  assert.deepEqual(sent.slice(1).map((f) => [f.type, f.keep, hashes(f.entries)]), [["lock.put", true, hashes([w.first, alices, after])]]);
  // What the plane brings of its branch: not kept, as before.
  applyState(c, JSON.stringify({ type: "lock", entries: [w.first, bobs, nobodys] }), send);
  assert.deepEqual(chainOf(c), hashes([w.first, alices, after]));
  assert.ok(!c.lockKept().some((e) => entryHash(e) === entryHash(nobodys)), "its own entry not kept");
});

test("an entry a station takes while it brings a peer level is brought to that peer too (followLock goes by what it kept as the sync began)", async () => {
  const { followLock } = await import("../src/mesh/lock-sync.ts");
  const w = workspace();
  const a = station(w, 0), b = station(w, 1);
  const first = member(w.first, "fay", w.alice.signer);
  const second = member(first, "gil", w.alice.signer);
  assert.deepEqual(take(a, first), []);
  let once = true;
  const call = async (_peer: string, ws: string | null, request: any) => {
    // A device brings `a` one more as `b` is given what it lacked.
    if (request.method === "lock.offer" && once) {
      once = false;
      assert.equal(post(a, [w.first, first, second], w.alice)[0], 200);
    }
    return answerLock(b, request, ws) as any;
  };
  const stop = followLock(a, call, () => () => {});
  for (let i = 0; i < 20; i++) await new Promise((r) => setImmediate(r));
  stop();
  assert.deepEqual(chainOf(b), hashes([w.first, first, second]));
});

test("an entry a device brings on the head keeps what is kept aside: in memory, in lock.json and in what lock.kept says", () => {
  const w = workspace();
  const c = station(w);
  const alices = member(w.first, "fay", w.alice.signer);
  const bobs = member(w.first, "erin", w.bob.signer);
  assert.deepEqual(take(c, alices, bobs), []);
  assert.deepEqual(onDisk(c).aside, [entryHash(bobs)]);
  const next = member(alices, "gil", w.alice.signer);
  assert.equal(post(c, [w.first, alices, next], w.alice)[0], 200);
  assert.deepEqual(chainOf(c), hashes([w.first, alices, next]));
  assert.deepEqual(onDisk(c), { entries: hashes([w.first, alices, next]), aside: [entryHash(bobs)] });
  assert.ok(hashes(c.lockKept()).includes(entryHash(bobs)), "in memory");
  assert.ok(((answerLock(c, { method: "lock.kept" }) as any).hashes as string[]).includes(entryHash(bobs)), "told to the other stations");
});
