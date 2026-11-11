// A person's own lock's calls that the person waits on (personal-lock.ts: a device taken off it, the lock begun anew,
// opened, joined, a phone's grant and a rig's call signed) wait on their stations for ASKED_MS at most a phase, and on
// the cloud's read no longer (2026-11-12: with the person's one station asleep, each took 15 s, joining 30 s; with the
// cloud's reads unanswered too, those that read never answered). Their station served the locks and then went silent
// (its machine asleep: asked, it neither answers nor closes), the cloud (a) answering everything, (b) leaving its reads
// unanswered: each answers within ASKED_MS, what it signed on the person's chain as the cloud keeps it and pinned here.
// Stations that answer still take what is signed, the cloud not waited on; a read that lands past the wait is taken.
//
// Each case in a workspace of its own, locked, this device (ME) signing for its owner s1 and on s1's own lock with
// their laptop, that lock bound in the workspace's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, entryHash, signedBytes } from "../src/lock.ts";
import { personOf } from "../src/personal-lock.ts";
import { hex } from "../src/util.ts";
import { ASKED_MS, bindPerson, fold, held, keepToPerson, onBoundPerson, read, signerKnown } from "../src/views/lock.ts";
import { call } from "./helpers.ts";
import { ME, genesis, grant, rig } from "./lock-rig.ts";
import { stationLater, stationReplies } from "./station-fixture.ts";

/// The workspace's one station, which keeps the person's own lock too.
const A = "aa".repeat(32);
/// The owner's laptop: an app device of theirs in the workspace's lock and on their own.
const LAPTOP = "77".repeat(32);
const LAPTOP_KEY = `ed25519:${"55".repeat(32)}`;
const LAPTOP_SIGNS = `ed25519:${"22".repeat(32)}`;
/// How long a call is given before it is said to have no answer.
const LIMIT_MS = 120_000;
/// Past a wait, what a call may take on this clock: it is stepped 10 ms at a time and an answer is seen at the end of
/// a step; what follows the wait (the entry's POST to the cloud, its answer, the call's answer to the UI) is answered
/// within a step or a few here.
const SLACK_MS = 50;

type Rig = Awaited<ReturnType<typeof rig>>;

/// A station of the locks as station/src/mesh/serve.ts answers it (as lock-calls-answer.test.ts's), keeping the
/// person's own lock too (GET/POST /lock/person); `silent`: asked, it never answers; `personLate`: its reads of the
/// person's lock answered that many ms late.
function station(first: Entry) {
  const chain: Entry[] = [first];
  const kept = { person: [] as Entry[] };
  const say = { silent: false, personLate: 0 };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.silent) return Effect.never;
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
    if (method === "GET" && path === "/lock/person") {
      const now = Effect.sync(() => ({ chains: kept.person.length > 0 ? [{ entries: kept.person }] : [] }));
      return say.personLate > 0 ? Effect.andThen(Effect.sleep(say.personLate), now) : now;
    }
    if (method === "POST" && path === "/lock/person") {
      kept.person = (body as { chain: Entry[] }).chain;
      return Effect.succeed({ taken: 1 });
    }
    return Effect.fail(new CoreError("http_404", "no route", 404));
  };
  return { chain, kept, say, answer };
}

