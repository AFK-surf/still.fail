// Every call a person waits on that the workspace's lock has a part in, made in each way its station and the cloud can
// answer: the station at once, late (its link back 10 s on, as a station just started anew) or never (its machine
// asleep: asked, it neither answers nor closes), or none named (a lock that never had a station, or whose last was
// taken out: the cloud's to keep, views/lock.ts `#cloudOnly`), the cloud answering or never answering anything. 2026-11-12 five
// fixes merged that waited ASKED_MS on the stations and then on the cloud alone: with the cloud frozen and the station
// late, a device approved face to face was never answered (#5646), and every test was green, their stations answering
// at once or never and nothing between. Here each call in each of the eight:
// - what one of them takes is done: answered ok, within the bound of the way it came (`bound`);
// - what neither can take answers all the same, an error, within ASKED_MS + TAKEN_MS and the reread's wait;
// - a call that needs the cloud (the roster's, which is the cloud's: members, roles, stations) is done only with it,
//   and so is every write where the lock names no station; what the cloud does not answer then fails by CLOUD_WRITE_MS.
// What does not hold is in `KNOWN` with why, and `KNOWN` only falls.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { REREAD_WAIT_MS } from "../src/core/execute.ts";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, entryHash } from "../src/lock.ts";
import { CLOUD_WRITE_MS } from "../src/lock-pending.ts";
import { jsonResponse } from "../src/testing.ts";
import { ASKED_MS, TAKEN_MS, held, read } from "../src/views/lock.ts";
import { serveTrusted, tryOne } from "../src/views/pair.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, genesis, grant, pipe, rig } from "./lock-rig.ts";
import { stationLater } from "./station-fixture.ts";

/// The lock's one station.
const A = "aa".repeat(32);
/// A web page of the owner's, on the lock.
const WEB = "ef".repeat(32);
/// When a late station answers, from the call's start.
const LATE_MS = 10_000;
/// How long a call is given before it is said to have no answer at all.
const LIMIT_MS = 30_000;
/// An answer is seen at the end of a 10 ms step, and what follows a wait (an entry's POST, the call's answer) takes a
/// few steps here.
const SLACK_MS = 200;

type Station = "now" | "late" | "never" | "none";
type Cloud = "answers" | "never";
type Rig = Awaited<ReturnType<typeof rig>>;
type Outcome = { ms: number | null; ok: boolean; said: unknown };

/// The calls, what each needs to be done: `either` the station or the cloud taking what it signs, `cloud` the cloud
/// (the roster is the cloud's), `none` nothing (a read answered from what is held).
const CALLS: { name: string; needs: "either" | "cloud" | "none"; make: (s: Setup) => Promise<Outcome> }[] = [
  { name: "lock.state", needs: "none", make: (s) => timedCall(s, "lock.state", { workspace: "ws" }) },
  { name: "lock.removeDevice", needs: "either", make: (s) => timedCall(s, "lock.removeDevice", { workspace: "ws", device: PHONE }) },
  { name: "lock.renew", needs: "either", make: (s) => timedCall(s, "lock.renew", { workspace: "ws", device: WEB }) },
  { name: "lock.disable", needs: "either", make: (s) => timedCall(s, "lock.disable", { workspace: "ws" }) },
  { name: "approved face to face", needs: "either", make: (s) => s.approve() },
  { name: "workspace.setRole", needs: "cloud", make: (s) => timedCall(s, "workspace.setRole", { workspace: "ws", member: "s2", role: "admin" }) },
  { name: "workspace.addMembers", needs: "cloud", make: (s) => timedCall(s, "workspace.addMembers", { workspace: "ws", role: "admin", emails: ["d@x.com"] }) },
  { name: "workspace.removeMember", needs: "cloud", make: (s) => timedCall(s, "workspace.removeMember", { workspace: "ws", member: "s2" }) },
  { name: "workspace.removeStation", needs: "cloud", make: (s) => timedCall(s, "workspace.removeStation", { workspace: "ws", station: A }) },
  { name: "workspace.enroll", needs: "cloud", make: (s) => timedCall(s, "workspace.enroll", { workspace: "ws", name: "mini" }) },
];

