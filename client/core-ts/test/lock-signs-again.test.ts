// The workspace lock as this device signs it (views/lock.ts `Lock.append`): one entry at a time, each after the head
// held as its turn begins; an entry that lost its place (a station's 409, a read that moved the chain held off it) signed
// again by this device where that still says what was meant, else let be with words that say what to do; taken by
// hash, not by how far a station's chain goes; a station on another branch of the lock is no other lock; and what this
// device keeps carried to a station that lacks it (`carry`, `personalStations` `carry`). The stations are simulated as
// station/src/cloud/state.ts `keepLock` keeps a lock: what a device brings itself only where it goes on from the head
// (else 409 and not kept), what it brings with `keep` by the rules' fork choice (src/lock-keep.ts `keep`, the same
// rules). The world: `ws`, its lock's genesis signed by this device (ME, the owner's app), naming OLD and THIRD (two
// other apps of the owner's, each signing with a key of its own) and PEER (a web page of the owner's).
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect } from "effect";
import { Core } from "../src/core.ts";
import { apply as applyOps } from "../src/delta.ts";
import { CoreError } from "../src/error.ts";
import { t } from "../src/i18n.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { keep } from "../src/lock-keep.ts";
import { hex, utf8 } from "../src/util.ts";
import { lockChain } from "../src/vault/lock-check.ts";
import { ASKED_MS, Lock, TAKEN_MS, asked, fold, held, lockView, pendingHeld, read } from "../src/views/lock.ts";
import { HostWire } from "../src/station/wire.ts";
import { subscribe } from "./helpers.ts";
import { ME, genesis, grant, rig, unhex, withoutMesh } from "./lock-rig.ts";
import { Status, stationReplies } from "./station-fixture.ts";

const A = "aa".repeat(32);
const S = "bb".repeat(32);
const T = "cc".repeat(32);
const U = "c0".repeat(32);
const V = "c1".repeat(32);
const N = "c2".repeat(32);
const OLD = "ee".repeat(32);
const THIRD = "ef".repeat(32);
const PEER = "f0".repeat(32);
/// What a station says as it refuses an entry that does not go on from its head (station/src/cloud/state.ts FORK).
const FORK = "the entry disagrees with this station's lock (a fork)";

/// A key of an app of the owner's elsewhere, made from `n`.
function keyOf(n: number) {
  const seed = new Uint8Array(32).fill(n);
  return { id: `ed25519:${hex(ed25519.getPublicKey(seed))}`, signBytes: (b: Uint8Array) => hex(ed25519.sign(b, seed)), seed };
}
const oldKey = keyOf(9);
const thirdKey = keyOf(8);
const headOf = (chain: readonly Entry[]): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
/// An entry after `chain` signed with `k`.
function signedBy(k: { id: string; signBytes(b: Uint8Array): string }, chain: readonly Entry[], at: number, kind: string, body: unknown): Entry {
  const e = next("ws", headOf(chain), at, kind, body);
  return { ...e, sig: { key: k.id, alg: "Ed25519", sig: k.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e))])) } };
}

