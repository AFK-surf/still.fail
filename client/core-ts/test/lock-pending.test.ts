// An entry of a workspace's lock that no station took and none refused by the call's wait is pending: the call
// answers at once saying so, the chain held is without it, the cloud's taking it counts for nothing, and it is brought
// to the stations as one is next read (views/lock.ts `deliver`): taken; signed again after the head where that moved
// and still says what was meant; failed, said so, where it does not. 2026-11-12: with the workspace's one station
// asleep and the cloud up, 移除设备 answered as done though no station would act on it; with both silent, never.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CLOUD_WRITE_MS } from "../src/core/execute.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, Signer, entryHash, next } from "../src/lock.ts";
import { PENDING_MOST } from "../src/lock-pending.ts";
import { jsonResponse } from "../src/testing.ts";
import { ASKED_MS, held, pendingHeld, read } from "../src/views/lock.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, genesis, grant, rig } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

/// The lock's one station.
const A = "aa".repeat(32);
/// Web pages of the owner's, on the lock.
const WEBS = Array.from({ length: PENDING_MOST + 1 }, (_, i) => (0xe0 + i).toString(16).repeat(32));
const SLACK_MS = 200;

/// A station of the lock as station/src/mesh/serve.ts answers it: `silent`, asked, it never answers; `lateUntil`, till
/// then what it is asked is held, and answered then; `refuse`, what is brought not on its head is refused (409).
function station(first: Entry, now: () => number) {
  const chain: Entry[] = [first];
  const say = { silent: false, lateUntil: 0 };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.silent) return Effect.never;
    if (now() < say.lateUntil) return Effect.andThen(Effect.sleep(say.lateUntil - now()), Effect.suspend(() => answer(method, path, body)));
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: head(), entries: chain.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      const es = (body as { entries: Entry[] }).entries;
      const last = es.at(-1)!;
      if (last.seq < chain.length) return entryHash(chain[last.seq]!) === entryHash(last) ? Effect.succeed({ taken: 0, head: head() }) : Effect.fail(new CoreError("lock_refused", "another entry is at its place", 409));
      for (const e of es) if (e.seq === chain.length && e.prev === entryHash(chain.at(-1)!)) chain.push(e);
      // (a lock turned off is let go of: the station keeps none after it, and says only that it took it)
      if (chain.at(-1) === last && last.kind === "disable") return Effect.succeed({ taken: 1, head: null });
      return chain.at(-1) === last ? Effect.succeed({ taken: 1, head: head() }) : Effect.fail(new CoreError("lock_refused", "not on its head", 409));
    }
    if (method === "GET" && path === "/lock/devices") return Effect.succeed({ devices: [] });
    if (method === "GET" && path === "/lock/person") return Effect.succeed({ chains: [] });
    if (method === "POST" && path === "/lock/person") return Effect.succeed({ taken: 1 });
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, say, answer };
}

/// A locked workspace `ws` (s1 the owner, this device its app; s2 a member with a phone; web pages of s1's), its one
/// station A serving it, the lock read and held; the cloud answering, or (`cloud: "never"`) never.
async function setUp(cloud: "answers" | "never" = "answers") {
  const g = grant();
  const more = [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }, ...WEBS.map((id, i) => ({ id, sub: "s1", kind: "web", label: `web ${i}`, exp: 2_000_000_000 }))];
  const r = await rig((signer) => ({ ws: genesis("ws", signer, true, [{ key: A, name: "mini" }], g.keys, ME, more) }), undefined, A);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!, () => r.host.nowMs());
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return st.answer(method, path, body);
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let finished = false;
    let failed: unknown;
    let out: X | undefined;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; finished = true; }, onFailure: (f) => { failed = f; finished = true; } }));
    for (let i = 0; i < 3000 && !finished; i++) await r.host.time.pass(10);
    assert.ok(finished, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its own lock's key made first, as answer-timing.test.ts's: nothing of this device's to say in the lock then)
  await run(inner.adb.personal().makeKey());
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.head?.seq, 0);
  if (cloud === "never") stationLater(r.host, () => new Promise(() => {}));
  /// A call as the app makes it: its answer and how long it took.
  const timed = async (name: string, params: Record<string, unknown>) => {
    const ui = r.core.connect();
    const id = 9000 + Math.floor(Math.random() * 1000);
    call(r.core, ui, id, name, { account: "s1", workspace: "ws", ...params });
    const t0 = r.host.nowMs();
    let answer: Record<string, any> | undefined;
    for (let i = 0; i < 3000 && answer === undefined; i++) {
      await r.host.time.pass(10);
      for (const [, m] of r.host.takeEmitted()) {
        const msg = m as Record<string, any>;
        if (msg.id === id && ("ok" in msg || "error" in msg)) answer = msg;
      }
    }
    assert.ok(answer !== undefined, `${name}: no answer`);
    return { ms: r.host.nowMs() - t0, ok: answer.ok, error: answer.error };
  };
  /// The station told this device again (its link opened, its `lock` event): the lock read of it.
  const told = () => run(read(inner, "ws"));
  const removed = (id: string) => held(inner, "ws")!.entries.some((e) => e.kind === "device.remove" && (e.body as { id: string }).id === id);
  return { r, inner, st, run, timed, told, removed };
}

