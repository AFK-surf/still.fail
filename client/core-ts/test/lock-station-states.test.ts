// The workspace lock as held after a read, by the states a second station of the workspace can be in (#5540: a station
// the lock does not name, keeping none, read alone, had the device let go of the lock). The world: `ws`, its view
// listing A and S; lock L1 (its genesis this device's, which is in it), which names A, A keeping it always. Each case:
// S in one state × how the device reads × what it held before, and what it holds after.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next, readHead } from "../src/lock.ts";
import { get, utf8 } from "../src/util.ts";
import { OTHERS_MS, TAKEN_MS, held, read } from "../src/views/lock.ts";
import { ME, elsewhere, genesis, grant, rig, unhex } from "./lock-rig.ts";
import { stationReplies } from "./station-fixture.ts";

const A = "aa".repeat(32);
const S = "bb".repeat(32);
const OLD = "ee".repeat(32);
const THIRD = "ef".repeat(32);

const STATES = [
  "unnamed-none", "named-none", "named-other", "unnamed-other", "old", "silent", "refuses", "named-behind", "named-ahead", "named-forked",
] as const;
type State = (typeof STATES)[number];
/// Whether L1 names S. (Those from before, asleep or refusing: named, as a station that keeps the lock is.)
const named = (s: State) => !s.startsWith("unnamed-");

const headOf = (chain: Entry[]): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });

/// A station of the lock as station/src/mesh/serve.ts answers it (lock-stations.test.ts's): its chain; `old`, one from
/// before, which serves none of it; `refuse`, one refusing this device.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const say = { old: false, refuse: false };
  const head = (): Head => headOf(chain);
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.refuse) return Effect.fail(new CoreError("lock_unconfirmed", "this device is not on the lock its person bound in this workspace"));
    if (say.old) return path.startsWith("/lock?") || path === "/lock" ? Effect.succeed({ head: head(), entries: [], takes: ["person"] }) : Effect.fail(new CoreError("http_404", "no route", 404));
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: head(), entries: chain.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      for (const e of (body as { entries?: Entry[] }).entries ?? []) if (e.seq === chain.length) chain.push(e);
      return Effect.succeed({ taken: 1, head: head() });
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    if (method === "POST" && path === "/lock/person") return Effect.succeed({ taken: 1 });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, say, answer };
}

/// A station keeping no lock (one the lock does not name, not protected yet; or one reset on its machine).
function unprotected(method: string, path: string): Effect.Effect<unknown, CoreError> {
  if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) return Effect.succeed({ head: null, entries: [], takes: ["person"], serves: ["person", "devices", "told"] });
  if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
  if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
  return Effect.fail(new CoreError("http_404", "no route", 404));
}