/// Cells that do not hold yet, by `call|station|cloud`, each with why. Only falls: one that holds now fails the test
/// until it is taken out.
const KNOWN: Record<string, string> = {};

/// Whether the call is to be done in this cell.
function done(needs: "either" | "cloud" | "none", st: Station, cloud: Cloud): boolean {
  if (needs === "none") return true;
  if (needs === "cloud" || st === "none") return cloud === "answers";
  // (what no station took by the call's wait answers as pending, whatever the cloud does: views/lock.ts `Lock.append`)
  return true;
}

/// How long the call may take in this cell: done, as the one that takes it answers; failing, once neither did.
function bound(ok: boolean, st: Station, cloud: Cloud): number {
  if (!ok) return st === "none" ? CLOUD_WRITE_MS + REREAD_WAIT_MS + SLACK_MS : ASKED_MS + TAKEN_MS + REREAD_WAIT_MS + SLACK_MS;
  // (no station to wait for: the cloud's answer is the call's)
  if (st === "none") return SLACK_MS;
  if (st === "now") return ASKED_MS + SLACK_MS;
  if (cloud === "answers") return ASKED_MS + REREAD_WAIT_MS + SLACK_MS;
  return LATE_MS + REREAD_WAIT_MS + SLACK_MS;
}

/// A station of the lock as station/src/mesh/serve.ts answers it (as lock-calls-answer.test.ts's); `silent`: asked,
/// it never answers; `lateUntil`: till then (the clock's ms) what it is asked is held, and answered then.
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

