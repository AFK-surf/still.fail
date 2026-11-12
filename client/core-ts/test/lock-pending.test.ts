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
import { ASKED_MS, held, pendingHeld, pendingRowOf, read } from "../src/views/lock.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, genesis, grant, rig } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

/// The lock's one station.
const A = "aa".repeat(32);
/// Its second, where `setUp` is asked for two.
const B = "bb".repeat(32);
/// Web pages of the owner's, on the lock.
const WEBS = Array.from({ length: PENDING_MOST + 1 }, (_, i) => (0xe0 + i).toString(16).repeat(32));
const SLACK_MS = 200;

/// A station of the lock as station/src/mesh/serve.ts answers it: `silent`, asked, it never answers; `lateUntil`, till
/// then what it is asked is held, and answered then; `refuse`, what is brought not on its head is refused (409);
/// `rules`, what is brought is refused in these words (409), as the lock's rules refuse it there.
function station(first: Entry, now: () => number) {
  const chain: Entry[] = [first];
  const say = { silent: false, lateUntil: 0, rules: null as string | null };
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
      if (say.rules !== null) return Effect.fail(new CoreError("lock_refused", say.rules, 409));
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
/// station A serving it (`two`: and B, `st2`), the lock read and held; the cloud answering, or (`cloud: "never"`) never.
async function setUp(cloud: "answers" | "never" = "answers", two = false) {
  const g = grant();
  const more = [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }, ...WEBS.map((id, i) => ({ id, sub: "s1", kind: "web", label: `web ${i}`, exp: 2_000_000_000 }))];
  const r = await rig((signer) => ({ ws: genesis("ws", signer, true, [{ key: A, name: "mini" }, ...(two ? [{ key: B, name: "mini 2" }] : [])], g.keys, ME, more) }), undefined, two ? [A, B] : A);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!, () => r.host.nowMs());
  const st2 = station(r.cloud.chains.get("ws")![0]!, () => r.host.nowMs());
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) return st.answer(method, path, body);
    if (two && ws === "ws" && id === B && path.startsWith("/lock")) return st2.answer(method, path, body);
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
  return { r, inner, st, st2, run, timed, told, removed };
}
type Setup = Awaited<ReturnType<typeof setUp>>;

/// The cloud from now on answering the workspace's view with `left` its stations, and taking a station's removal (as
/// it does once a person takes one out).
function stationsLeft(s: Setup, left: { id: string; name: string }[]) {
  stationLater(s.r.host, (req) => {
    const path = new URL(req.url).pathname;
    if (req.method === "DELETE" && /^\/v1\/workspaces\/ws\/stations\/[^/]+$/.test(path)) return Promise.resolve(jsonResponse(200, { ok: true }));
    if (req.method === "GET" && path === "/v1/workspaces/ws") return Promise.resolve(jsonResponse(200, { id: "ws", name: "W", role: "owner", lock: s.r.cloud.head("ws"), lock_requests: 0, stations: left.map((x) => ({ ...x, online: true, last_seen: null })) }));
    return undefined;
  });
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
  assert.match(pendingRowOf(s.inner, "ws", pendingHeld(s.inner, "ws")[0]!).text, /^移除设备 .+：没有生效。另一台设备刚改过「.+」，请查看现在的状态，仍然需要的话再操作一次$/);
  assert.equal(s.st.chain.length, 2);
  assert.ok(!s.removed(PHONE));
});

test("refused by its station with its parent the head still (the lock's rules there): failed, said so, the station's words kept apart", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  await s.timed("lock.removeDevice", { device: PHONE });
  s.st.say.silent = false;
  s.st.say.rules = "this device may not take that one out";
  await s.told();
  await s.r.host.time.pass(500);
  const row = pendingRowOf(s.inner, "ws", pendingHeld(s.inner, "ws")[0]!);
  assert.deepEqual([row.state, row.why], ["failed", "this device may not take that one out"]);
  assert.match(row.text, /^移除设备 .+：没有生效。请查看现在的状态，仍然需要的话再操作一次$/);
});

