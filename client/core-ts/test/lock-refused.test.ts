// An entry a station of the lock refuses on the lock it keeps (views/lock.ts `Lock.append`, `#refusedBy`): its 409
// (station/src/mesh/serve.ts: another entry at the place, or the lock's rules), with no station taking it, is the
// call's failure, `lock_refused` in the station's words; the cloud is not sent the entry (sent, it took it where its
// chain was a place behind the station's, and the two forked; its POST unanswered, the call never answered), and the
// station's lock is read again, so the same call pressed again signs after what it keeps. A station keeping another
// lock, or refusing this device, is as before: the entry goes to the cloud. A station that takes it wins over another's
// refusal, whichever comes first: a refusal does not end the wait, and with another station silent it is the call's
// answer once the call's wait is over. Each case in a workspace of its own, locked, this device signing for its owner,
// on the test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { ASKED_MS, held, read } from "../src/views/lock.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, elsewhere, genesis, grant, rig } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

const A = "aa".repeat(32);
const B = "bb".repeat(32);
/// What a station says as it refuses an entry that disagrees with its chain (station/src/cloud/state.ts `takeLock`).
const FORK = "the entry disagrees with this station's lock (a fork)";
/// How long a call is given before it is said to have no answer.
const LIMIT_MS = 30_000;

type Rig = Awaited<ReturnType<typeof rig>>;

/// A station of the lock as station/src/mesh/serve.ts answers it, its refusals as the core has them (requests.ts
/// `httpError`: the code, the words, the status). `pending`: another device's entry, at the place this one signs, that
/// reaches it as this device's does (it read the chain before); `other`: the chain of another lock it keeps since;
/// `refuse`: what it answers every POST /lock; `delay`: how long it takes over a POST; `silent`: it answers no POST.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const say = { pending: null as Entry | null, other: null as Entry[] | null, refuse: null as CoreError | null, delay: 0, silent: false };
  const headOf = (c: Entry[]): Head => ({ seq: c.length - 1, hash: entryHash(c.at(-1)!), genesis: entryHash(c[0]!) });
  const fork = () => Effect.fail(new CoreError("http_409", FORK, 409));
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    const kept = say.other ?? chain;
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: headOf(kept), entries: kept.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      if (say.silent) return Effect.never;
      const take = Effect.suspend((): Effect.Effect<unknown, CoreError> => {
        if (say.refuse !== null) return Effect.fail(say.refuse);
        if (say.pending !== null) {
          chain.push(say.pending);
          say.pending = null;
        }
        if (say.other !== null) return fork();
        let taken = 0;
        for (const e of (body as { entries: Entry[] }).entries) {
          if (e.seq < chain.length) {
            if (entryHash(chain[e.seq]!) !== entryHash(e)) return fork();
          } else if (e.seq === chain.length) {
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
  return { chain, say, head: () => headOf(chain), answer };
}

/// A locked workspace `ws` (s1 the owner, this device its app; s2 a member with a phone), its stations `ids` serving it,
/// the lock read and held. `cloud.posted`: the entries the cloud was sent since; `cloud.hang`: its POST /lock left
/// unanswered.
async function setUp(ids: string[]) {
  const g = grant();
  let me: Signer | null = null;
  const r = await rig((signer) => ((me = signer), { ws: genesis("ws", signer, true, ids.map((key, i) => ({ key, name: `s${i}` })), g.keys, ME, [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }]) }), undefined, ids);
  const inner = r.core.inner;
  const stations = new Map(ids.map((id) => [id, station(r.cloud.chains.get("ws")![0]!)]));
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    const st = ws === "ws" ? stations.get(id!) : undefined;
    if (st !== undefined && path.startsWith("/lock")) return st.answer(method, path, body);
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let failed: unknown;
    let out: X | undefined;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    for (let i = 0; i < 500 && !done; i++) await r.host.time.pass(10);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its key of its person's lock made before, as lock-stations.test.ts's setUp does)
  await run(inner.adb.personal().makeKey());
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.head?.seq, 0);
  const cloud = { posted: 0, hang: false };
  stationLater(r.host, (req) => {
    if (req.method !== "POST" || new URL(req.url).pathname !== "/v1/workspaces/ws/lock") return undefined;
    cloud.posted++;
    return cloud.hang ? new Promise(() => {}) : undefined;
  });
  // Another device's entry at the place this one signs next.
  const another = () => me!.sign(next("ws", stations.get(ids[0]!)!.head(), 1001, "member", { sub: "s3", email: "c@x.com", role: "member" }));
  return { r, inner, stations, cloud, another };
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
const said = (what: string, ms: number | null, answer: Record<string, unknown> | undefined) => `${what}: after ${ms} ms, ${JSON.stringify(answer ?? null)}`;
/// The call refused in the station's words.
function refused(what: string, ms: number | null, answer: Record<string, unknown> | undefined) {
  assert.ok(answer !== undefined && "error" in answer, said(what, ms, answer));
  const e = answer.error as { code: string; message: string };
  assert.deepEqual([e.code, e.message], ["lock_refused", FORK], said(what, ms, answer));
}
const removedLast = (c: Entry[]) => c.at(-1)!.kind === "device.remove" && (c.at(-1)!.body as { id: string }).id === PHONE;

test("an entry the lock's station refuses (another device's at its place) fails the call, the cloud not sent it; read again, pressed again it signs after it", async (t) => {
  const { r, inner, stations, cloud, another } = await setUp([A]);
  const st = stations.get(A)!;
  st.say.pending = another();
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`refused after ${ms} ms`);
  refused("removeDevice", ms, answer);
  assert.equal(cloud.posted, 0, "the cloud was not sent the entry");
  assert.equal(r.cloud.chains.get("ws")!.length, 1, "the cloud's chain unchanged");
  // The station's lock, read again, held here.
  const caught = await until(r, () => held(inner, "ws")?.head?.hash === st.head().hash);
  assert.notEqual(caught, null, "what is held caught up with the station's");
  assert.deepEqual(held(inner, "ws")!.entries.map(entryHash), st.chain.map(entryHash));
  // Pressed again: after it, the station taking it.
  const again = await removePhone(r);
  assert.ok(again.answer !== undefined && "ok" in again.answer, said("again", again.ms, again.answer));
  assert.equal(st.chain.length, 3);
  assert.ok(removedLast(st.chain) && st.chain.at(-1)!.seq === 2, "signed after the other device's entry, taken by the station");
});

