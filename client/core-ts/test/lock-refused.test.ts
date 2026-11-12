// An entry a station of the lock refuses on the lock it keeps (views/lock.ts `Lock.append`, `#refusedBy`): its 409
// (station/src/mesh/serve.ts: another entry at the place, or the lock's rules), with no station taking it. Within the
// call: the station's lock is read again, and where it moved on (another device's entry at the place) the entry is signed
// again after it and the call answers well; where it did not (the lock's rules), the call fails, `lock_refused` in the
// station's words, and the cloud is not sent the entry. Past the call's wait, the cloud took the entry and the station
// refused it after: what this device held past what a station had shown it (`shown`) gives way to the station's chain,
// and its own entry is signed again after it, unless the station's is about the same thing. A station keeping another
// lock, or refusing this device, is as before: the entry goes to the cloud. A station that takes it wins over another's
// refusal, whichever comes first. Each case in a workspace of its own, locked, this device signing for its owner, on the
// test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { HostWire } from "../src/station/wire.ts";
import { ASKED_MS, held, lockView, read } from "../src/views/lock.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, elsewhere, genesis, grant, rig, withoutMesh } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

const A = "aa".repeat(32);
const B = "bb".repeat(32);
/// A tablet of the member s2's, on the lock: what a later call takes out.
const TABLET = "ce".repeat(32);
/// What a station says as it refuses an entry that disagrees with its chain (station/src/cloud/state.ts `takeLock`).
const FORK = "the entry disagrees with this station's lock (a fork)";
/// What it says as the lock's rules refuse one (rules/src/lock/lock.mbt).
const RULES = "members remove only their own devices";
/// How long a call is given before it is said to have no answer.
const LIMIT_MS = 30_000;

type Rig = Awaited<ReturnType<typeof rig>>;

/// A station of the lock as station/src/mesh/serve.ts answers it, its refusals as the core has them (requests.ts
/// `httpError`: the code, the words, the status). `pending`: other devices' entries, from the place this one signs,
/// that reach it as this device's does (it read the chain before); `other`: the chain of another lock it keeps since;
/// `refuse`: what it answers every POST /lock; `delay`: how long it takes over a POST; `silent`: it answers no POST;
/// `down`: it answers nothing (not reached). `posts`: the POSTs of the lock it was brought.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const say = { pending: null as Entry | Entry[] | null, other: null as Entry[] | null, refuse: null as CoreError | null, delay: 0, silent: false, down: false };
  const seen = { posts: 0 };
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c.at(-1)!), genesis: entryHash(c[0]!) });
  const fork = () => Effect.fail(new CoreError("http_409", FORK, 409));
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.down) return Effect.fail(new CoreError("network", "not reached"));
    const kept = say.other ?? chain;
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: headOf(kept), entries: kept.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      if (Array.isArray((body as { entries?: unknown })?.entries)) seen.posts++;
      if (say.silent) return Effect.never;
      const take = Effect.suspend((): Effect.Effect<unknown, CoreError> => {
        if (say.refuse !== null) return Effect.fail(say.refuse);
        if (say.pending !== null) {
          chain.push(...(Array.isArray(say.pending) ? say.pending : [say.pending]));
          say.pending = null;
        }
        if (say.other !== null) return fork();
        let taken = 0;
        for (const e of (body as { entries: Entry[] }).entries) {
          if (e.seq < chain.length) {
            if (entryHash(chain[e.seq]!) !== entryHash(e)) return fork();
          } else if (e.seq === chain.length) {
            if (e.prev !== entryHash(chain.at(-1)!)) return fork();
            chain.push(e);
            taken++;
          }
        }
        return Effect.succeed({ taken, head: headOf(chain) });
      });
      return say.delay > 0 ? Effect.andThen(Effect.sleep(say.delay), take) : take;
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    if (method === "POST" && path === "/lock/person") return Effect.succeed({ taken: 1 });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, say, seen, head: () => headOf(chain), answer };
}