/// A station of the lock as station/src/mesh/serve.ts and cloud/state.ts `keepLock` answer it. `say.before`: what
/// reaches it just before the next entry a device brings itself (another device's, taken first: the device read the
/// chain before); `delay` how long a POST takes; `down` it answers nothing (its link fails); `forks` whether it says it
/// keeps what a device brings as another keeper's; `deaf` it keeps nothing brought with `keep` (as one that cannot be
/// reached by it); `none` it keeps no lock (reset on its own machine). `posts`: what each POST /lock brought. `person`: the chain it keeps of the person's own lock;
/// `personPosts` what each POST /lock/person brought.
function station(g0: Entry) {
  let kept = { entries: [g0] as Entry[], aside: [] as Entry[] };
  const root = entryHash(g0);
  const rules = { chain: (all: Entry[]) => lockChain(all, root), pre: (e: Entry) => (e?.ws !== g0.ws ? "an entry of another lock" : null) };
  const say = { before: null as (() => void) | null, delay: 0, down: false, forks: true, deaf: false, none: false, person: [] as Entry[], takesPerson: false };
  const posts: { entries: Entry[]; keep: boolean }[] = [];
  const personPosts: { chain: Entry[]; keep: boolean }[] = [];
  const fork = () => Effect.fail(new CoreError("http_409", FORK, 409));
  const take = (brought: Entry[], keepIt: boolean): Effect.Effect<unknown, CoreError> => {
    const last = entryHash(brought.at(-1)!);
    if (keepIt) {
      if (!say.deaf) kept = keep(kept, brought, rules).kept;
    } else {
      // Only what goes on from the head, in order (a fresh entry that does not is refused and not kept).
      const have = new Set([...kept.entries, ...kept.aside].map(entryHash));
      let chain = kept.entries;
      for (const e of [...brought].sort((a, b) => a.seq - b.seq)) {
        if (have.has(entryHash(e))) continue;
        if (e.seq !== chain.length || e.prev !== entryHash(chain.at(-1)!)) return fork();
        chain = [...chain, e];
      }
      const r = lockChain(chain, root);
      if (r.at.length !== chain.length) return Effect.fail(new CoreError("http_409", "the lock's rules refuse it", 409));
      kept = { entries: chain, aside: kept.aside };
    }
    return kept.entries.some((e) => entryHash(e) === last) ? Effect.succeed({ taken: 1, head: headOf(kept.entries) }) : fork();
  };
  // (frozen: what it is asked waits, no answer and no error, until it is thawed, then answered as it keeps the lock then)
  let frozen: Deferred.Deferred<void> | null = null;
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> =>
    Effect.suspend(() => (frozen === null ? answerNow(method, path, body) : Effect.andThen(Deferred.await(frozen), Effect.suspend(() => answerNow(method, path, body)))));
  const answerNow = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.down) return Effect.fail(new CoreError("network", "unreachable"));
    const serves = { takes: ["person"], serves: ["person", "devices", "told", ...(say.forks ? ["forks"] : [])] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after=")) && say.none) return Effect.succeed({ head: null, entries: [], ...serves });
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      const at = after >= 0 ? kept.entries[after] : undefined;
      return Effect.succeed({ head: headOf(kept.entries), entries: kept.entries.filter((e) => e.seq > after), ...(at !== undefined ? { after_hash: entryHash(at) } : {}), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      const b = body as { entries: Entry[]; keep?: boolean };
      posts.push({ entries: b.entries, keep: b.keep === true });
      const work = Effect.suspend(() => {
        if (!b.keep && say.before !== null) {
          const before = say.before;
          say.before = null;
          before();
        }
        return take(b.entries, b.keep === true);
      });
      return say.delay > 0 ? Effect.andThen(Effect.sleep(say.delay), work) : work;
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: say.person.length === 0 ? [] : [{ genesis: entryHash(say.person[0]!), entries: say.person }] });
    if (method === "POST" && path === "/lock/person") {
      const b = body as { chain: Entry[]; keep?: boolean };
      personPosts.push({ chain: b.chain, keep: b.keep === true });
      if (say.takesPerson && !b.keep) say.person = b.chain;
      return Effect.succeed({ genesis: entryHash(b.chain[0]!), length: b.chain.length });
    }
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return {
    say, posts, personPosts, answer,
    chain: () => kept.entries,
    set: (chain: Entry[]) => void (kept = { entries: chain, aside: [] }),
    add: (e: Entry) => void (kept = { entries: [...kept.entries, e], aside: kept.aside }),
    /// What another keeper took, kept by the rules' fork choice (station/src/mesh/lock-sync.ts: stations level).
    keeps: (es: Entry[]) => void (kept = keep(kept, es, rules).kept),
    aside: () => kept.aside,
    /// Stopped where it is (`e2e-local.sh freeze`, SIGSTOP), and started again.
    freeze: () => void (frozen = Deferred.makeUnsafe<void>()),
    thaw: () => {
      const f = frozen;
      frozen = null;
      if (f !== null) Deferred.doneUnsafe(f, Effect.void);
    },
  };
}