/// The world for S in `state`, the view listing the stations in `order`. S begins level (keeping L1 as A does where L1
/// names it, none where it does not: what a healthy S is) and is put in its state by `s.put()`, after the device's first
/// read: the device holds L1 then as any device reading a healthy workspace would, and S has answered once (one that
/// never answered is not waited for, answersOf, which would make `silent` another case).
/// `says`: what the workspace's view says of the lock, where the device will hold none (readLockOf chooses by it): `A`,
/// A's head, the cloud level with A as the real one is (it is sent every entry); `none`, no lock; `unkept`, a lock no
/// station keeps. Not given: the rig's (L1's genesis), as a device holding L1 never reads it.
async function setUp(state: State, order: "A first" | "S first", says?: "A" | "none" | "unkept") {
  const g = grant();
  let me: Signer | null = null;
  const stations = named(state) ? [{ key: A, name: "a" }, { key: S, name: "s" }] : [{ key: A, name: "a" }];
  // (OLD, another app of the owner's that signs: what S went another way with is its, not this device's, which would
  // sign its own again: lock-signs-again.test.ts. THIRD, one more, whose removal is A's entry: a removal of a device
  // that signs, it beats S's at the genesis by the rules' second step)
  const old = elsewhere();
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, stations, g.keys, ME, [{ id: OLD, sub: "s1", kind: "app", label: "old", sign_key: old.id }, { id: THIRD, sub: "s1", kind: "app", label: "third", sign_key: `ed25519:${"77".repeat(32)}` }]) }), undefined, order === "A first" ? [A, S] : [S, A]);
  const inner = r.core.inner;
  const signer = me! as Signer;
  const g1 = r.cloud.chains.get("ws")![0]!;
  // A keeps L1 one entry past its genesis (so that S can be behind it).
  const a = station(g1);
  a.chain.push(signer.sign(next("ws", headOf(a.chain), 1001, "device.remove", { id: THIRD })));
  const aChain = [...a.chain];
  // The chains S may keep: L2 (another genesis, naming S), L1 one shorter, one longer, and forked at A's last entry.
  const l2 = [genesis("ws", elsewhere(), true, [{ key: S, name: "s" }], g.keys, ME, [])];
  const behind = [g1];
  const ahead = [...aChain, signer.sign(next("ws", headOf(aChain), 1003, "member", { sub: "s4", email: "d@x.com", role: "member" }))];
  const fork = next("ws", headOf([g1]), 1002, "member", { sub: "s9", email: "x@x.com", role: "member" });
  const forked = [g1, { ...fork, sig: { key: old.id, alg: "Ed25519" as const, sig: old.signBytes(new Uint8Array([...utf8("stillfail-lock/1 sig\0"), ...unhex(entryHash(fork))])) } }];
  const sSt = station(g1);
  sSt.chain.splice(0, 1, ...aChain);
  const s = {
    now: "level" as State | "level",
    put() {
      s.now = state;
      const keep = state === "named-other" || state === "unnamed-other" ? l2 : state === "named-behind" ? behind : state === "named-ahead" ? ahead : state === "named-forked" ? forked : aChain;
      sSt.chain.splice(0, sSt.chain.length, ...keep);
      sSt.say.old = state === "old";
      sSt.say.refuse = state === "refuses";
    },
  };
  const cloud = { asked: [] as string[] };
  stationReplies(r.host, (req) => {
    if (!/\/v1\/workspaces\/ws\/(lock|devices)/.test(req.url)) return r.cloud.reply(req);
    cloud.asked.push(`${req.method} ${req.url.replace(/^.*\/v1\/workspaces\/ws/, "")}`);
    return r.cloud.reply(req);
  });
  const atA: string[] = [];
  const atS: string[] = [];
  // How long A takes to answer a read of its lock (on the test's clock): 0, at once.
  const slow = { a: 0 };
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return (atA.push(`${method} ${path}`), slow.a > 0 ? Effect.andThen(Effect.sleep(slow.a), a.answer(method, path, body)) : a.answer(method, path, body));
    if (ws === "ws" && id === S) {
      atS.push(`${method} ${path}`);
      if (s.now === "level") return named(state) ? sSt.answer(method, path, body) : unprotected(method, path);
      if (s.now === "silent") return Effect.never;
      if (s.now === "unnamed-none" || s.now === "named-none") return unprotected(method, path);
      return sSt.answer(method, path, body);
    }
    return (original as (...x: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let failed: unknown;
    inner.runner.fork(Effect.match(e, { onSuccess: () => { done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
  };
  // A read that may never end (S silent, asked alone): let run until it does or its deadline (TAKEN_MS) passed.
  const settle = async (e: Effect.Effect<unknown, any>) => {
    let done = false;
    inner.runner.fork(Effect.ensuring(Effect.ignore(e), Effect.sync(() => void (done = true))));
    for (let t = 0; t < TAKEN_MS + 500 && !done; t += 10) await r.host.time.pass(10);
    await r.host.time.pass(100);
  };
  // (its key of its person's lock made before, as lock-stations.test.ts: the person's lock begun meanwhile is not the point)
  await run(inner.adb.personal().makeKey());
  if (says === "A") r.cloud.chains.set("ws", aChain);
  const UNKEPT = "ee".repeat(32);
  if (says !== undefined) inner.data.update({ topic: "workspace", workspace: "ws" }, (v) => ({ ...(v as object), lock: says === "A" ? headOf(aChain) : says === "none" ? null : { seq: 0, hash: UNKEPT, genesis: UNKEPT } }));
  // (the view's head, as each case's precondition says)
  const viewSays = () => readHead(get(inner.data.shared({ topic: "workspace", workspace: "ws" }), "lock"));
  // The chain each lock's genesis and each S chain's last entry is, for what a failure says was held.
  const names = new Map<string, string>([[entryHash(g1), "L1"], [entryHash(l2[0]!), "L2"], [entryHash(forked[1]!), "fork"], [entryHash(ahead.at(-1)!), "S-ahead"], [entryHash(aChain.at(-1)!), "A-last"]]);
  const said = () => {
    const h = held(inner, "ws");
    if (!h?.head) return h ? "none" : "no record";
    return `seq ${h.head.seq} of ${names.get(h.head.genesis) ?? h.head.genesis.slice(0, 8)}, last ${names.get(h.head.hash) ?? h.head.hash.slice(0, 8)}`;
  };
  const holds = (chain: Entry[], why: string) => {
    const h = held(inner, "ws");
    assert.deepEqual(h?.head ?? null, headOf(chain), `${why}: held ${said()}`);
    assert.deepEqual(h?.entries, chain, `${why}: held ${said()}`);
    assert.notEqual(h?.head?.genesis, entryHash(l2[0]!), "never L2");
    assert.ok(!h?.entries.some((e) => entryHash(e) === entryHash(forked[1]!)), "never the forked entry");
  };
  const none = (why: string) => assert.equal(held(inner, "ws")?.head ?? null, null, `${why}: held ${said()}`);
  // S alone, as its link opens again (each part read again after an absence, station/sync.ts), or as it tells its lock moved.
  const opened = (id: string) => settle(Effect.all(inner.stations.also.filter((p) => p.resume).map((p) => Effect.ignore(p.read(`ws/${id}`))), { discard: true }));
  const told = async (id: string, head: Head | null) => {
    inner.stations.onEvent(`ws/${id}`, "lock", JSON.stringify({ workspace: "ws", head }));
    for (let t = 0; t < OTHERS_MS + 500; t += 10) await r.host.time.pass(10);
  };
  return { r, inner, s, sSt, aChain, ahead, behind, l2, cloud, atA, atS, run, opened, told, holds, none, said, viewSays, slow };
}

const READS = ["all", "alone-told", "alone-opened"] as const;
const ORDERS = ["A first", "S first"] as const;
/// A's reads of the lock (GET /lock?after=…), not the probes of how far it goes (`after=999999999`, readStations, bindPerson).
const lockReads = (at: string[]) => at.filter((x) => x.startsWith("GET /lock?after=") && !x.endsWith("=999999999"));

// The device holds L1, read of A with S level; S put in its state; read again. What it holds is A's L1, but for S
// keeping it longer (taken once S was read); the cloud not asked where A answered.
for (const state of STATES)
  for (const how of READS)
    for (const order of how === "all" ? ORDERS : (["A first"] as const))
      test(`S ${state}, read ${how}, device holds L1, ${order}`, async () => {
        const w = await setUp(state, order);
        await w.run(read(w.inner, "ws"));
        await w.r.host.time.pass(100);
        w.holds(w.aChain, "after the first read");
        w.s.put();
        w.cloud.asked.length = 0;
        w.atA.length = 0;
        if (how === "all") await w.run(read(w.inner, "ws"));
        else if (how === "alone-told") await w.told(S, state === "unnamed-none" || state === "named-none" ? null : headOf(w.sSt.chain));
        else await w.opened(S);
        await w.r.host.time.pass(100);
        w.holds(state === "named-ahead" ? w.ahead : w.aChain, "after the read");
        if (how === "all") assert.deepEqual(w.cloud.asked.filter((x) => x.startsWith("GET /lock")), [], "the cloud asked though A answered");
        // Read alone, S's word is all that is asked, but where it keeps none and L1 names it: then A is asked too (readLockOf).
        else assert.equal(lockReads(w.atA).length > 0, state === "named-none", `A asked: ${w.atA.join()}`);
      });

// The device holds none, the cloud's view naming L1 (#5540's device), read of all the stations.
for (const state of STATES)
  for (const order of ORDERS)
    test(`S ${state}, read all, device holds none, ${order}`, async () => {
      const w = await setUp(state, order, "A");
      await w.run(read(w.inner, "ws"));
      await w.r.host.time.pass(100);
      w.s.put();
      w.inner.data.put("lock", "ws", { head: null, entries: [] });
      w.none("let go");
      assertViewOnA(w);
      await w.run(read(w.inner, "ws"));
      await w.r.host.time.pass(100);
      // The longer of the two where both keep L1; L1 as A keeps it where S keeps another or went another way.
      w.holds(state === "named-ahead" ? w.ahead : w.aChain, "after the read");
    });

// The device holds none, the cloud's view naming L1: S's link opens again, then A's. With none held every station is
// read as one link opens (readLockOf), so what is held after S's is what is held at the end: A's opening changes nothing.
for (const state of STATES)
  test(`S ${state}, read alone-opened S then A, device holds none, A first`, async () => {
    const w = await setUp(state, "A first", "A");
    await w.run(read(w.inner, "ws"));
    await w.r.host.time.pass(100);
    w.s.put();
    w.inner.data.put("lock", "ws", { head: null, entries: [] });
    w.none("let go");
    assertViewOnA(w);
    const end = state === "named-ahead" ? w.ahead : w.aChain;
    w.atA.length = 0;
    await w.opened(S);
    assert.ok(lockReads(w.atA).length > 0, `A asked as S's link opened: ${w.atA.join()}`);
    w.holds(end, "after S alone");
    await w.opened(A);
    w.holds(end, "after A alone");
  });

// Every link opening again at once (the network back): one read of every station, not one for each link.
test("S unnamed-none, links of S and A open in the same tick, device holds none: A asked once", async () => {
  const w = await setUp("unnamed-none", "A first", "A");
  await w.run(read(w.inner, "ws"));
  await w.r.host.time.pass(100);
  w.s.put();
  w.inner.data.put("lock", "ws", { head: null, entries: [] });
  assertViewOnA(w);
  w.atA.length = 0;
  // (A slow to answer, as over a network: the first read is still asking it as the second link opens. Answered at
  // once, the first read is over, the lock held, before the second begins, which then is A's own read of the lock held)
  w.slow.a = 50;
  const opening = (id: string) => w.inner.stations.also.filter((p) => p.resume).map((p) => Effect.ignore(p.read(`ws/${id}`)));
  await w.run(Effect.all([...opening(S), ...opening(A)], { concurrency: "unbounded", discard: true }));
  await w.r.host.time.pass(100);
  w.holds(w.aChain, "after both opened");
  assert.equal(lockReads(w.atA).length, 1, w.atA.join());
});

// The link that asked first closing again as that read runs (its part's read interrupted, station/sync.ts) does not
// end the read: it is the core's, and the other link's read, waiting on it, has the lock of it.
test("S unnamed-none, S's link opens then closes as every station is read, A's link waiting on that read, device holds none: the read goes on", async () => {
  const w = await setUp("unnamed-none", "A first", "A");
  await w.run(read(w.inner, "ws"));
  await w.r.host.time.pass(100);
  w.s.put();
  w.inner.data.put("lock", "ws", { head: null, entries: [] });
  assertViewOnA(w);
  w.atA.length = 0;
  w.slow.a = 50;
  const opening = (id: string) => Effect.all(w.inner.stations.also.filter((p) => p.resume).map((p) => Effect.ignore(p.read(`ws/${id}`))), { discard: true });
  const first = w.inner.runner.fork(opening(S));
  await w.r.host.time.pass(10);
  let done = false;
  w.inner.runner.fork(Effect.ensuring(opening(A), Effect.sync(() => void (done = true))));
  await w.r.host.time.pass(10);
  assert.equal(lockReads(w.atA).length, 1, `A asked by the first read: ${w.atA.join()}`);
  await w.inner.runner.run(Fiber.interrupt(first));
  await w.r.host.time.passUntil(500, () => done);
  assert.ok(done, "A's link's read ended");
  await w.r.host.time.pass(100);
  w.holds(w.aChain, "after the first asker went away");
  assert.equal(lockReads(w.atA).length, 1, w.atA.join());
});

// What the view says decides only where it names a lock a station keeps.
for (const order of ORDERS)
  test(`S named-other, read all, device holds none, view names no lock, ${order}`, async () => {
    // Nothing tells L1 and L2 apart then: the first station's in the stations' order is held (arbitrary, as any would be).
    const w = await setUp("named-other", order, "none");
    await w.run(read(w.inner, "ws"));
    await w.r.host.time.pass(100);
    w.s.put();
    w.inner.data.put("lock", "ws", { head: null, entries: [] });
    assert.equal(w.viewSays(), null);
    await w.run(read(w.inner, "ws"));
    await w.r.host.time.pass(100);
    const h = held(w.inner, "ws");
    const first = order === "A first" ? w.aChain : w.l2;
    assert.deepEqual(h?.head ?? null, headOf(first), `held ${w.said()}`);
    assert.deepEqual(h?.entries, first, `held ${w.said()}`);
  });

test("S unnamed-none, read all, device holds none, view names a lock no station keeps, A first", async () => {
  // A preference, never a refusal: what the stations keep is held still.
  const w = await setUp("unnamed-none", "A first", "unkept");
  await w.run(read(w.inner, "ws"));
  await w.r.host.time.pass(100);
  w.s.put();
  w.inner.data.put("lock", "ws", { head: null, entries: [] });
  assert.equal(w.viewSays()?.genesis, "ee".repeat(32));
  await w.run(read(w.inner, "ws"));
  await w.r.host.time.pass(100);
  w.holds(w.aChain, "after the read");
});

/// The view's head is A's (the precondition of the cases deciding by it).
function assertViewOnA(w: { viewSays(): Head | null; aChain: Entry[] }) {
  const says = w.viewSays();
  assert.equal(says?.hash, headOf(w.aChain).hash, "the view's head is A's");
  assert.equal(says?.genesis, headOf(w.aChain).genesis, "the view's genesis is L1's");
}