/// A locked workspace `ws` (s1 the owner, this device its app; s2 a member with a phone and a tablet), its stations
/// `ids` serving it, the lock read and held. `cloud.posted`: the entries the cloud was sent since; `cloud.hang`: its
/// POST /lock left unanswered. `restart()`: the app started anew on the same host (its database, its keys), the
/// stations reached as before.
async function setUp(ids: string[]) {
  const g = grant();
  let me: Signer | null = null;
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, ids.map((key, i) => ({ key, name: `s${i}` })), g.keys, ME, [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }, { id: TABLET, sub: "s2", kind: "app", label: "iPad" }]) }), undefined, ids);
  const stations = new Map(ids.map((id) => [id, station(r.cloud.chains.get("ws")![0]!)]));
  const reach = (inner: Rig["core"]["inner"]) => {
    const original = inner.stations.requests.call.bind(inner.stations.requests);
    inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
      const [ws, id] = addr.toString().split("/");
      const st = ws === "ws" ? stations.get(id!) : undefined;
      if (st !== undefined && path.startsWith("/lock")) return st.answer(method, path, body);
      return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
    }) as typeof inner.stations.requests.call;
  };
  reach(r.core.inner);
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let failed: unknown;
    let out: X | undefined;
    r.core.inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    for (let i = 0; i < 500 && !done; i++) await r.host.time.pass(10);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its key of its person's lock made before, as lock-stations.test.ts's setUp does)
  await run(r.core.inner.adb.personal().makeKey());
  await run(read(r.core.inner, "ws"));
  assert.equal(held(r.core.inner, "ws")?.head?.seq, 0);
  const cloud = { posted: 0, hang: false };
  stationLater(r.host, (req) => {
    if (req.method !== "POST" || new URL(req.url).pathname !== "/v1/workspaces/ws/lock") return undefined;
    cloud.posted++;
    return cloud.hang ? new Promise(() => {}) : undefined;
  });
  // Another device's entry at the place this one signs next (`after`, more of them after the first).
  const another = (after: Entry[] = stations.get(ids[0]!)!.chain, kind = "member", body: unknown = { sub: "s3", email: "c@x.com", role: "member" }) =>
    me!.sign(next("ws", { seq: after.length - 1, hash: entryHash(after.at(-1)!), genesis: entryHash(after[0]!) }, 1001 + after.length, kind, body));
  const restart = async () => {
    await Effect.runPromise(r.core.inner.data.written);
    await r.core.close();
    r.host.takeEmitted();
    r.core = await Core.create(r.host, { clock: r.host.time.clock, sample: 0, wire: () => new HostWire(r.host) });
    r.core.inner.mesh = () => withoutMesh(ME);
    reach(r.core.inner);
    await r.host.time.pass(500);
  };
  return { r, stations, cloud, another, run, restart, inner: () => r.core.inner };
}

/// Steps the clock 10 ms at a time until `done()` says, or LIMIT_MS: the time it took, or null.
async function until(r: Rig, done: () => boolean): Promise<number | null> {
  const t0 = r.host.nowMs();
  while (r.host.nowMs() - t0 < LIMIT_MS) {
    await r.host.time.pass(10);
    if (done()) return r.host.nowMs() - t0;
  }
  return null;
}

/// A call made as the app makes it, on its own connection: how long it took (null: none by LIMIT_MS), its answer.
let callId = 9000;
async function timedCall(r: Rig, name: string, params: Record<string, unknown>) {
  const ui = r.core.connect();
  const id = ++callId;
  let answer: Record<string, unknown> | undefined;
  call(r.core, ui, id, name, params);
  const ms = await until(r, () => {
    for (const [, m] of r.host.takeEmitted()) {
      const msg = m as Record<string, unknown>;
      if (msg.id === id && ("ok" in msg || "error" in msg)) answer = msg;
    }
    return answer !== undefined;
  });
  return { ms, answer };
}