/// `ids` the stations of `ws` (each named by its lock); `another`: those keeping a lock of another genesis.
async function setUp(ids: string[], another: string[] = []) {
  const g = grant();
  let me: Signer | null = null;
  const devices = [
    { id: OLD, sub: "s1", kind: "app", label: "old", sign_key: oldKey.id },
    { id: THIRD, sub: "s1", kind: "app", label: "third", sign_key: thirdKey.id },
    { id: PEER, sub: "s1", kind: "web", label: "peer" },
  ];
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, ids.map((key, i) => ({ key, name: `st${i}` })), g.keys, ME, devices) }), undefined, ids);
  const inner = r.core.inner;
  const signer = me! as Signer;
  const g0 = r.cloud.chains.get("ws")![0]!;
  const other = genesis("ws", keyOf(5), false);
  const stations = new Map(ids.map((id) => [id, station(another.includes(id) ? other : g0)]));
  /// `ws`'s stations reached by `inner`'s requests as these simulated ones (each core's: the app quit and started again).
  const reach = (inner: typeof r.core.inner) => {
    const original = inner.stations.requests.call.bind(inner.stations.requests);
    inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
      const [ws, id] = addr.toString().split("/");
      const st = ws === "ws" ? stations.get(id!) : undefined;
      if (st !== undefined && path.startsWith("/lock")) return st.answer(method, path, body);
      return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
    }) as typeof inner.stations.requests.call;
  };
  reach(inner);
  const run = async <X>(e: Effect.Effect<X, any>, limit = 5_000): Promise<X> => {
    let done = false;
    let failed: unknown;
    let out: X | undefined;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    for (let i = 0; i < limit / 10 && !done; i++) await r.host.time.pass(10);
    assert.ok(done, "no answer");
    await r.host.time.pass(100);
    if (failed !== undefined) throw failed;
    return out as X;
  };
  const settle = async (ms = 2_000) => {
    for (let n = 0; n < ms; n += 10) await r.host.time.pass(10);
  };
  // (its key of its person's lock made before, as lock-follows-forks.test.ts: no lock of its own begun meanwhile)
  await run(inner.adb.personal().makeKey());
  await run(read(inner, "ws"));
  const st = (id: string) => stations.get(id)!;
  /// The fresh entries (brought without `keep`) of this device's key each station was brought, by hash.
  const fresh = () => {
    const out = new Map<string, Entry>();
    for (const s of stations.values()) for (const p of s.posts) if (!p.keep) for (const e of p.entries) if (e.sig?.key === signer.id) out.set(entryHash(e), e);
    return [...out.values()].filter((e) => e.seq > 0);
  };
  /// Two entries of this device's after one parent, as the stations were brought them: the pair, in words.
  const twins = () => {
    const by = new Map<string, Entry[]>();
    for (const e of fresh()) by.set(e.prev!, [...(by.get(e.prev!) ?? []), e]);
    return [...by.values()].filter((es) => es.length > 1).map((es) => es.map((e) => `${e.kind} ${JSON.stringify(e.body)}`).join(" and "));
  };
  return { r, inner, signer, g0, stations, st, run, settle, fresh, twins, reach };
}

const s3 = { sub: "s3", email: "c@x.com", role: "member" };
const removingPeer = (e: Entry) => e.kind === "device.remove" && (e.body as { id: string }).id === PEER;
/// The words of `core-misc.lock.changedMeanwhile` before what it names.
const changedWords = () => t("core-misc.lock.changedMeanwhile", { what: "\u0000" }).split("\u0000")[0]!;

for (const pair of ["a person's call and a background signer", "two calls at once"] as const)
  test(`${pair}: the stations are never brought two entries of this device after one parent`, async () => {
    const w = await setUp([A]);
    w.st(A).say.delay = 50;
    // A background signer is a Lock with no call's wait (bindPerson's, keepToPerson's, ownLockFor's); a call has one.
    const background = new Lock(w.inner, "ws", "s1", null);
    const call = () => new Lock(w.inner, "ws", "s1", null, { byHand: true, within: asked(w.inner) });
    const first = pair === "two calls at once" ? call() : background;
    const out = await w.run(Effect.all([Effect.result(first.append("member", s3)), Effect.result(call().append("device.remove", { id: PEER }))], { concurrency: 2 }));
    await w.settle();
    assert.deepEqual(w.twins(), [], "two entries after one parent");
    assert.deepEqual(out.map((r) => r._tag), ["Success", "Success"]);
    assert.deepEqual(w.st(A).chain().map((e) => e.kind).sort(), ["device.remove", "genesis", "member"]);
    assert.deepEqual(held(w.inner, "ws")!.entries.map(entryHash), w.st(A).chain().map(entryHash), "both held");
  });