test("the lock turned off by another device meanwhile: failed, said it is no longer needed", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  await s.timed("lock.removeDevice", { device: PHONE });
  s.st.say.silent = false;
  await theirs(s, "disable", {});
  await s.told();
  await s.r.host.time.pass(500);
  const row = pendingRowOf(s.inner, "ws", pendingHeld(s.inner, "ws")[0]!);
  assert.equal(row.state, "failed");
  assert.match(row.text, /^移除设备 .+：没有生效。安全模式已经关闭，这项改动不再需要$/);
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

// ── a station gone for good ──
// Whose taking counts for an entry are the stations the lock names after it (views/lock.ts `#signed`): one taken out is
// brought it behind, and where none is named after it the lock is the cloud's to keep, as one that never named one;
// what was pending then is brought the cloud's way (`deliver`). 2026-11-13: with the lock's one station retired, every
// change pended for good, its removal too, and past PENDING_MOST every call was refused: the lock could be neither
// changed nor turned off, and the station's machine, the last way out, was gone.

test("the lock's one station gone for good, taken out of the workspace: its removal the cloud's, what was pending for it brought then, and the lock turned off at once", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  const a = await s.timed("lock.removeDevice", { device: PHONE });
  assert.equal(a.ok?.pending?.state, "waiting", JSON.stringify(a.ok));
  stationsLeft(s, []);
  const b = await s.timed("workspace.removeStation", { station: A });
  assert.equal(b.error, undefined, JSON.stringify(b.error));
  await s.r.host.time.pass(1_000);
  const kinds = held(s.inner, "ws")!.entries.map((e) => e.kind);
  assert.ok(kinds.includes("station.remove"), kinds.join());
  assert.ok(s.removed(PHONE), `the pending removal taken: ${kinds.join()}`);
  assert.deepEqual(pendingHeld(s.inner, "ws"), []);
  assert.ok(s.r.cloud.chains.get("ws")!.some((e) => e.kind === "device.remove" && (e.body as { id: string }).id === PHONE), "the cloud keeps it");
  const lock = await s.r.watch({ topic: "lock", workspace: "ws" });
  const l = await lock();
  assert.deepEqual(l.pending, []);
  assert.ok(!JSON.stringify(l.members ?? []).includes("Pixel 8"), "the phone not listed");
  const c = await s.timed("lock.disable", {});
  assert.equal(c.error, undefined, JSON.stringify(c.error));
  assert.equal(c.ok?.pending, undefined, JSON.stringify(c.ok));
  assert.equal(held(s.inner, "ws")!.entries.at(-1)!.kind, "disable");
});

test("one of the lock's two stations taken out while the other is silent: pending, waiting for the other by name, the cloud sent nothing", async () => {
  const s = await setUp("answers", true);
  s.st2.say.silent = true;
  stationsLeft(s, [{ id: B, name: "studio 2" }]);
  const length = s.r.cloud.chains.get("ws")!.length;
  const b = await s.timed("workspace.removeStation", { station: A });
  assert.equal(b.error, undefined, JSON.stringify(b.error));
  // (the answer the cloud's with the row, which says it waits)
  assert.match(b.ok?.pending?.text ?? "", /^移除 station .+：已记下，等 studio 2 上线后生效$/, JSON.stringify(b.ok));
  assert.deepEqual(pendingHeld(s.inner, "ws").map((x) => [x.state, x.entry.kind]), [["waiting", "station.remove"]]);
  assert.equal(s.r.cloud.chains.get("ws")!.length, length, "the cloud sent nothing");
  const lock = await s.r.watch({ topic: "lock", workspace: "ws" });
  const rows = (await lock()).pending as { stations: string[]; text: string }[];
  assert.deepEqual(rows.map((x) => x.stations), [["studio 2"]], JSON.stringify(rows));
});

// ── what a call answers ──
// A call whose lock entry ends pending says so in its answer, `pending` its row (LockPending), whatever else the call
// answers (the roster's: the cloud's; people added: the first that pends), so the app says that sentence in place of
// its done words (2026-11-13: the roster's calls answered as done, the entry only pending).

test("the roster's calls and people added, their lock entry pending: the answer carries the row, its sentence saying it waits", async () => {
  const members = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }];
  for (const [name, params, says] of [
    ["workspace.setRole", { member: "s2", role: "admin" }, /^把 .+ 改为.+：已记下，等 studio 上线后生效$/],
    ["workspace.removeMember", { member: "s2" }, /^移除成员 .+：已记下，等 studio 上线后生效$/],
    ["workspace.addMembers", { role: "admin", emails: ["d@x.com"] }, /^添加成员 .+：已记下，等 studio 上线后生效$/],
  ] as const) {
    const s = await setUp();
    s.st.say.silent = true;
    stationLater(s.r.host, (req) => {
      const path = new URL(req.url).pathname;
      if ((req.method === "PATCH" || req.method === "DELETE") && path === "/v1/workspaces/ws/members/s2") return Promise.resolve(jsonResponse(200, { ok: true }));
      if (req.method === "POST" && path === "/v1/workspaces/ws/members") return Promise.resolve(jsonResponse(200, { joined: [], added: ["d@x.com"], already: [], view: { members } }));
      return undefined;
    });
    const a = await s.timed(name, params);
    assert.equal(a.error, undefined, `${name}: ${JSON.stringify(a.error)}`);
    assert.equal(a.ok?.pending?.state, "waiting", `${name}: ${JSON.stringify(a.ok)}`);
    assert.match(a.ok.pending.text, says, name);
  }
});