/// An entry signed at the station meanwhile, after its head (by this device's key, as another device of the owner's
/// would: what the station keeps is all this device reads of it).
async function theirs(s: Awaited<ReturnType<typeof setUp>>, kind: string, body: unknown): Promise<Entry> {
  const signer = (await Effect.runPromise(Signer.load(s.r.host)))!;
  const h = s.st.chain.at(-1)!;
  const e = signer.sign(next("ws", { seq: h.seq, hash: entryHash(h), genesis: entryHash(s.st.chain[0]!) }, 2000, kind, body));
  s.st.chain.push(e);
  return e;
}

test("no station answering and the cloud taking it: pending within the call's wait, nothing held, the cloud sent nothing", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  const a = await s.timed("lock.removeDevice", { device: PHONE });
  assert.ok(a.ms <= ASKED_MS + SLACK_MS, `answered after ${a.ms} ms`);
  assert.equal(a.error, undefined);
  assert.equal(a.ok.pending.state, "waiting");
  assert.match(a.ok.pending.text, /studio/);
  assert.equal(held(s.inner, "ws")!.head!.seq, 0, "the chain held is without it");
  assert.equal(s.r.cloud.posted.filter((p) => p.kind === "device.remove").length, 0, "the cloud is not sent what no station took");
  assert.deepEqual(pendingHeld(s.inner, "ws").map((x) => [x.state, x.entry.kind]), [["waiting", "device.remove"]]);
  // (kept on the device: the core's device data, which outlives a run)
  assert.ok(s.inner.data.record("lockPending", "ws") !== undefined);
  // Its station back and read: brought, taken, pending no more, and then the cloud is sent it.
  s.st.say.silent = false;
  await s.told();
  await s.r.host.time.pass(500);
  assert.equal(pendingHeld(s.inner, "ws").length, 0);
  assert.ok(s.removed(PHONE));
  assert.equal(s.st.chain.at(-1)!.kind, "device.remove");
  assert.equal(s.r.cloud.posted.filter((p) => p.kind === "device.remove").length, 1);
});

test("a station that takes it after the call's wait: held as it comes, pending no more", async () => {
  const s = await setUp();
  s.st.say.lateUntil = s.r.host.nowMs() + 10_000;
  const a = await s.timed("lock.removeDevice", { device: PHONE });
  assert.ok(a.ms <= ASKED_MS + SLACK_MS, `answered after ${a.ms} ms`);
  assert.equal(a.ok.pending.state, "waiting");
  await s.r.host.time.pass(8_000);
  assert.equal(pendingHeld(s.inner, "ws").length, 0);
  assert.ok(s.removed(PHONE));
});

test("the cloud down and the station up: nothing waits on the cloud", async () => {
  const s = await setUp("never");
  const a = await s.timed("lock.removeDevice", { device: PHONE });
  assert.ok(a.ms <= ASKED_MS + SLACK_MS, `answered after ${a.ms} ms`);
  assert.equal(a.error, undefined);
  assert.equal(a.ok.pending, undefined);
  assert.ok(s.removed(PHONE));
});

test("the head moved meanwhile: signed again after it where it still says what was meant", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  await s.timed("lock.removeDevice", { device: PHONE });
  // Another device made s2 an admin meanwhile: about someone else than the phone.
  s.st.say.silent = false;
  await theirs(s, "member", { sub: "s2", email: "b@x.com", role: "admin" });
  await s.told();
  await s.r.host.time.pass(500);
  assert.equal(pendingHeld(s.inner, "ws").length, 0);
  assert.equal(s.st.chain.length, 3);
  assert.equal(s.st.chain[2]!.kind, "device.remove");
  assert.equal(s.st.chain[2]!.prev, entryHash(s.st.chain[1]!));
  assert.ok(s.removed(PHONE));
});