test("a background signer holds a call back no longer than its own bring (TAKEN_MS): the call's wait goes on from there", async () => {
  const w = await setUp([A]);
  // The station takes 20 s over every POST: the background's entry is left to the cloud at TAKEN_MS.
  w.st(A).say.delay = 20_000;
  w.inner.runner.fork(Effect.ignore(new Lock(w.inner, "ws", "s1", null).append("member", s3)));
  await w.r.host.time.pass(100);
  const t0 = w.r.host.nowMs();
  let t1 = 0;
  await w.run(Effect.tap(new Lock(w.inner, "ws", "s1", null, { byHand: true, within: asked(w.inner) }).append("device.remove", { id: PEER }), () => Effect.sync(() => void (t1 = w.r.host.nowMs()))), 30_000);
  const ms = t1 - t0;
  assert.ok(ms >= TAKEN_MS - 300 && ms <= TAKEN_MS + 300, `the call answered after ${ms} ms`);
  assert.ok(ms < TAKEN_MS + ASKED_MS, "its own wait is not added on top: it began with the call");
});

test("refused as not on the head by the only station (another device's entry got there first): read, signed again, taken; the call succeeds once", async () => {
  const w = await setUp([A]);
  const a = w.st(A);
  a.say.before = () => a.add(signedBy(oldKey, a.chain(), 1001, "member", s3));
  const answer = await w.r.ask("lock.removeDevice", { workspace: "ws", device: PEER });
  assert.ok(answer !== undefined);
  assert.deepEqual(a.chain().map((e) => e.kind), ["genesis", "member", "device.remove"], "signed again after the other device's entry");
  assert.equal(a.chain().filter(removingPeer).length, 1, "on the chain once");
  assert.equal(a.chain().at(-1)!.sig?.key, w.signer.id);
  assert.equal(w.fresh().filter(removingPeer).length, 2, "the one that lost and the one signed again");
  assert.deepEqual(held(w.inner, "ws")!.entries.map(entryHash), a.chain().map(entryHash));
});

for (const meanwhile of ["the same done", "the device changed otherwise", "the lock turned off"] as const)
  test(`refused as not on the head, ${meanwhile} meanwhile by another device: ${meanwhile === "the same done" ? "nothing signed, the call succeeds" : "not signed again, the call says what to do"}`, async () => {
    const w = await setUp([A]);
    const a = w.st(A);
    const q = (c: Entry[]) =>
      meanwhile === "the same done" ? signedBy(oldKey, c, 1001, "device.remove", { id: PEER })
      : meanwhile === "the device changed otherwise" ? signedBy(oldKey, c, 1001, "device", { id: PEER, sub: "s1", kind: "web", label: "peer 2" })
      : signedBy(oldKey, c, 1001, "disable", {});
    a.say.before = () => a.add(q(a.chain()));
    const out = await w.r.ask("lock.removeDevice", { workspace: "ws", device: PEER }).then((x) => ({ ok: x }), (e) => ({ error: e as { code: string; message: string } }));
    assert.equal(w.fresh().length, 1, "signed once, not again");
    assert.equal(a.chain().length, 2, "the other device's entry alone after the genesis");
    if (meanwhile === "the same done") assert.ok("ok" in out, JSON.stringify(out));
    else {
      assert.ok("error" in out, JSON.stringify(out));
      assert.equal(out.error.code, "lock_refused");
      assert.ok(out.error.message.startsWith(changedWords()), out.error.message);
      assert.notEqual(out.error.message, FORK);
    }
  });