const removePhone = (r: Rig) => timedCall(r, "lock.removeDevice", { workspace: "ws", device: PHONE });
const removeTablet = (r: Rig) => timedCall(r, "lock.removeDevice", { workspace: "ws", device: TABLET });
const said = (what: string, ms: number | null, answer: Record<string, unknown> | undefined) => `${what}: after ${ms} ms, ${JSON.stringify(answer ?? null)}`;
/// The call refused in the station's words.
function refused(what: string, ms: number | null, answer: Record<string, unknown> | undefined, words = FORK) {
  assert.ok(answer !== undefined && "error" in answer, said(what, ms, answer));
  const e = answer.error as { code: string; message: string };
  assert.deepEqual([e.code, e.message], ["lock_refused", words], said(what, ms, answer));
}
const removes = (id: string) => (e: Entry) => e.kind === "device.remove" && (e.body as { id: string }).id === id;
const removedLast = (c: Entry[]) => removes(PHONE)(c.at(-1)!);
/// A chain as a failure says it: each entry's place, kind and what it is of, and whether it follows the one before.
const shown = (c: Entry[] | undefined) =>
  (c ?? []).map((e, i) => `${e.seq}:${e.kind}${(e.body as { id?: string; sub?: string })?.id ? `(${(e.body as { id: string }).id.slice(0, 4)})` : (e.body as { sub?: string })?.sub ? `(${(e.body as { sub: string }).sub})` : ""}${i > 0 && e.prev !== entryHash(c![i - 1]!) ? "!unlinked" : ""}`).join(" ");
const protectedOf = (inner: Rig["core"]["inner"], id: string) => (lockView(inner, "ws") as { stations: { id: string; protected: boolean }[] }).stations.find((s) => s.id === id)?.protected;

test("P1: an entry the lock's station refuses inside the call's wait (another device's at its place) is signed again after it: the call answers well, the station keeps both", async (t) => {
  const { r, stations, cloud, another, inner } = await setUp([A]);
  const st = stations.get(A)!;
  st.say.pending = another();
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`answered after ${ms} ms; the station keeps ${shown(st.chain)}; posts ${st.seen.posts}`);
  assert.ok(answer !== undefined && "ok" in answer, said("removeDevice", ms, answer));
  assert.ok(ms! <= ASKED_MS, `answered after ${ms} ms`);
  assert.deepEqual([st.chain.length, st.chain[1]!.kind], [3, "member"], `the station keeps ${shown(st.chain)}`);
  assert.ok(removedLast(st.chain) && st.chain[2]!.prev === entryHash(st.chain[1]!), "signed again after the other device's entry, taken by the station");
  assert.equal(st.seen.posts, 2, "one POST more");
  assert.deepEqual(held(inner(), "ws")!.entries.map(entryHash), st.chain.map(entryHash), "held as the station keeps it");
  // (the station took it: the cloud is sent it behind, the one refused never)
  await r.host.time.pass(500);
  assert.ok(!r.cloud.chains.get("ws")!.some((e) => e.seq === 1 && removes(PHONE)(e)), "the cloud never sent the refused entry");
  void cloud;
});

test("P1, the cloud's POST unanswered: the call answers at once, the cloud not waited on", async (t) => {
  const { r, stations, cloud, another } = await setUp([A]);
  const st = stations.get(A)!;
  st.say.pending = another();
  cloud.hang = true;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`answered after ${ms} ms`);
  assert.ok(answer !== undefined && "ok" in answer, said("removeDevice, the cloud's POST unanswered", ms, answer));
  assert.ok(ms! <= 50, `answered after ${ms} ms`);
  assert.ok(removedLast(st.chain) && st.chain.length === 3);
});

test("refused by the lock's rules (no other entry at the place): the call fails as before, in the station's words, and is not signed again", async (t) => {
  const { r, stations, cloud } = await setUp([A]);
  const st = stations.get(A)!;
  st.say.refuse = new CoreError("http_409", RULES, 409);
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`refused after ${ms} ms, posts ${st.seen.posts}`);
  refused("removeDevice, refused by the rules", ms, answer, RULES);
  await r.host.time.pass(5_000);
  assert.equal(st.seen.posts, 1, "brought once: what is held did not move, nothing signed again");
  assert.equal(cloud.posted, 0, "the cloud was not sent the entry");
  // Pressed again: refused again, once more brought, no loop.
  const again = await removePhone(r);
  refused("again", again.ms, again.answer, RULES);
  await r.host.time.pass(5_000);
  assert.equal(st.seen.posts, 2);
});

