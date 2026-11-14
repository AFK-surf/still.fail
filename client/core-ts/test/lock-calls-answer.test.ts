// The workspace lock's own calls a person waits on (views/lock.ts `run`: the page's `state`, a device taken out or
// renewed, the lock turned off; a device approved face to face, views/pair.ts `approve`) wait on its stations for ASKED_MS at most, all told (2026-11-12: with the one station
// asleep, each took 45 s, three waits of TAKEN_MS; with the cloud's reads unanswered too, none answered). Its station
// served the lock and then went silent (its machine asleep: asked, it neither answers nor closes), the cloud (a)
// answering everything, (b) leaving its reads unanswered: each answers within ASKED_MS, what it signed pending (no
// station took it: not held, not sent to the cloud, whose taking it would count for nothing). Stations that answer are still what takes the entry, the
// cloud not waited on: with the cloud down entirely a device is taken out at once, and the lock turned off after the
// person took 10 s over its prompt (the wait begins at the stations, not with the call). Each case in a workspace of
// its own, locked, this device signing for its owner.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, entryHash } from "../src/lock.ts";
import { ASKED_MS, held, lockView, pendingHeld, read } from "../src/views/lock.ts";
import { serveTrusted, tryOne } from "../src/views/pair.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, genesis, grant, pipe, rig } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

/// The lock's one station.
const A = "aa".repeat(32);
/// A web page of the owner's, on the lock.
const WEB = "ef".repeat(32);
/// How long a call is given before it is said to have no answer.
const LIMIT_MS = 120_000;
/// Past ASKED_MS, what a call may take on this clock: it is stepped 10 ms at a time and an answer is seen at the end of
/// a step; what follows the wait (the entry's POST to the cloud, its answer, the call's answer to the UI) is answered
/// within the step the wait ends in here (each answered at 3000 ms), and may take a few more on a fixture that answers
/// a step later.
const SLACK_MS = 50;

type Rig = Awaited<ReturnType<typeof rig>>;

/// A station of the lock as station/src/mesh/serve.ts answers it (as lock-stations.test.ts's); `silent`: asked, it
/// never answers.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const say = { silent: false };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.silent) return Effect.never;
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: head(), entries: chain.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      for (const e of (body as { entries: Entry[] }).entries) if (e.seq === chain.length) chain.push(e);
      return Effect.succeed({ taken: 1, head: head() });
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    if (method === "POST" && path === "/lock/person") return Effect.succeed({ taken: 1 });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, say, answer };
}

/// A locked workspace `ws` (s1 the owner, this device its app; s2 a member; `more` devices), its one station A serving
/// it, the lock read and held.
async function setUp(more: Record<string, unknown>[]) {
  const g = grant();
  const r = await rig((signer) => ({ ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME, more) }), undefined, A);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!);
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return st.answer(method, path, body);
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let failed: unknown;
    let out: X | undefined;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its key of its person's lock made before, as lock-stations.test.ts's setUp does)
  await run(inner.adb.personal().makeKey());
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.head?.seq, 0);
  return { r, inner, st, g };
}