test("a read moves the chain held off this device's entry (two stations, another branch winning): signed again once, in the background; a second read signs no third", async () => {
  const w = await setUp([A, S]);
  const s = w.st(S);
  s.say.down = true;
  // X, a member put in, taken by A alone.
  await w.run(new Lock(w.inner, "ws", "s1", null).append("member", s3));
  const X = held(w.inner, "ws")!.entries[1]!;
  assert.equal(X.kind, "member");
  // Meanwhile S took another device's removal of THIRD (a removal of a device that signs: it wins at the genesis).
  s.set([w.g0, signedBy(oldKey, [w.g0], 1002, "device.remove", { id: THIRD })]);
  s.say.down = false;
  await w.run(read(w.inner, "ws"));
  await w.settle();
  const h = held(w.inner, "ws")!;
  const members = w.fresh().filter((e) => e.kind === "member");
  assert.equal(members.length, 2, "X, and X signed again");
  const again = members.find((e) => entryHash(e) !== entryHash(X))!;
  assert.equal(again.prev, entryHash(s.chain()[1]!), "after the removal that won");
  assert.deepEqual(s.chain().map((e) => e.kind), ["genesis", "device.remove", "member"]);
  assert.ok(h.entries.some((e) => entryHash(e) === entryHash(again)), "held");
  await w.run(read(w.inner, "ws"));
  await w.settle();
  assert.equal(w.fresh().filter((e) => e.kind === "member").length, 2, "no third");
});

/// This device's `acts`, taken by A alone (S down) after `shared` (taken by both), all losing their place together:
/// S's chain put as `theirs` makes it after what both took (another device's removal of THIRD first, which wins at the
/// parent of the first act: a removal of a device that signs), S up and read, and the background's signing again let
/// settle. T, the lock's third station, is down throughout.
async function lostTogether(acts: [string, unknown][], shared: [string, unknown][] = [], theirs: (base: Entry[], w: Awaited<ReturnType<typeof setUp>>) => Entry[] = (base) => [signedBy(oldKey, base, 1002, "device.remove", { id: THIRD })]) {
  const w = await setUp([A, S, T]);
  w.st(T).say.down = true;
  for (const [kind, body] of shared) await w.run(new Lock(w.inner, "ws", "s1", null).append(kind, body));
  const base = w.st(S).chain();
  assert.equal(base.length, shared.length + 1, "S took what both took");
  w.st(S).say.down = true;
  const mine: Entry[] = [];
  for (const [kind, body] of acts) {
    await w.run(new Lock(w.inner, "ws", "s1", null).append(kind, body));
    mine.push(held(w.inner, "ws")!.entries.at(-1)!);
  }
  assert.deepEqual(w.st(A).chain().map(entryHash), [...base, ...mine].map(entryHash), "A took them all");
  const won = theirs(base, w);
  w.st(S).set([...base, ...won]);
  w.st(S).say.down = false;
  await w.run(read(w.inner, "ws"));
  await w.settle(5_000);
  const h = held(w.inner, "ws")!;
  for (const e of mine) assert.ok(!h.entries.some((x) => entryHash(x) === entryHash(e)), "each act lost its place");
  assert.deepEqual(w.st(S).chain().map(entryHash), h.entries.map(entryHash), "S has what is held");
  assert.deepEqual(w.st(A).chain().map(entryHash), h.entries.map(entryHash), "A has what is held");
  assert.deepEqual(pendingHeld(w.inner, "ws"), [], "nothing pending or failed");
  // (what this device signed again, in the order it signed it)
  const again = h.entries.filter((e) => e.sig?.key === w.signer.id && e.seq > base.length && ![...mine, ...won].some((m) => entryHash(m) === entryHash(e)));
  return { w, h, mine, base, again, after: fold(h.entries) };
}

const putBack = { key: T, name: "st2" };
test("lost together, this device's station taken out then put back: both signed again in that order, the station in at the end", async () => {
  const { after, again } = await lostTogether([["station.remove", { key: T }], ["station", putBack]]);
  assert.deepEqual(again.map((e) => e.kind), ["station.remove", "station"], "both signed again, in the order made");
  assert.ok(after.stations.has(T), "the station put back is in");
});