test("a station refusing for another reason (another lock kept since; this device not let in) is as before: the cloud takes the entry", async (t) => {
  for (const why of ["another lock", "lock_unconfirmed"]) {
    const { r, stations, cloud } = await setUp([A]);
    const st = stations.get(A)!;
    if (why === "another lock") st.say.other = [genesis("ws", elsewhere(), false)];
    else st.say.refuse = new CoreError("lock_unconfirmed", "this device is not on the lock its person bound in this workspace", 403);
    const { ms, answer } = await removePhone(r);
    t.diagnostic(`${why}: answered after ${ms} ms`);
    assert.ok(answer !== undefined && "ok" in answer, said(why, ms, answer));
    assert.equal(cloud.posted, 1, why);
    const kept = r.cloud.chains.get("ws")!;
    assert.ok(kept.length === 2 && removedLast(kept), `${why}: on the cloud's chain`);
  }
});

test("one station takes the entry, another refuses it: the call succeeds, the cloud sent it behind", async (t) => {
  const { r, stations, cloud, another } = await setUp([A, B]);
  const b = stations.get(B)!;
  b.say.pending = another();
  b.say.delay = 100;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`answered after ${ms} ms`);
  assert.ok(answer !== undefined && "ok" in answer, said("one took it", ms, answer));
  assert.ok(removedLast(stations.get(A)!.chain), "A took it");
  await r.host.time.pass(500);
  assert.equal(cloud.posted, 1, "sent to the cloud behind");
  assert.ok(removedLast(r.cloud.chains.get("ws")!));
});

test("one station refuses the entry, another takes it a moment after: the call succeeds, the refusal not its answer", async (t) => {
  const { r, stations, another } = await setUp([A, B]);
  const a = stations.get(A)!;
  a.say.pending = another();
  stations.get(B)!.say.delay = 100;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`answered after ${ms} ms`);
  assert.ok(answer !== undefined && "ok" in answer, said("one took it after the other refused", ms, answer));
  assert.ok(removedLast(stations.get(B)!.chain), "B took it");
  assert.ok(ms! >= 100 && ms! <= 150, `answered after ${ms} ms`);
});

test("within a call's wait, one station refusing at 1 s and the other silent: past the wait the entry is signed again after the refusing station's lock, which takes it", async (t) => {
  const { r, stations, another } = await setUp([A, B]);
  const a = stations.get(A)!;
  a.say.pending = another();
  a.say.delay = 1_000;
  stations.get(B)!.say.silent = true;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`answered after ${ms} ms`);
  assert.ok(answer !== undefined && "ok" in answer, said("removeDevice, B silent", ms, answer));
  // (the first wait ends at ASKED_MS, B silent; signed again then, the cloud asked too past the wait, A taking it
  // after its own delay)
  assert.ok(ms! >= ASKED_MS && ms! <= ASKED_MS + 1_000 + 50, `answered after ${ms} ms`);
  await r.host.time.pass(1_500);
  assert.ok(removedLast(a.chain) && a.chain.length === 3, `A keeps ${shown(a.chain)}`);
  assert.ok(!r.cloud.chains.get("ws")!.some((e) => e.seq === 1 && removes(PHONE)(e)), "the cloud never sent the refused entry");
});