/// The cloud from now on: "all" answered as the rig's does, "reads" its GETs never answered, "down" nothing answered.
function cloudAs(r: Rig, mode: "all" | "reads" | "down") {
  stationLater(r.host, (req) => (mode === "down" || (mode === "reads" && req.method === "GET") ? new Promise(() => {}) : undefined));
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
async function timedCall(r: Rig, name: string, params: Record<string, unknown>) {
  const ui = r.core.connect();
  const id = 9000;
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

/// The call answered, well, within `bound`.
function answeredWithin(what: string, ms: number | null, answer: Record<string, unknown> | undefined, bound: number) {
  assert.ok(ms !== null, `${what}: no answer after ${LIMIT_MS} ms`);
  assert.ok(answer !== undefined && "ok" in answer, `${what}: answered after ${ms} ms with ${JSON.stringify(answer?.error)}`);
  assert.ok(ms <= bound, `${what}: answered after ${ms} ms, more than ${bound}`);
}

/// What the call signed, no station taking it: pending here (`is` of it, after the head held), the chain held and the
/// cloud's (`before` its length) without it.
function pendingOn(what: string, r: Rig, inner: Rig["core"]["inner"], before: number, is: (e: Entry) => boolean) {
  assert.equal(r.cloud.chains.get("ws")!.length, before, `${what}: the cloud is not sent what no station took`);
  const h = held(inner, "ws")!;
  assert.equal(h.entries.length, before, `${what}: the chain held is without it`);
  const waiting = pendingHeld(inner, "ws").filter((x) => x.state === "waiting");
  assert.equal(waiting.length, 1, `${what}: one pending`);
  const e = waiting[0]!.entry;
  assert.ok(is(e), `${what}: ${e.kind} ${JSON.stringify(e.body)}`);
  assert.equal(e.prev, h.head!.hash, `${what}: after the head held`);
}

const CONDITIONS = [
  { name: "(a) the cloud answering all", mode: "all" as const },
  { name: "(b) the cloud's reads unanswered", mode: "reads" as const },
];

const CALLS: { call: string; params: Record<string, unknown>; entry: ((e: Entry) => boolean) | null }[] = [
  { call: "lock.state", params: { workspace: "ws" }, entry: null },
  { call: "lock.removeDevice", params: { workspace: "ws", device: PHONE }, entry: (e) => e.kind === "device.remove" && (e.body as { id?: string }).id === PHONE },
  { call: "lock.renew", params: { workspace: "ws", device: WEB }, entry: (e) => e.kind === "device" && (e.body as { id?: string }).id === WEB },
  { call: "lock.disable", params: { workspace: "ws" }, entry: (e) => e.kind === "disable" },
];

for (const cond of CONDITIONS) {
  for (const c of CALLS) {
    test(`${c.call} answers within ASKED_MS, the lock's station silent, ${cond.name}`, async (t) => {
      const { r, inner, st } = await setUp([
        // (s2's phone, not on a lock of s2's own: taken out of the workspace's, `run`'s removeDevice past `onOwnLock`)
        { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" },
        { id: WEB, sub: "s1", kind: "web", label: "web", exp: 2_000_000_000 },
      ]);
      cloudAs(r, cond.mode);
      st.say.silent = true;
      const before = r.cloud.chains.get("ws")!.length;
      const { ms, answer } = await timedCall(r, c.call, c.params);
      t.diagnostic(`${c.call}, ${cond.name}: ${ms} ms`);
      answeredWithin(`${c.call}, ${cond.name}`, ms, answer, ASKED_MS + SLACK_MS);
      if (c.entry !== null) pendingOn(`${c.call}, ${cond.name}`, r, inner, before, c.entry);
      // (not in effect while pending: the page says it is on still, and shows it pending)
      if (c.call === "lock.disable") assert.equal((lockView(inner, "ws") as { locked: boolean }).locked, true, "the lock's page says it is on still");
    });
  }

  test(`a device approved face to face answers within ASKED_MS, the lock's station silent, ${cond.name}`, async (t) => {
    // As lock-pair.test.ts's `met`: s2's phone, not on the lock, met over a stream of its own; the code shown read off
    // the prompt while the station still answers, then the station silent and the code typed.
    const { r, inner, st, g } = await setUp([]);
    const prompts = await r.watch({ topic: "lockPrompts" });
    const [trusted, phone] = await pipe();
    inner.runner.fork(serveTrusted(inner, PHONE, ME, trusted));
    const sign_key = "ed25519:" + "11".repeat(32);
    const hello = { t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", PHONE, "s2") }], kind: "app", label: "Pixel 8", sign_key };
    let first: unknown;
    inner.runner.fork(Effect.map(Effect.andThen(phone.send(hello), phone.next()), (m) => { first = m; }));
    await until(r, () => first !== undefined);
    assert.deepEqual(first, { t: "code", workspaces: ["ws"] });
    const shown = (await prompts()).pairing;
    assert.equal(shown.length, 1);
    cloudAs(r, cond.mode);
    st.say.silent = true;
    const before = r.cloud.chains.get("ws")!.length;
    let out: { ok: unknown } | { err: unknown } | undefined;
    inner.runner.fork(Effect.map(Effect.result(tryOne(inner, { id: ME, d: phone, workspaces: ["ws"] } as never, PHONE, shown[0].code)), (x) => {
      out = x._tag === "Success" ? { ok: x.success } : { err: x.failure };
    }));
    const ms = await until(r, () => out !== undefined);
    const what = `approved face to face, ${cond.name}`;
    t.diagnostic(`${what}: ${ms} ms`);
    answeredWithin(what, ms, out === undefined ? undefined : "ok" in out ? { ok: out.ok } : { error: String((out.err as Error)?.message ?? out.err) }, ASKED_MS + SLACK_MS);
    assert.deepEqual((out as { ok: { approved: { workspaces: string[] } } }).ok.approved.workspaces, ["ws"], what);
    pendingOn(what, r, inner, before, (e) => e.kind === "device" && (e.body as { id?: string; sign_key?: string }).id === PHONE && (e.body as { sign_key?: string }).sign_key === sign_key);
  });
}

test("the cloud losing its answers, the lock's station silent: the removal is pending, not said to have failed, and nothing asks the cloud", async (t) => {
  // The cloud was what took the entry once the stations' wait was over, and whether it kept one whose answer was lost
  // (a gateway's 502) was read of it after that wait. It takes none now: the call answers pending whatever it does.
  const { r, inner, st } = await setUp([{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }]);
  cloudAs(r, "all");
  st.say.silent = true;
  r.cloud.lose.posts = 1;
  const before = r.cloud.chains.get("ws")!.length;
  const { ms, answer } = await timedCall(r, "lock.removeDevice", { workspace: "ws", device: PHONE });
  t.diagnostic(`removeDevice, the cloud's answer lost: ${ms} ms`);
  assert.equal(r.cloud.lose.posts, 1, "nothing was posted to the cloud");
  answeredWithin("removeDevice, the cloud's answer lost", ms, answer, ASKED_MS + SLACK_MS);
  pendingOn("removeDevice, the cloud's answer lost", r, inner, before, (e) => e.kind === "device.remove" && (e.body as { id?: string }).id === PHONE);
});

test("stations that answer take the entry, the cloud down entirely not waited on: a device taken out at once", async (t) => {
  const { r, inner, st } = await setUp([{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }]);
  cloudAs(r, "down");
  const { ms, answer } = await timedCall(r, "lock.removeDevice", { workspace: "ws", device: PHONE });
  t.diagnostic(`removeDevice, the cloud down: ${ms} ms`);
  // (well within ASKED_MS: the station's answers, not the wait's end, are what it went on)
  answeredWithin("removeDevice, the cloud down", ms, answer, ASKED_MS / 2);
  assert.deepEqual([st.chain.length, st.chain.at(-1)!.kind, (st.chain.at(-1)!.body as { id: string }).id], [2, "device.remove", PHONE], "the station took it");
  assert.equal(held(inner, "ws")?.head?.hash, entryHash(st.chain.at(-1)!));
});

test("the call's wait begins at the stations, not with the call: the lock turned off after the person took 10 s over its prompt, the cloud down, the station takes it", async (t) => {
  const { r, inner, st } = await setUp([]);
  // The person takes 10 s to answer the system's prompt (a fingerprint), on the core's clock.
  const ask = r.host.secureAsk!;
  r.host.secureAsk = (reason) => Effect.andThen(Effect.sleep(10_000), ask.call(r.host, reason));
  const asked = r.host.secureAsked.length;
  cloudAs(r, "down");
  const { ms, answer } = await timedCall(r, "lock.disable", { workspace: "ws" });
  t.diagnostic(`disable after a prompt of 10 s, the cloud down: ${ms} ms`);
  assert.equal(r.host.secureAsked.length, asked + 1, "the person was asked");
  answeredWithin("disable after a prompt of 10 s, the cloud down", ms, answer, 10_000 + ASKED_MS / 2);
  assert.ok(ms! >= 10_000, `answered after ${ms} ms, before the person did`);
  assert.equal(st.chain.at(-1)!.kind, "disable", "the station took it");
  assert.equal((lockView(inner, "ws") as { locked: boolean }).locked, false);
});