test("lost together, this device's station put in then taken out: out at the end", async () => {
  const { after, again } = await lostTogether([["station", putBack], ["station.remove", { key: T }]], [["station.remove", { key: T }]]);
  assert.deepEqual(again.map((e) => e.kind), ["station", "station.remove"], "both signed again, in the order made");
  assert.ok(!after.stations.has(T), "the station taken out is out");
});

test("lost together, this device's station out, back, out again: out at the end (an earlier one signed again does not make the third done)", async () => {
  const { after, again } = await lostTogether([["station.remove", { key: T }], ["station", putBack], ["station.remove", { key: T }]]);
  assert.deepEqual(again.map((e) => e.kind), ["station.remove", "station", "station.remove"], "all three signed again, in the order made");
  assert.ok(!after.stations.has(T), "out");
});

test("lost together, a member given a role then taken out by this device: out at the end, nothing failed", async () => {
  const { after, again } = await lostTogether([["member", { ...s3, role: "admin" }], ["member.remove", { sub: "s3" }]], [["member", s3]]);
  assert.equal(again.at(-1)?.kind, "member.remove", "the removal signed again, last");
  assert.ok(!after.members.has("s3"), "out");
});

test("lost, then the same member taken out by this device directly (taken at once, on the branch that won): the stale role is not signed again, the member stays out", async () => {
  const { after, again } = await lostTogether([["member", { ...s3, role: "admin" }]], [["member", s3]], (base, w) => {
    const Y = signedBy(oldKey, base, 1002, "device.remove", { id: THIRD });
    // (signed with this device's own key, later than the role: its later act, not one of those that lost their place)
    const D = w.signer.sign(next("ws", headOf([...base, Y]), w.r.host.nowMs() / 1000 + 1, "member.remove", { sub: "s3" }));
    return [Y, D];
  });
  assert.deepEqual(again, [], "nothing signed again");
  assert.ok(!after.members.has("s3"), "out");
});

test("lost together, another device decided about the same member since: let be, as that device left it", async () => {
  const { after, again } = await lostTogether([["member", { ...s3, role: "admin" }], ["member.remove", { sub: "s3" }]], [["member", s3]], (base) => {
    const Y = signedBy(oldKey, base, 1002, "device.remove", { id: THIRD });
    return [Y, signedBy(oldKey, [...base, Y], 1003, "member", { ...s3, role: "admin" })];
  });
  assert.deepEqual(again, [], "nothing signed again (the role done by the other device, the removal decided otherwise)");
  assert.equal(after.members.get("s3")?.role, "admin", "as the other device left it");
});