/// A locked workspace `ws` (s1 the owner, this device its app; s2 a member with a phone; a web page of s1's), its one
/// station A serving it (`named`; else the lock names no station, A only the workspace's), the lock read and held.
async function setUp(named = true) {
  const g = grant();
  const more = [
    { id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" },
    { id: WEB, sub: "s1", kind: "web", label: "web", exp: 2_000_000_000 },
  ];
  const r = await rig((signer) => ({ ws: genesis("ws", signer, true, named ? [{ key: A, name: "a" }] : [], g.keys, ME, more) }), undefined, A);
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
    await r.host.time.passUntil(5000, () => finished);
    assert.ok(finished, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  await run(inner.adb.personal().makeKey());
  await run(read(inner, "ws"));
  assert.equal(held(inner, "ws")?.head?.seq, 0);
  // A new phone of s2's met face to face, its code read off the prompt while all still answer: `approve` types it.
  const prompts = await r.watch({ topic: "lockPrompts" });
  const NEW = "c7".repeat(32);
  const [trusted, phone] = await pipe();
  inner.runner.fork(serveTrusted(inner, NEW, ME, trusted));
  const hello = { t: "hello", v: 1, workspaces: [{ ws: "ws", credential: g.credential("ws", NEW, "s2") }], kind: "app", label: "Pixel 9", sign_key: "ed25519:" + "11".repeat(32) };
  let first: unknown;
  inner.runner.fork(Effect.map(Effect.andThen(phone.send(hello), phone.next()), (m) => { first = m; }));
  await until(r, () => first !== undefined);
  const shown = (await prompts()).pairing as { code: string }[];
  assert.equal(shown.length, 1);
  const approve = async (): Promise<Outcome> => {
    let out: Outcome | undefined;
    const t0 = r.host.nowMs();
    inner.runner.fork(Effect.map(Effect.result(tryOne(inner, { id: ME, d: phone, workspaces: ["ws"] } as never, NEW, shown[0]!.code)), (x) => {
      out = x._tag === "Success" ? { ms: 0, ok: true, said: null } : { ms: 0, ok: false, said: String((x.failure as Error)?.message ?? x.failure) };
    }));
    const ms = await until(r, () => out !== undefined);
    return out === undefined ? { ms: null, ok: false, said: null } : { ...out, ms: r.host.nowMs() - t0 };
  };
  return { r, inner, st, approve };
}
type Setup = Awaited<ReturnType<typeof setUp>>;

/// The cloud from now on: answering (the lock's requests as the rig's cloud does, the roster's at once) or nothing.
function cloudAs(r: Rig, how: Cloud) {
  const members = [{ sub: "s1", email: "a@x.com", role: "owner" }, { sub: "s2", email: "b@x.com", role: "member" }];
  const json = (b: unknown) => Promise.resolve(jsonResponse(200, b));
  stationLater(r.host, (req) => {
    if (how === "never") return new Promise(() => {});
    const path = new URL(req.url).pathname;
    if (req.method === "POST" && path === "/v1/workspaces/ws/members") return json({ joined: [], added: ["d@x.com"], already: [], view: { members } });
    if ((req.method === "PATCH" || req.method === "DELETE") && path === "/v1/workspaces/ws/members/s2") return json({ ok: true });
    if (req.method === "DELETE" && path === `/v1/workspaces/ws/stations/${A}`) return json({ ok: true });
    if (req.method === "POST" && path === "/v1/workspaces/ws/enrollments") {
      return json({ token: "tok", install: "curl x | sh -s -- tok", installWindows: "& (irm x) tok", command: "stillfail station enroll https://x tok" });
    }
    return undefined;
  });
}

/// Steps the clock 10 ms at a time until `ready()` says, or LIMIT_MS: the time it took, or null.
async function until(r: Rig, ready: () => boolean): Promise<number | null> {
  const t0 = r.host.nowMs();
  return (await r.host.time.passUntil(LIMIT_MS, ready)) ? r.host.nowMs() - t0 : null;
}

/// A call made as the app makes it, on its own connection.
async function timedCall(s: Setup, name: string, params: Record<string, unknown>): Promise<Outcome> {
  const ui = s.r.core.connect();
  const id = 9000;
  let answer: Record<string, unknown> | undefined;
  call(s.r.core, ui, id, name, { account: "s1", ...params });
  const ms = await until(s.r, () => {
    for (const [, m] of s.r.host.takeEmitted()) {
      const msg = m as Record<string, unknown>;
      if (msg.id === id && ("ok" in msg || "error" in msg)) answer = msg;
    }
    return answer !== undefined;
  });
  return { ms, ok: answer !== undefined && "ok" in answer, said: answer?.error ?? null };
}

const STATIONS: Station[] = ["now", "late", "never", "none"];
const CLOUDS: Cloud[] = ["answers", "never"];

test("every lock call answers in each way its station and the cloud answer: done where one takes it, an error in time where neither does", async (t) => {
  const wrong: string[] = [];
  const rows: string[] = [];
  for (const c of CALLS) {
    for (const st of STATIONS) {
      for (const cloud of CLOUDS) {
        const s = await setUp(st !== "none");
        cloudAs(s.r, cloud);
        if (st === "late") s.st.say.lateUntil = s.r.host.nowMs() + LATE_MS;
        if (st === "never") s.st.say.silent = true;
        const out = await c.make(s);
        const ok = done(c.needs, st, cloud);
        const most = bound(ok, st, cloud);
        const holds = out.ms !== null && out.ok === ok && out.ms <= most;
        const key = `${c.name}|${st}|${cloud}`;
        rows.push(`TIMING ${key}: ${out.ms === null ? "no answer" : `${out.ok ? "ok" : `error ${JSON.stringify(out.said)}`} after ${out.ms} ms`}; to be ${ok ? "ok" : "an error"} within ${most} ms${holds ? "" : " ✗"}`);
        if (!holds) wrong.push(key);
        s.r.core.close();
      }
    }
  }
  for (const row of rows) console.log(row);
  t.diagnostic(`cells: ${rows.length}; not holding: ${JSON.stringify(wrong)}`);
  assert.deepEqual(wrong.filter((k) => !(k in KNOWN)), [], "a call that does not answer as the station and the cloud let it (see TIMING above)");
  assert.deepEqual(Object.keys(KNOWN).filter((k) => !wrong.includes(k)), [], "holds now: take it out of KNOWN");
});