/// P2: the station keeping this lock silent past the call's wait with another device's entry (`others`, from the place
/// this one signs) reaching it first: the cloud takes this device's at the wait's end and the call answers well; the
/// station refuses it at 5 s. What is held and shown then (`then`: the chains, and whether the station is shown
/// protected), and what a later call that signs does after that (`later`: the tablet taken out).
async function p2(t: { diagnostic(s: string): void }, others: (w: Awaited<ReturnType<typeof setUp>>) => Entry[]) {
  const w = await setUp([A]);
  const st = w.stations.get(A)!;
  st.say.pending = others(w);
  st.say.delay = 5_000;
  const { ms, answer } = await removePhone(w.r);
  assert.ok(answer !== undefined && "ok" in answer, said("removeDevice, the station refusing at 5 s", ms, answer));
  assert.ok(ms! >= ASKED_MS && ms! <= ASKED_MS + 50, `answered after ${ms} ms`);
  assert.equal(w.cloud.posted, 1, "the cloud sent it at the wait's end");
  // (what it is brought from now on it answers at once: the refusal at 5 s is of the POST made before)
  st.say.delay = 0;
  await w.r.host.time.pass(3_000);
  const then = { held: [...(held(w.inner(), "ws")?.entries ?? [])], station: [...st.chain], protected: protectedOf(w.inner(), A) };
  t.diagnostic(`held: ${shown(then.held)}; the station keeps: ${shown(then.station)}; A protected: ${then.protected}`);
  const after = await removeTablet(w.r);
  const later = { ...after, ok: after.answer !== undefined && "ok" in after.answer, took: removes(TABLET)(st.chain.at(-1)!), protected: protectedOf(w.inner(), A) };
  t.diagnostic(`a later lock.removeDevice: ${said("", after.ms, after.answer)}; the station keeps ${shown(st.chain)}; A protected: ${later.protected}`);
  return { ...w, st, then, later };
}

/// The later call answered well, the station took what it signed, and the station is shown protected.
function laterWell(w: Awaited<ReturnType<typeof p2>>) {
  assert.ok(w.later.ok, said("a later removeDevice", w.later.ms, w.later.answer));
  assert.ok(w.later.took, `the station took it: ${shown(w.st.chain)}`);
  assert.equal(w.later.protected, true, "the station not shown keeping another lock");
}

test("P2: the station refusing past the call's wait, the cloud having taken the entry: the station's chain is held, this device's entry signed again after it", async (t) => {
  const w = await p2(t, (x) => [x.another()]);
  const { then } = w;
  assert.deepEqual(then.station.map((e) => e.kind), ["genesis", "member", "device.remove"], `the station keeps ${shown(then.station)}`);
  assert.ok(removedLast(then.station) && then.station[2]!.prev === entryHash(then.station[1]!), "signed again after the other device's entry");
  assert.deepEqual(then.held.map(entryHash), then.station.map(entryHash), `held ${shown(then.held)}`);
  assert.equal(then.protected, true, "the station not shown keeping another lock");
  laterWell(w);
});

test("P2, the station's chain longer than what is held: held as the station keeps it, links that follow, this device's entry after it", async (t) => {
  const w = await p2(t, (x) => {
    const first = x.another();
    const chain = [...x.stations.get(A)!.chain, first];
    return [first, x.another(chain, "member", { sub: "s4", email: "d@x.com", role: "member" })];
  });
  const { then } = w;
  assert.deepEqual(then.station.map((e) => e.kind), ["genesis", "member", "member", "device.remove"], `the station keeps ${shown(then.station)}`);
  assert.deepEqual(then.held.map(entryHash), then.station.map(entryHash), `held ${shown(then.held)}`);
  laterWell(w);
});

test("P2, the other device's entry about the same device: this device's is not signed again, the station's chain held as it is", async (t) => {
  const w = await p2(t, (x) => [x.another(undefined, "device", { id: PHONE, sub: "s2", kind: "app", label: "Pixel 9" })]);
  const { then } = w;
  assert.deepEqual(then.station.map((e) => e.kind), ["genesis", "device"], `the station keeps ${shown(then.station)}`);
  assert.deepEqual(then.held.map(entryHash), then.station.map(entryHash), `held ${shown(then.held)}`);
  assert.equal(then.protected, true);
  laterWell(w);
});