// The real-station end-to-end's round 7b (apps/mbui/e2e/locks.ts) as the side run of 2026-11-12 (run 43182403308) had
// it: this device's entry taken by one station alone, that station frozen (no answer, no error), the other taking
// another device's entry at its place, both up again on one chain with this device's entry aside.
for (const how of ["running all along", "closed meanwhile and started again"] as const)
  test(`a station that took this device's entry frozen, another taking another device's at its place, both up again on one chain with it aside (this device ${how}): it reads it, signs its entry again after the head, both take it, and its lock topic answers throughout`, async () => {
    const w = await setUp([A, S]);
    const a = w.st(A);
    const s = w.st(S);
    s.say.down = true;
    await w.run(new Lock(w.inner, "ws", "s1", null).append("member", s3));
    const X = held(w.inner, "ws")!.entries[1]!;
    assert.deepEqual(a.chain().map(entryHash), [w.g0, X].map(entryHash), "A took X");
    a.freeze();
    let inner = w.inner;
    let lock = await w.r.watch({ topic: "lock", workspace: "ws" });
    assert.ok((await lock())?.locked, "the lock topic answers before");
    if (how === "closed meanwhile and started again") {
      await Effect.runPromise(w.inner.data.written);
      w.r.core.close();
      w.r.host.takeEmitted();
    }
    // Y, another device's removal of THIRD, taken by S (it wins over X at the genesis: a removal of a device that signs).
    const Y = signedBy(oldKey, [w.g0], 1002, "device.remove", { id: THIRD });
    s.set([w.g0, Y]);
    s.say.down = false;
    if (how === "running all along") {
      // S up: its link opens and it is read (A asked too, and not answering)
      inner.runner.fork(Effect.ignore(read(inner, "ws")));
      await w.settle();
      assert.ok((await lock())?.locked, "the lock topic answers while A is frozen");
    }
    // A thawed, level with S: Y on its chain, X aside.
    a.keeps([w.g0, Y]);
    assert.deepEqual(a.chain().map(entryHash), [w.g0, Y].map(entryHash), "A on Y's branch");
    assert.deepEqual(a.aside().map(entryHash), [entryHash(X)], "X aside at A");
    a.thaw();
    if (how === "closed meanwhile and started again") {
      const again = await Core.create(w.r.host, { clock: w.r.host.time.clock, sample: 0, wire: () => new HostWire(w.r.host) });
      again.inner.mesh = () => withoutMesh(ME);
      w.reach(again.inner);
      inner = again.inner;
      const ui = again.connect();
      const values = new Map<number, unknown>();
      subscribe(again, ui, 7, { topic: "lock", workspace: "ws" } as never);
      lock = async () => {
        await w.r.host.time.pass(200);
        for (const [, m] of w.r.host.takeEmitted()) {
          const msg = m as Record<string, unknown>;
          if ("value" in msg) values.set(msg.id as number, msg.value);
          else if ("delta" in msg) values.set(msg.id as number, applyOps(values.get(msg.id as number), msg.delta as never));
        }
        return values.get(7) as any;
      };
      assert.ok((await lock())?.locked, "the lock topic answers as it starts");
    }
    // Both told (A's lock moved; S as it is reached again): read.
    inner.runner.fork(Effect.ignore(read(inner, "ws")));
    for (let n = 0; n < 5_000; n += 10) await w.r.host.time.pass(10);
    const members = w.fresh().filter((e) => e.kind === "member");
    assert.equal(members.length, 2, `X, and X signed again: ${members.length}`);
    const XX = members.find((e) => entryHash(e) !== entryHash(X))!;
    assert.equal(XX.prev, entryHash(Y), "signed again after Y");
    for (const [id, st] of [[A, a], [S, s]] as const) assert.deepEqual(st.chain().map(entryHash), [w.g0, Y, XX].map(entryHash), `${id === A ? "A" : "S"} took it`);
    assert.deepEqual(held(inner, "ws")!.entries.map(entryHash), [w.g0, Y, XX].map(entryHash), "held");
    const l = await lock();
    assert.ok(l?.locked, "the lock topic answers after");
  });