test("the head moved meanwhile with the same said: done, dropped, nothing signed again", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  await s.timed("lock.removeDevice", { device: PHONE });
  s.st.say.silent = false;
  await theirs(s, "device.remove", { id: PHONE });
  await s.told();
  await s.r.host.time.pass(500);
  assert.equal(pendingHeld(s.inner, "ws").length, 0);
  assert.equal(s.st.chain.length, 2);
});

test("the head moved meanwhile about the same device otherwise: failed, said so, nothing signed again", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  await s.timed("lock.removeDevice", { device: PHONE });
  s.st.say.silent = false;
  await theirs(s, "device", { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8 Pro" });
  await s.told();
  await s.r.host.time.pass(500);
  assert.deepEqual(pendingHeld(s.inner, "ws").map((x) => x.state), ["failed"]);
  assert.equal(s.st.chain.length, 2);
  assert.ok(!s.removed(PHONE));
});

test("an act that only repeats a pending one answers as that one, signing nothing twice", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  const a = await s.timed("lock.removeDevice", { device: PHONE });
  const b = await s.timed("lock.removeDevice", { device: PHONE });
  assert.equal(b.ok.pending.id, a.ok.pending.id);
  assert.equal(pendingHeld(s.inner, "ws").length, 1);
});

test("past the bound: the call is refused with a sentence that says what to wait for", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  for (let i = 0; i < PENDING_MOST; i++) assert.equal((await s.timed("lock.removeDevice", { device: WEBS[i] })).ok.pending.state, "waiting");
  const over = await s.timed("lock.removeDevice", { device: WEBS[PENDING_MOST] });
  assert.equal(over.error?.code, "lock_pending_full");
  assert.match(over.error?.message, /studio/);
  assert.equal(pendingHeld(s.inner, "ws").length, PENDING_MOST);
  // Its station back: all of them taken, one after another, each signed again after the one before.
  s.st.say.silent = false;
  await s.told();
  await s.r.host.time.pass(2_000);
  assert.equal(pendingHeld(s.inner, "ws").length, 0);
  assert.equal(s.st.chain.length, PENDING_MOST + 1);
});

test("the cloud's answer to a lock entry changes nothing: a lock read of the cloud alone brings no pending entry on", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  stationLater(s.r.host, (req) => (req.method === "POST" && /\/lock$/.test(new URL(req.url).pathname) ? Promise.resolve(jsonResponse(200, { ok: true })) : undefined));
  await s.timed("lock.removeDevice", { device: PHONE });
  await s.r.host.time.pass(20_000);
  assert.equal(held(s.inner, "ws")!.head!.seq, 0);
  assert.equal(pendingHeld(s.inner, "ws").length, 1);
});

test("the roster's writes with the cloud never answering: each ends at CLOUD_WRITE_MS saying nothing was saved, a pending entry of it dropped", async () => {
  const said = "still.fail 服务器没有回应，这项改动没有保存。请检查网络后再试一次";
  for (const [name, params] of [
    ["workspace.setRole", { member: "s2", role: "admin" }],
    ["workspace.removeMember", { member: "s2" }],
    ["workspace.removeStation", { station: A }],
    ["workspace.addMembers", { role: "admin", emails: ["d@x.com"] }],
    ["workspace.enroll", { name: "mini" }],
  ] as const) {
    for (const silent of [false, true]) {
      const s = await setUp("never");
      s.st.say.silent = silent;
      const a = await s.timed(name, params);
      const what = `${name}, the station ${silent ? "silent" : "up"}`;
      assert.equal(a.error?.code, "cloud_silent", `${what}: ${JSON.stringify(a)}`);
      assert.equal(a.error?.message, said, what);
      assert.ok(a.ms <= (silent ? ASKED_MS : 0) + CLOUD_WRITE_MS + SLACK_MS, `${what}: answered after ${a.ms} ms`);
      // (nothing saved: what was pending of it is no more, and nothing is to take effect later)
      assert.equal(pendingHeld(s.inner, "ws").length, 0, what);
    }
  }
});

test("the lock turned off with its station up: taken (the station lets the lock go and shows no head), not pending", async () => {
  const s = await setUp();
  const a = await s.timed("lock.disable", {});
  assert.equal(a.error, undefined);
  assert.equal(a.ok.pending, undefined, JSON.stringify(a.ok));
  assert.equal(pendingHeld(s.inner, "ws").length, 0);
  assert.equal(held(s.inner, "ws")!.entries.at(-1)!.kind, "disable");
});