/// A locked workspace `ws` (s1 the owner, this device its app, LAPTOP theirs too), its one station A serving it; this
/// device's person's own lock begun here with LAPTOP put on it, and bound in the workspace's lock.
async function setUp() {
  const g = grant();
  const r = await rig((signer) => ({ ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME, [{ id: LAPTOP, sub: "s1", kind: "app", label: "laptop", sign_key: LAPTOP_SIGNS }]) }), undefined, A);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!);
  // What the station was asked of the person's lock, by method.
  const asked: string[] = [];
  const original = inner.stations.requests.call.bind(inner.stations.requests);
  inner.stations.requests.call = ((addr: { toString(): string }, method: string, path: string, body: unknown, ...rest: unknown[]) => {
    const [ws, id] = addr.toString().split("/");
    if (ws === "ws" && id === A && path.startsWith("/lock")) {
      if (path === "/lock/person") asked.push(`${method}`);
      return st.answer(method, path, body);
    }
    return (original as (...a: unknown[]) => unknown)(addr, method, path, body, ...rest);
  }) as typeof inner.stations.requests.call;
  // The cloud's copy of the person's own lock (/v1/me/personal-lock), beside the rig's workspace locks.
  const personCloud = { entries: [] as Entry[] };
  stationReplies(r.host, (req) => {
    if (!req.url.includes("/v1/me/personal-lock")) return r.cloud.reply(req);
    if (req.method === "GET") return { entries: personCloud.entries };
    const sent = (JSON.parse(new TextDecoder().decode(req.body!)) as { entries: Entry[] }).entries;
    if (sent[0]?.seq === 0) personCloud.entries = sent;
    else for (const e of sent) if (e.seq === personCloud.entries.length) personCloud.entries = [...personCloud.entries, e];
    return { ok: true };
  });
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
  const personal = inner.adb.personal();
  // (its key made first, so that it does not begin the lock by itself as the lock is read: begun here, by hand)
  await run(personal.makeKey());
  await run(read(inner, "ws"));
  await run(personal.begin("s1", "why"));
  await run(personal.addDevice("s1", { key: LAPTOP_KEY, id: LAPTOP, label: "laptop", sign_key: LAPTOP_SIGNS }, "why"));
  await run(read(inner, "ws"));
  await run(bindPerson(inner, "ws"));
  await run(read(inner, "ws"));
  await run(keepToPerson(inner, "ws"));
  await r.host.time.pass(1000);
  assert.equal(personal.standing("s1"), "member");
  assert.equal(onBoundPerson(inner, "ws"), true, "bound");
  assert.deepEqual(st.kept.person.map((e) => e.kind), ["genesis", "device"], "the station keeps the person's lock");
  assert.deepEqual(personCloud.entries.map(entryHash), personal.entries("s1").map(entryHash), "and the cloud");
  asked.length = 0;
  return { r, inner, st, run, personal, personCloud, asked };
}
type Setup = Awaited<ReturnType<typeof setUp>>;

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
  return { ms, ok: answer !== undefined && "ok" in answer, said: answer === undefined ? undefined : "ok" in answer ? answer.ok : answer.error };
}

/// An effect of the core's, timed as a call is.
async function timedEffect(s: Setup, e: Effect.Effect<unknown, any>) {
  let out: { ok: boolean; said: unknown } | undefined;
  s.inner.runner.fork(Effect.match(e, { onSuccess: (x) => void (out = { ok: true, said: x }), onFailure: (f) => void (out = { ok: false, said: f }) }));
  const ms = await until(s.r, () => out !== undefined);
  return { ms, ok: out?.ok ?? false, said: out?.said };
}

/// The call answered, well, within `bound`.
function answeredWithin(what: string, t: { ms: number | null; ok: boolean; said: unknown }, bound: number) {
  assert.ok(t.ms !== null, `${what}: no answer after ${LIMIT_MS} ms`);
  assert.ok(t.ok, `${what}: answered after ${t.ms} ms with ${t.said instanceof CoreError ? t.said.message : JSON.stringify(t.said)}`);
  assert.ok(t.ms <= bound, `${what}: answered after ${t.ms} ms, more than ${bound}`);
}

/// What the call signed is on the person's chain as the cloud keeps it, and pinned here: the last entry, `is` of it,
/// `length` long.
function onChain(what: string, s: Setup, length: number, is: (e: Entry) => boolean) {
  const pinned = s.personal.entries("s1");
  assert.equal(pinned.length, length, `${what}: pinned here ${pinned.map((e) => e.kind).join()}`);
  assert.ok(is(pinned.at(-1)!), `${what}: ${JSON.stringify(pinned.at(-1))}`);
  assert.deepEqual(s.personCloud.entries.map(entryHash), pinned.map(entryHash), `${what}: as the cloud keeps it`);
}

const isRemove = (key: string) => (e: Entry) => e.kind === "device.remove" && (e.body as { key?: string }).key === key;

const CONDITIONS = [
  { name: "(a) the cloud answering all", mode: "all" as const },
  { name: "(b) the cloud's reads unanswered", mode: "reads" as const },
];