test("taken by hash: a station whose answer's head is as far but another entry took none of it (pending, whatever the cloud says)", async () => {
  const w = await setUp([A]);
  const a = w.st(A);
  // A station from before answering what it took by how far its chain goes, its chain at that place another entry.
  const original = a.answer;
  w.inner.stations.requests.call = ((call) => (addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    if (addr.toString() === `ws/${A}` && method === "POST" && path === "/lock") {
      const e = (body as { entries: Entry[] }).entries.at(-1)!;
      return Effect.succeed({ taken: 1, head: { seq: e.seq, hash: "ff".repeat(32), genesis: entryHash(w.g0) } });
    }
    if (addr.toString() === `ws/${A}`) return original(method, path, body);
    return (call as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  })(w.inner.stations.requests.call) as typeof w.inner.stations.requests.call;
  stationReplies(w.r.host, (req) => (req.method === "POST" && /\/v1\/workspaces\/ws\/lock$/.test(new URL(req.url).pathname) ? new Status(503, { error: "unavailable" }) : w.r.cloud.reply(req)));
  const out = await w.run(Effect.result(new Lock(w.inner, "ws", "s1", null).append("member", s3)));
  assert.equal(out._tag, "Success", "not taken: pending");
  assert.equal(held(w.inner, "ws")!.entries.length, 1, "not held");
  assert.deepEqual(pendingHeld(w.inner, "ws").map((x) => x.entry.kind), ["member"]);
});

test("a station on another branch of the lock is not another lock; one of another genesis is", async () => {
  const w = await setUp([A, S, T], [T]);
  w.st(S).say.forks = false;
  // X, a removal of THIRD, taken by A and S; then S on another device's member put in after the genesis (which X beats).
  await w.run(new Lock(w.inner, "ws", "s1", null).append("device.remove", { id: THIRD }));
  w.st(S).set([w.g0, signedBy(oldKey, [w.g0], 1003, "member", s3)]);
  await w.run(read(w.inner, "ws"));
  const h = held(w.inner, "ws")!;
  assert.equal(h.entries.at(-1)!.kind, "device.remove", "X held");
  assert.equal(h.aside?.length, 1, "S's entry aside");
  const rows = lockView(w.inner, "ws").stations as { id: string; protected: boolean }[];
  assert.equal(rows.find((x) => x.id === S)?.protected, true, "S on another branch: protected, to come level");
  assert.equal(rows.find((x) => x.id === T)?.protected, false, "T keeps another lock");
});

test("carrying: a station that lacks what another showed is brought it with keep, once; one that does not say forks is not, nor one keeping no lock or another (it would pin it there again)", async () => {
  const w = await setUp([S, T, U, V, N], [V]);
  const Y = signedBy(oldKey, [w.g0], 1004, "member", s3);
  w.st(S).set([w.g0, Y]);
  w.st(T).say.deaf = true;
  w.st(U).say.forks = false;
  w.st(N).say.none = true;
  await w.run(read(w.inner, "ws"));
  assert.deepEqual(held(w.inner, "ws")!.entries.map(entryHash), [w.g0, Y].map(entryHash), "the lock held as S keeps it");
  await w.settle(500);
  const keeps = (id: string) => w.st(id).posts.filter((p) => p.keep);
  assert.equal(keeps(T).length, 1, "T brought it");
  assert.deepEqual(keeps(T)[0]!.entries.map(entryHash), [w.g0, Y].map(entryHash));
  assert.equal(keeps(U).length, 0, "U says no forks");
  assert.equal(keeps(S).length, 0, "S lacks nothing");
  assert.equal(keeps(V).length, 0, "V keeps another lock");
  assert.equal(keeps(N).length, 0, "N keeps no lock");
  await w.run(read(w.inner, "ws"));
  await w.settle(500);
  assert.equal(keeps(T).length, 1, "once for what is kept");
});

test("carrying a person's own lock: a station of theirs that lacks what another showed is brought the chain with keep, once; one that does not say forks is not", async () => {
  const w = await setUp([S, T, U]);
  w.st(U).say.forks = false;
  w.st(S).say.takesPerson = true;
  await w.run(read(w.inner, "ws"));
  const personal = w.inner.adb.personal();
  await w.run(personal.open("s1", "why"));
  const pg = personal.entries("s1")[0]!;
  assert.ok(pg !== undefined, "begun");
  // Another entry of the person's lock S took (signed with this device's key, as one of its own would be).
  const seed = (await w.run(w.r.host.secureGet!("personal-signer", { user: true })))!;
  const e = { v: 1 as const, ws: "person:s1", seq: 1, prev: entryHash(pg), at: 1_800_000_000, kind: "device", body: { key: `ed25519:${"77".repeat(32)}`, id: "77".repeat(32), label: "phone" } };
  const pY = { ...e, sig: { key: personal.chain("s1")!.devices.keys().next().value!, alg: "Ed25519" as const, sig: hex(ed25519.sign(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(e as Entry))]), seed)) } } as Entry;
  w.st(S).say.person = [pg, pY];
  w.st(T).say.person = [pg];
  w.st(U).say.person = [pg];
  await w.run(personal.refresh("s1"));
  await w.settle(500);
  assert.deepEqual(personal.entries("s1").map(entryHash), [pg, pY].map(entryHash), "pinned");
  const keeps = (id: string) => w.st(id).personPosts.filter((p) => p.keep);
  assert.equal(keeps(T).length, 1, "T brought it");
  assert.deepEqual(keeps(T)[0]!.chain.map(entryHash), [pg, pY].map(entryHash));
  assert.equal(keeps(U).length, 0, "U says no forks");
  await w.run(personal.refresh("s1"));
  await w.settle(500);
  assert.equal(keeps(T).length, 1, "once");
});