test("P2 with the app started anew between the cloud taking the entry and the station's refusal: the same, once the station is read", async (t) => {
  const w = await setUp([A]);
  const st = w.stations.get(A)!;
  // (the POST that would be refused never answers: the app goes before it does)
  st.say.silent = true;
  const { ms, answer } = await removePhone(w.r);
  assert.ok(answer !== undefined && "ok" in answer, said("removeDevice, the station silent", ms, answer));
  assert.equal(w.cloud.posted, 1);
  assert.ok(removedLast(held(w.inner(), "ws")!.entries), "held with this device's entry");
  await w.restart();
  // Meanwhile the station took another device's entry at that place, and answers again.
  st.say.silent = false;
  st.chain.push(w.another(st.chain.slice(0, 1)));
  await w.run(read(w.inner(), "ws"));
  await w.r.host.time.pass(1_000);
  t.diagnostic(`held: ${shown(held(w.inner(), "ws")?.entries)}; the station keeps: ${shown(st.chain)}; A protected: ${protectedOf(w.inner(), A)}`);
  assert.deepEqual(st.chain.map((e) => e.kind), ["genesis", "member", "device.remove"], `the station keeps ${shown(st.chain)}`);
  assert.ok(removedLast(st.chain));
  assert.deepEqual(held(w.inner(), "ws")!.entries.map(entryHash), st.chain.map(entryHash), `held ${shown(held(w.inner(), "ws")?.entries)}`);
  assert.equal(protectedOf(w.inner(), A), true);
  const after = await removeTablet(w.r);
  t.diagnostic(`a later lock.removeDevice: ${said("", after.ms, after.answer)}; the station keeps ${shown(st.chain)}`);
  assert.ok(after.answer !== undefined && "ok" in after.answer, said("a later removeDevice", after.ms, after.answer));
  assert.ok(removes(TABLET)(st.chain.at(-1)!));
});

test("a chain held of the cloud alone gives way to a station's showing another entry after the place they agree", async (t) => {
  const w = await setUp([A]);
  const st = w.stations.get(A)!;
  const g0 = st.chain[0]!;
  // The station not reached: the cloud's chain, one entry on, is what is read.
  st.say.down = true;
  const fromCloud = w.another([g0], "member", { sub: "s5", email: "e@x.com", role: "member" });
  w.r.cloud.chains.set("ws", [g0, fromCloud]);
  await w.run(read(w.inner(), "ws"));
  assert.equal(held(w.inner(), "ws")!.head!.hash, entryHash(fromCloud), "held of the cloud");
  // The station back, keeping another entry at that place.
  st.say.down = false;
  st.chain.push(w.another([g0]));
  await w.run(read(w.inner(), "ws"));
  await w.r.host.time.pass(500);
  t.diagnostic(`held: ${shown(held(w.inner(), "ws")?.entries)}; the station keeps: ${shown(st.chain)}`);
  assert.deepEqual(held(w.inner(), "ws")!.entries.map(entryHash), st.chain.map(entryHash), "the station's held");
  assert.equal(protectedOf(w.inner(), A), true);
});

test("a station showing another entry at or below the place a station showed changes nothing held (#5540)", async (t) => {
  const w = await setUp([A]);
  const st = w.stations.get(A)!;
  const { answer } = await removePhone(w.r);
  assert.ok(answer !== undefined && "ok" in answer);
  const was = held(w.inner(), "ws")!;
  assert.ok(removedLast(was.entries) && removedLast(st.chain), "the station took it: shown");
  // The station now says another entry at that place (a fork), and is read.
  st.chain.splice(1, st.chain.length - 1, w.another(st.chain.slice(0, 1)));
  await w.run(read(w.inner(), "ws"));
  await w.r.host.time.pass(500);
  t.diagnostic(`held: ${shown(held(w.inner(), "ws")?.entries)}; the station keeps: ${shown(st.chain)}`);
  assert.deepEqual(held(w.inner(), "ws")!.entries.map(entryHash), was.entries.map(entryHash), "what is held stays");
  assert.equal(st.chain.length, 2, "nothing signed again");
});