/// Each call, made with the station silent and the cloud as the condition says; `signs`: what it leaves on the chain.
/// `signGrant` and `signRig` run the core's function, not the app's call: `adb.decide` signs for a phone's grant that a
/// station lending its adb asked for, and `rig.*` for a rig of the person's, and no fixture here has either; their
/// waits on the person's lock are all in these functions. `signGrant` has two phases (the read before the person is
/// asked, what is signed after): here only the first waits, there being nothing for `#restate` or `#addApproved` to sign
/// (nothing is brought to the station, asserted), so its bound is one ASKED_MS; the second phase is the test
/// below with a prompt of 10 s.
const CALLS: { name: string; made: (s: Setup) => Promise<{ ms: number | null; ok: boolean; said: unknown }>; signs?: (s: Setup, before: Entry[]) => void; reads?: true }[] = [
  {
    name: "adb.personalRemove",
    made: (s) => timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY }),
    signs: (s, before) => onChain("adb.personalRemove", s, before.length + 1, isRemove(LAPTOP_KEY)),
  },
  {
    name: "adb.personalRestart",
    made: (s) => timedCall(s.r, "adb.personalRestart", { sub: "s1" }),
    signs: (s, before) => onChain("adb.personalRestart", s, 1, (e) => e.kind === "genesis" && entryHash(e) !== entryHash(before[0]!)),
  },
  { name: "adb.personalOpen", made: (s) => timedCall(s.r, "adb.personalOpen", { sub: "s1" }) },
  { name: "adb.personalJoin", made: (s) => timedCall(s.r, "adb.personalJoin", { sub: "s1" }) },
  {
    name: "signGrant",
    made: (s) => timedEffect(s, s.personal.signGrant("s1", { station: `ws/${A}`, request: "p", session: "k1", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why")),
    reads: true,
  },
  { name: "signRig", made: (s) => timedEffect(s, s.personal.signRig("s1", "settings", { v: 1 }, "why", `ws/${A}`)) },
];

for (const cond of CONDITIONS) {
  for (const c of CALLS) {
    test(`${c.name} answers within ASKED_MS, the person's station silent, ${cond.name}`, async (t) => {
      const s = await setUp();
      cloudAs(s.r, cond.mode);
      s.st.say.silent = true;
      const before = s.personal.entries("s1");
      const out = await c.made(s);
      t.diagnostic(`${c.name}, ${cond.name}: ${out.ms} ms`);
      answeredWithin(`${c.name}, ${cond.name}`, out, ASKED_MS + SLACK_MS);
      if (c.reads) assert.ok(!s.asked.includes("POST"), `nothing signed after the read: the station was asked ${s.asked.join()}`);
      if (c.signs) c.signs(s, before);
    });
  }

  test(`lock.removeDevice of an own device: its half on the person's lock within ASKED_MS, the person's station silent, ${cond.name}`, async (t) => {
    // `run`'s removeDevice: the device taken off the person's lock (one ASKED_MS of its own, PersonalLock.removeDevice),
    // then `keepToPerson`, then the workspace's lock read again within `run`'s ASKED_MS, begun there: two waits in all.
    // Left for the next change: the call's `keepToPerson` finds the one the person's lock's change began already there
    // and does nothing, so the device leaves the workspace's lock behind the call (75 s with the cloud answering, never
    // with its reads unanswered, measured 2026-11-12): not asserted here.
    const s = await setUp();
    cloudAs(s.r, cond.mode);
    s.st.say.silent = true;
    const before = s.personal.entries("s1");
    const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP });
    t.diagnostic(`lock.removeDevice, ${cond.name}: ${out.ms} ms`);
    answeredWithin(`lock.removeDevice, ${cond.name}`, out, 2 * ASKED_MS + SLACK_MS);
    onChain(`lock.removeDevice, ${cond.name}`, s, before.length + 1, isRemove(LAPTOP_KEY));
  });
}