test("refused so, the cloud's POST unanswered: the call fails at once", async (t) => {
  const { r, stations, cloud, another } = await setUp([A]);
  stations.get(A)!.say.pending = another();
  cloud.hang = true;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`refused after ${ms} ms`);
  assert.notEqual(ms, null, `no answer in ${LIMIT_MS} ms`);
  refused("removeDevice, the cloud's POST unanswered", ms, answer);
  assert.ok(ms! <= 50, `answered after ${ms} ms`);
  assert.equal(cloud.posted, 0);
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

test("within a call's wait, one station refusing at 1 s and the other silent: the refusal is the call's answer once its wait is over, the cloud not sent the entry", async (t) => {
  const { r, stations, cloud, another } = await setUp([A, B]);
  const a = stations.get(A)!;
  a.say.pending = another();
  a.say.delay = 1_000;
  stations.get(B)!.say.silent = true;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`refused after ${ms} ms`);
  refused("removeDevice, B silent", ms, answer);
  assert.ok(ms! >= ASKED_MS && ms! <= ASKED_MS + 50, `answered after ${ms} ms`);
  await r.host.time.pass(500);
  assert.equal(cloud.posted, 0);
});

test("the same refusal coming at 5 s, past the call's wait: the cloud was sent the entry at its end and took it, the call answers well (the known gap)", async (t) => {
  // Past the wait the cloud is asked too, the stations still listened to (views/lock.ts ASKED_MS): at 3 s no station had
  // taken the entry nor refused it, so it went to the cloud, which took it at once. A's refusal at 5 s cannot unsend
  // it: the cloud's chain has this device's entry where A keeps another's. The one case of a station that keeps this
  // lock refusing that cannot be told in time (`Lock.append`); asserted here so that a change to it is seen.
  const { r, stations, cloud, another } = await setUp([A, B]);
  const a = stations.get(A)!;
  a.say.pending = another();
  a.say.delay = 5_000;
  stations.get(B)!.say.silent = true;
  const { ms, answer } = await removePhone(r);
  t.diagnostic(`answered after ${ms} ms`);
  assert.ok(answer !== undefined && "ok" in answer, said("refused at 5 s", ms, answer));
  assert.ok(ms! >= ASKED_MS && ms! <= ASKED_MS + 50, `answered after ${ms} ms`);
  assert.equal(cloud.posted, 1, "the cloud sent it at the wait's end");
  await r.host.time.pass(3_000);
  const kept = r.cloud.chains.get("ws")!;
  assert.ok(removedLast(kept) && kept.at(-1)!.seq === 1, "the cloud keeps this device's entry at 1");
  assert.equal(a.chain[1]!.kind, "member", "where A keeps another device's: the fork");
});