test("stations that answer take what is signed, the cloud down entirely not waited on: a device taken off at once", async (t) => {
  const s = await setUp();
  cloudAs(s.r, "down");
  const out = await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY });
  t.diagnostic(`adb.personalRemove, the cloud down: ${out.ms} ms`);
  // (well within ASKED_MS: the station's answer, not the wait's end, is what it went on)
  answeredWithin("adb.personalRemove, the cloud down", out, ASKED_MS / 2);
  assert.ok(isRemove(LAPTOP_KEY)(s.st.kept.person.at(-1)!), "the station took it");
  assert.equal(entryHash(s.personal.entries("s1").at(-1)!), entryHash(s.st.kept.person.at(-1)!), "and it is pinned here");
});

test("a grant signed after the person took 10 s over its prompt: what is signed then is waited for at the stations, the cloud down, the station takes it", async (t) => {
  // signGrant's two waits: the read before the prompt, and what is signed after it. One wait begun at the read would be
  // over by the time the person answered, and the cloud alone would be what takes what is signed. Something to sign
  // after the prompt: this device says another key it signs workspaces' locks with (`#restate`).
  const s = await setUp();
  const OTHER = `ed25519:${"99".repeat(32)}`;
  signerKnown(s.inner, OTHER);
  const get = s.r.host.secureGet!;
  s.r.host.secureGet = (key, opts) => (opts.user ? Effect.andThen(Effect.sleep(10_000), get.call(s.r.host, key, opts)) : get.call(s.r.host, key, opts));
  cloudAs(s.r, "down");
  const before = s.personal.entries("s1").length;
  const out = await timedEffect(s, s.personal.signGrant("s1", { station: `ws/${A}`, request: "p", session: "k1", chat: "c", scope: "hour", exp: 2_000_000_000 }, "why"));
  t.diagnostic(`signGrant after a prompt of 10 s, the cloud down: ${out.ms} ms`);
  answeredWithin("signGrant after a prompt of 10 s, the cloud down", out, 10_000 + ASKED_MS / 2);
  assert.ok(out.ms! >= 10_000, `answered after ${out.ms} ms, before the person did`);
  const said = s.st.kept.person.at(-1)!;
  assert.deepEqual([said.kind, (said.body as { sign_key?: string }).sign_key], ["device", OTHER], "the station took what was signed");
  assert.equal(s.personal.entries("s1").length, before + 1);
  assert.equal(entryHash(s.personal.entries("s1").at(-1)!), entryHash(said), "and it is pinned here");
});

test("a read that lands past the call's wait is taken all the same: the call goes by the chain pinned, the longer one pinned as it comes", async (t) => {
  const s = await setUp();
  // The station keeps an entry this device has not heard of (another device of the person's signed it: here, with this
  // device's own key, as one of theirs would), and answers a read of it 5 s late.
  const pinned = s.personal.entries("s1");
  const seed = s.r.host.secure.get("personal-signer")!.value;
  const key = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  const e = { v: 1 as const, ws: personOf("s1"), seq: pinned.length, prev: entryHash(pinned.at(-1)!), at: Math.floor(s.r.host.nowMs() / 1000), kind: "device", body: { key: `ed25519:${"66".repeat(32)}`, id: "66".repeat(32), label: "tablet" } };
  const later: Entry = { ...e, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } };
  s.st.kept.person = [...pinned, later];
  s.st.say.personLate = 5_000;
  cloudAs(s.r, "all");
  const t0 = s.r.host.nowMs();
  const out = await timedEffect(s, s.personal.signRig("s1", "settings", { v: 1 }, "why", `ws/${A}`));
  t.diagnostic(`signRig, its read 5 s late: ${out.ms} ms`);
  answeredWithin("signRig, its read 5 s late", out, ASKED_MS + SLACK_MS);
  assert.equal(s.personal.entries("s1").length, pinned.length, "answered by the chain pinned");
  const at = await until(s.r, () => s.personal.entries("s1").length === pinned.length + 1);
  assert.ok(at !== null, "the longer chain pinned");
  const ms = s.r.host.nowMs() - t0;
  t.diagnostic(`the longer chain pinned at ${ms} ms`);
  assert.ok(ms >= 5_000 && ms <= 5_000 + SLACK_MS, `pinned at ${ms} ms`);
  assert.equal(entryHash(s.personal.entries("s1").at(-1)!), entryHash(later));
});
