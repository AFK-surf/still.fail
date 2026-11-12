// A person's own lock's calls that the person waits on (personal-lock.ts: a device taken off it, the lock begun anew,
// opened, joined, a phone's grant and a rig's call signed) wait on their stations for ASKED_MS at most a phase, and on
// the cloud's read no longer (2026-11-12: with the person's one station asleep, each took 15 s, joining 30 s; with the
// cloud's reads unanswered too, those that read never answered). Their station served the locks and then went silent
// (its machine asleep: asked, it neither answers nor closes), the cloud (a) answering everything, (b) leaving its reads
// unanswered: each answers within ASKED_MS a phase, what it signed pending (no station took it: not pinned, the cloud not
// sent it; src/lock-pending.ts), but a lock begun anew, which the cloud takes as before. What this device takes off or
// puts on their lock is so in the workspace's lock where they bound it within one phase more, pending there too, before
// the call answers (views/lock.ts `takeOffBound`, `putOnBound`). Stations that answer still take what is signed, the
// cloud not waited on; a read that lands past the wait is taken.
//
// Each case in a workspace of its own, locked, this device (ME) signing for its owner s1 and on s1's own lock with
// their laptop, that lock bound in the workspace's.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { type Entry, type Head, entryHash, signedBytes } from "../src/lock.ts";
import { personOf } from "../src/personal-lock.ts";
import { hex } from "../src/util.ts";
import { ASKED_MS, bindPerson, fold, held, keepToPerson, onBoundPerson, pendingHeld, read, signerKnown, withBound } from "../src/views/lock.ts";
import { serveTrusted, tryOne } from "../src/views/pair.ts";
import { call } from "./helpers.ts";
import { ME, PHONE, genesis, grant, pipe, rig } from "./lock-rig.ts";
import { jsonResponse } from "../src/testing.ts";
import { stationLater, stationReplies } from "./station-fixture.ts";

/// The workspace's one station, which keeps the person's own lock too.
const A = "aa".repeat(32);
/// The owner's laptop: an app device of theirs in the workspace's lock and on their own.
const LAPTOP = "77".repeat(32);
const LAPTOP_KEY = `ed25519:${"55".repeat(32)}`;
const LAPTOP_SIGNS = `ed25519:${"22".repeat(32)}`;
/// A new device of theirs, approved face to face into their own lock.
const NEW = "88".repeat(32);
const NEW_KEY = `ed25519:${"44".repeat(32)}`;
const NEW_SIGNS = `ed25519:${"33".repeat(32)}`;
/// A second device of the owner's, on both locks where `setUp` is asked for it.
const TABLET = "66".repeat(32);
const TABLET_KEY = `ed25519:${"67".repeat(32)}`;
const TABLET_SIGNS = `ed25519:${"68".repeat(32)}`;
/// How long a call is given before it is said to have no answer.
const LIMIT_MS = 120_000;
/// Past a wait, what a call may take on this clock: it is stepped 10 ms at a time and an answer is seen at the end of
/// a step; what follows the wait (the entry's POST to the cloud, its answer, the call's answer to the UI) is answered
/// within a step or a few here.
const SLACK_MS = 50;

type Rig = Awaited<ReturnType<typeof rig>>;

/// A station of the locks as station/src/mesh/serve.ts answers it (as lock-calls-answer.test.ts's), keeping the
/// person's own lock too (GET/POST /lock/person); `silent`: asked, it never answers; `personLate`: its reads of the
/// person's lock answered that many ms late; `refused`: how many entries it refused (409), one at a place it holds
/// another at, as `takeLock` does; `lateUntil`: till then (the clock's ms, `now`) what it is asked is held, and
/// answered then (its link coming back, as a station just started anew: the tests of stations late, at the end);
/// `personSilent`: what it is asked of the person's lock never answered, the workspace's answered.
function station(first: Entry, now: () => number) {
  const chain: Entry[] = [first];
  const kept = { person: [] as Entry[] };
  const say = { silent: false, personSilent: false, personLate: 0, refused: 0, lateUntil: 0 };
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const answer = (method: string, path: string, body: unknown): Effect.Effect<unknown, CoreError> => {
    if (say.silent || (say.personSilent && path === "/lock/person")) return Effect.never;
    if (now() < say.lateUntil) return Effect.andThen(Effect.sleep(say.lateUntil - now()), Effect.suspend(() => answer(method, path, body)));
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return Effect.succeed({ head: head(), entries: chain.filter((e) => e.seq > after), ...serves });
    }
    if (method === "POST" && path === "/lock") {
      for (const e of (body as { entries?: Entry[] }).entries ?? []) {
        if (e.seq === chain.length && e.prev === entryHash(chain.at(-1)!)) chain.push(e);
        else if (chain[e.seq] === undefined || entryHash(chain[e.seq]!) !== entryHash(e)) {
          say.refused++;
          return Effect.fail(new CoreError("lock_refused", "another entry at that place", 409));
        }
      }
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
/// device's person's own lock begun here with LAPTOP put on it, and bound in the workspace's lock. `tablet`: TABLET too,
/// in the workspace's lock and on the person's. `phone`: PHONE, the member s2's, in the workspace's lock.
async function setUp({ tablet = false, phone = false } = {}) {
  const g = grant();
  const more = [
    { id: LAPTOP, sub: "s1", kind: "app", label: "laptop", sign_key: LAPTOP_SIGNS },
    ...(tablet ? [{ id: TABLET, sub: "s1", kind: "app", label: "tablet", sign_key: TABLET_SIGNS }] : []),
    ...(phone ? [{ id: PHONE, sub: "s2", kind: "app", label: "Pixel 8" }] : []),
  ];
  const r = await rig((signer) => ({ ws: genesis("ws", signer, true, [{ key: A, name: "a" }], g.keys, ME, more) }), undefined, A);
  const inner = r.core.inner;
  const st = station(r.cloud.chains.get("ws")![0]!, () => r.host.nowMs());
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
    await r.host.time.passUntil(5000, () => done);
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
  if (tablet) await run(personal.addDevice("s1", { key: TABLET_KEY, id: TABLET, label: "tablet", sign_key: TABLET_SIGNS }, "why"));
  await run(read(inner, "ws"));
  await run(bindPerson(inner, "ws"));
  await run(read(inner, "ws"));
  await run(keepToPerson(inner, "ws"));
  await r.host.time.pass(1000);
  assert.equal(personal.standing("s1"), "member");
  assert.equal(onBoundPerson(inner, "ws"), true, "bound");
  assert.deepEqual(st.kept.person.map((e) => e.kind), ["genesis", "device", ...(tablet ? ["device"] : [])], "the station keeps the person's lock");
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

/// What the call signed, no station taking it: pending on the person's lock (shown, waiting), the chain pinned and the
/// cloud's as they were (`before`).
function pendingOnPerson(what: string, s: Setup, before: Entry[]) {
  assert.deepEqual(s.personal.entries("s1").map(entryHash), before.map(entryHash), `${what}: not pinned`);
  assert.equal(s.personCloud.entries.length, before.length, `${what}: the cloud not sent it`);
  assert.deepEqual(s.personal.view("s1").pending.map((p: { state: string }) => p.state), ["waiting"], `${what}: pending`);
}

/// What the call signed in the workspace's lock, no station taking it: pending there (`is` of it), the chain held and
/// the cloud's as they were (`before` the cloud's length).
function pendingInWorkspace(what: string, s: Setup, before: number, is: (e: Entry) => boolean) {
  assert.equal(s.r.cloud.chains.get("ws")!.length, before, `${what}: the cloud not sent the workspace's`);
  assert.ok(pendingHeld(s.inner, "ws").some((p) => p.state === "waiting" && is(p.entry)), `${what}: pending in the workspace's lock`);
}

const isRemove = (key: string) => (e: Entry) => e.kind === "device.remove" && (e.body as { key?: string }).key === key;
const isOut = (id: string) => (e: Entry) => e.kind === "device.remove" && (e.body as { id?: string }).id === id;

/// The laptop out of the workspace's lock as held here, and its `device.remove` on the cloud's chain of it (`before`
/// that chain's length before the call).
function outOfWorkspace(what: string, s: Setup, before: number) {
  assert.equal(fold(held(s.inner, "ws")!.entries).devices.has(LAPTOP), false, `${what}: out of the workspace's lock held here`);
  assert.ok(s.r.cloud.chains.get("ws")!.slice(before).some(isOut(LAPTOP)), `${what}: its device.remove on the cloud's chain for the workspace`);
}

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
/// `adb.personalRemove` takes the device out of the workspace's lock too (views/lock.ts `takeOffBound`, a phase of its
/// own after the person's lock's): two ASKED_MS, and the device out of the workspace's lock at the answer.
const CALLS: { name: string; made: (s: Setup) => Promise<{ ms: number | null; ok: boolean; said: unknown }>; signs?: (s: Setup, before: Entry[], ws: number) => void; reads?: true; phases?: number }[] = [
  {
    name: "adb.personalRemove",
    made: (s) => timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY }),
    signs: (s, before, ws) => {
      pendingOnPerson("adb.personalRemove", s, before);
      assert.equal(fold(held(s.inner, "ws")!.entries).devices.has(LAPTOP), true, "in the workspace's lock held still");
      pendingInWorkspace("adb.personalRemove", s, ws, isOut(LAPTOP));
    },
    phases: 2,
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
    test(`${c.name} answers within ASKED_MS a phase, the person's station silent, ${cond.name}`, async (t) => {
      const s = await setUp();
      cloudAs(s.r, cond.mode);
      s.st.say.silent = true;
      const before = s.personal.entries("s1");
      const ws = s.r.cloud.chains.get("ws")!.length;
      const out = await c.made(s);
      t.diagnostic(`${c.name}, ${cond.name}: ${out.ms} ms`);
      answeredWithin(`${c.name}, ${cond.name}`, out, (c.phases ?? 1) * ASKED_MS + SLACK_MS);
      if (c.reads) assert.ok(!s.asked.includes("POST"), `nothing signed after the read: the station was asked ${s.asked.join()}`);
      if (c.signs) c.signs(s, before, ws);
    });
  }

  test(`lock.removeDevice of an own device answers within two ASKED_MS, out of the workspace's lock at the answer, the person's station silent, ${cond.name}`, async (t) => {
    // `run`'s removeDevice: the device taken off the person's lock (PersonalLock.removeDevice, one ASKED_MS), then out of
    // the workspace's (views/lock.ts `takeOffBound`, one more, its read after the call's last): two waits in all
    // (2026-11-12: 18 s, the device listed in the workspace's lock 57 s more with the cloud answering, for good with its
    // reads unanswered).
    const s = await setUp();
    cloudAs(s.r, cond.mode);
    s.st.say.silent = true;
    const before = s.personal.entries("s1");
    const ws = s.r.cloud.chains.get("ws")!.length;
    const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP });
    t.diagnostic(`lock.removeDevice, ${cond.name}: ${out.ms} ms`);
    answeredWithin(`lock.removeDevice, ${cond.name}`, out, 2 * ASKED_MS + SLACK_MS);
    pendingOnPerson(`lock.removeDevice, ${cond.name}`, s, before);
    pendingInWorkspace(`lock.removeDevice, ${cond.name}`, s, ws, isOut(LAPTOP));
  });

  test(`a device approved face to face into the person's lock answers within two ASKED_MS, on their lock and in the workspace's, the person's station silent, ${cond.name}`, async (t) => {
    // views/pair.ts `approve`, its person's branch: put on the person's lock (PersonalLock.addDevice, one ASKED_MS),
    // then in the workspace's where they bound it (views/lock.ts `putOnBound`, one more): two waits (2026-11-12: 60 s,
    // and no answer with the cloud's reads unanswered).
    const s = await setUp();
    const prompts = await s.r.watch({ topic: "lockPrompts" });
    const [trusted, phone] = await pipe();
    s.inner.runner.fork(serveTrusted(s.inner, NEW, ME, trusted));
    const hello = await s.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel 9", sign_key: NEW_SIGNS, personal: { subs: ["s1"], key: NEW_KEY } }), phone.next()));
    assert.deepEqual(hello, { t: "code", workspaces: ["person:s1"] });
    const code = (await prompts()).pairing.find((p: { device: string }) => p.device === NEW).code as string;
    cloudAs(s.r, cond.mode);
    s.st.say.silent = true;
    const before = s.personal.entries("s1");
    const ws = s.r.cloud.chains.get("ws")!.length;
    const out = await timedEffect(s, tryOne(s.inner, { id: ME, d: phone, workspaces: ["person:s1"] }, NEW, code));
    t.diagnostic(`approved face to face, ${cond.name}: ${out.ms} ms`);
    answeredWithin(`approved face to face, ${cond.name}`, out, 2 * ASKED_MS + SLACK_MS);
    pendingOnPerson(`approved face to face, ${cond.name}`, s, before);
    pendingInWorkspace(`approved face to face, ${cond.name}`, s, ws, (e) => e.kind === "device" && (e.body as { id?: string; sign_key?: string }).id === NEW && (e.body as { sign_key?: string }).sign_key === NEW_SIGNS);
    // (the new device given the chain with its entry on, to pin and bring to the stations itself)
    const chains = (out.said as { approved?: { chains?: Record<string, Entry[]> } } | undefined)?.approved?.chains;
    assert.ok(chains?.s1?.some((e) => e.kind === "device" && (e.body as { key?: string }).key === NEW_KEY), JSON.stringify(out.said).slice(0, 200));
    // (and the answer says it is pending, its row: the app says its sentence in place of its done words)
    const pending = (out.said as { approved?: { t?: string; pending?: { state: string; text: string } } } | undefined)?.approved;
    assert.equal(pending?.t, "approved");
    assert.equal(pending?.pending?.state, "waiting", JSON.stringify(out.said).slice(0, 300));
    assert.match(pending!.pending!.text, /^批准设备 Pixel 9：已记下，等 .+ 上线后生效$/);
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

test("an own device taken off with the cloud down entirely: the station takes both entries, the cloud not waited on, nothing left failing", async (t) => {
  const s = await setUp();
  const defects: unknown[] = [];
  s.inner.runner.onDefect = (error) => { defects.push(error); };
  cloudAs(s.r, "down");
  const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP });
  t.diagnostic(`lock.removeDevice, the cloud down: ${out.ms} ms`);
  answeredWithin("lock.removeDevice, the cloud down", out, ASKED_MS / 2);
  assert.ok(isRemove(LAPTOP_KEY)(s.st.kept.person.at(-1)!), "the station took the person's entry");
  assert.ok(s.st.chain.some(isOut(LAPTOP)), "and the workspace's");
  assert.equal(fold(held(s.inner, "ws")!.entries).devices.has(LAPTOP), false, "out of the workspace's lock held here");
  // (the person's lock's change began `keepToPerson` too, which may sign the same: one of the two is taken)
  await s.r.host.time.pass(30_000);
  assert.equal(s.st.chain.filter(isOut(LAPTOP)).length, 1, "one device.remove of it at the station");
  assert.deepEqual(defects, []);
});

test("a device taking itself off its person's lock signs nothing in the workspace's", async (t) => {
  const s = await setUp();
  cloudAs(s.r, "all");
  const mine = [...s.personal.chain("s1")!.devices.values()].find((d) => d.id === ME)!;
  const station = s.st.chain.length;
  const cloud = s.r.cloud.chains.get("ws")!.length;
  const out = await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: mine.key });
  t.diagnostic(`adb.personalRemove of itself: ${out.ms} ms`);
  answeredWithin("adb.personalRemove of itself", out, ASKED_MS + SLACK_MS);
  assert.ok(isRemove(mine.key)(s.st.kept.person.at(-1)!), "taken off the person's lock");
  assert.equal(s.personal.standing("s1"), "outside");
  await s.r.host.time.pass(1000);
  assert.equal(s.st.chain.length, station, "nothing signed in the workspace's lock at the station");
  assert.equal(s.r.cloud.chains.get("ws")!.length, cloud, "nor at the cloud");
});

/// The cloud answering all, its POSTs of the workspace's lock counted.
function cloudCounting(r: Rig) {
  const posts = { lock: 0 };
  stationLater(r.host, (req) => {
    if (req.method === "POST" && new URL(req.url).pathname === "/v1/workspaces/ws/lock") posts.lock++;
    return undefined;
  });
  return posts;
}

test("an own device taken off, stations and the cloud answering: one device.remove of it in the workspace's lock, at the station and the cloud, nothing refused, nothing left failing", async (t) => {
  // This device signs it once (`takeOffBound`); `keepToPerson`, started as the person's lock changed, does nothing
  // until that is done (`withBound`) and then finds it done. Two of them signing at one place, the one the station
  // refused would go to the cloud's POST.
  const s = await setUp();
  const defects: unknown[] = [];
  s.inner.runner.onDefect = (error) => { defects.push(error); };
  const posts = cloudCounting(s.r);
  const cloud = s.r.cloud.chains.get("ws")!.length;
  const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP });
  t.diagnostic(`lock.removeDevice, all answering: ${out.ms} ms`);
  answeredWithin("lock.removeDevice, all answering", out, ASKED_MS / 2);
  await s.r.host.time.pass(30_000);
  assert.equal(s.st.chain.filter(isOut(LAPTOP)).length, 1, "one device.remove of it at the station");
  assert.equal(s.r.cloud.chains.get("ws")!.filter(isOut(LAPTOP)).length, 1, "and at the cloud");
  assert.equal(s.st.say.refused, 0, "nothing refused at the station");
  assert.equal(posts.lock, 1, "the cloud sent the one entry, as the station took it");
  assert.equal(s.r.cloud.chains.get("ws")!.length, cloud + 1);
  assert.deepEqual(defects, []);
});

test("a device approved face to face, stations and the cloud answering: one device entry of it in the workspace's lock, at the station and the cloud, nothing refused, nothing left failing", async (t) => {
  const s = await setUp();
  const defects: unknown[] = [];
  s.inner.runner.onDefect = (error) => { defects.push(error); };
  const prompts = await s.r.watch({ topic: "lockPrompts" });
  const [trusted, phone] = await pipe();
  s.inner.runner.fork(serveTrusted(s.inner, NEW, ME, trusted));
  const hello = await s.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel 9", sign_key: NEW_SIGNS, personal: { subs: ["s1"], key: NEW_KEY } }), phone.next()));
  assert.deepEqual(hello, { t: "code", workspaces: ["person:s1"] });
  const code = (await prompts()).pairing.find((p: { device: string }) => p.device === NEW).code as string;
  const posts = cloudCounting(s.r);
  const isIn = (e: Entry) => e.kind === "device" && (e.body as { id?: string }).id === NEW;
  const out = await timedEffect(s, tryOne(s.inner, { id: ME, d: phone, workspaces: ["person:s1"] }, NEW, code));
  t.diagnostic(`approved face to face, all answering: ${out.ms} ms`);
  answeredWithin("approved face to face, all answering", out, ASKED_MS / 2);
  await s.r.host.time.pass(30_000);
  assert.equal(s.st.chain.filter(isIn).length, 1, "one device entry of it at the station");
  assert.equal(s.r.cloud.chains.get("ws")!.filter(isIn).length, 1, "and at the cloud");
  assert.equal(s.st.say.refused, 0, "nothing refused at the station");
  assert.equal(posts.lock, 1, "the cloud sent the one entry, as the station took it");
  assert.deepEqual(defects, []);
});

test("keepToPerson while this device does the workspaces' half itself does nothing and takes no key, and runs once that is over", async () => {
  // The tablet taken off the person's lock with the marker up (as `run` and adb.ts take a device off, here without the
  // explicit act): nothing takes it out of the workspace's lock until the marker comes down, `keepToPerson` asked
  // directly meanwhile too; then the one run as it comes down does, for the same heads (no key was taken).
  const s = await setUp({ tablet: true });
  cloudAs(s.r, "all");
  const gate = Deferred.makeUnsafe<void>();
  let over = false;
  s.inner.runner.fork(Effect.ensuring(withBound(s.inner, "s1", Effect.andThen(s.personal.removeDevice("s1", TABLET_KEY, "why"), Deferred.await(gate))), Effect.sync(() => void (over = true))));
  await s.r.host.time.pass(1000);
  assert.ok(isRemove(TABLET_KEY)(s.personal.entries("s1").at(-1)!), "off the person's lock");
  await s.run(keepToPerson(s.inner, "ws"));
  await s.r.host.time.pass(1000);
  assert.equal(fold(held(s.inner, "ws")!.entries).devices.has(TABLET), true, "still in the workspace's lock while the marker is up");
  assert.equal(s.st.chain.filter(isOut(TABLET)).length, 0);
  Deferred.doneUnsafe(gate, Effect.void);
  await s.r.host.time.pass(1000);
  assert.ok(over);
  assert.equal(fold(held(s.inner, "ws")!.entries).devices.has(TABLET), false, "out of the workspace's lock once it came down");
  assert.equal(s.st.chain.filter(isOut(TABLET)).length, 1, "taken out at the station, once");
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

// ── stations late ──
// Past a call's wait what no station took is pending, and the stations still listened to (views/lock.ts ASKED_MS).
// 2026-11-12: the cloud frozen and the station just started anew, its link back 10 s later, a device let in face to
// face was never answered: the call had stopped listening to the stations at 3 s. The station here holds what it is
// asked for 10 s and answers it then; the cloud is down (nothing answered) or refuses at once (503): each call answers
// pending at its waits' end, and what it signed is held as the station takes it, at about 10 s, pending no more.

/// How long past the station's answer at 10 s a call may take: its answer is seen at the end of a 10 ms step, and the
/// calls in two phases (the person's lock, then the workspace's) read and sign the second at once, the station
/// answering then.
const LATE_SLACK_MS = 100;

/// The cloud answering nothing, or 503 to everything at once.
function cloudFailing(r: Rig, how: "down" | "503") {
  stationLater(r.host, () => (how === "down" ? new Promise(() => {}) : Promise.resolve(jsonResponse(503, { error: "down" }))));
}

/// What each call is, what it leaves at the station; `approve`: the face-to-face approval, its code shown before.
const LATE: { name: string; made: (s: Setup, approve: (() => Promise<{ ms: number | null; ok: boolean; said: unknown }>) | null) => Promise<{ ms: number | null; ok: boolean; said: unknown }>; took: (s: Setup) => boolean; approve?: true }[] = [
  {
    name: "lock.removeDevice of another's device (the workspace's lock)",
    made: (s) => timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: PHONE }),
    took: (s) => s.st.chain.some(isOut(PHONE)),
  },
  {
    name: "adb.personalRemove",
    made: (s) => timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY }),
    took: (s) => isRemove(LAPTOP_KEY)(s.st.kept.person.at(-1)!) && s.st.chain.some(isOut(LAPTOP)),
  },
  {
    name: "lock.removeDevice of an own device",
    made: (s) => timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP }),
    took: (s) => isRemove(LAPTOP_KEY)(s.st.kept.person.at(-1)!) && s.st.chain.some(isOut(LAPTOP)),
  },
  {
    name: "a device approved face to face into the person's lock",
    made: (_s, approve) => approve!(),
    took: (s) => s.st.kept.person.some((e) => e.kind === "device" && (e.body as { key?: string }).key === NEW_KEY) && s.st.chain.some((e) => e.kind === "device" && (e.body as { id?: string }).id === NEW),
    approve: true,
  },
];

for (const how of ["down", "503"] as const) {
  for (const c of LATE) {
    test(`${c.name}: the station answering from 10 s, the cloud ${how === "down" ? "down entirely" : "answering 503"}, done as the station takes it`, async (t) => {
      const s = await setUp({ phone: true });
      let approve: (() => Promise<{ ms: number | null; ok: boolean; said: unknown }>) | null = null;
      if (c.approve) {
        const prompts = await s.r.watch({ topic: "lockPrompts" });
        const [trusted, phone] = await pipe();
        s.inner.runner.fork(serveTrusted(s.inner, NEW, ME, trusted));
        const hello = await s.run(Effect.andThen(phone.send({ t: "hello", v: 1, workspaces: [], kind: "app", label: "Pixel 9", sign_key: NEW_SIGNS, personal: { subs: ["s1"], key: NEW_KEY } }), phone.next()));
        assert.deepEqual(hello, { t: "code", workspaces: ["person:s1"] });
        const code = (await prompts()).pairing.find((p: { device: string }) => p.device === NEW).code as string;
        approve = () => timedEffect(s, tryOne(s.inner, { id: ME, d: phone, workspaces: ["person:s1"] }, NEW, code));
      }
      cloudFailing(s.r, how);
      s.st.say.lateUntil = s.r.host.nowMs() + 10_000;
      const out = await c.made(s, approve);
      t.diagnostic(`${c.name}, the cloud ${how}: ${out.ms} ms`);
      answeredWithin(`${c.name}, the cloud ${how}`, out, 2 * ASKED_MS + LATE_SLACK_MS);
      await s.r.host.time.pass(10_000 + LATE_SLACK_MS - out.ms!);
      assert.ok(c.took(s), `${c.name}: the station holds what was signed`);
      assert.equal(pendingHeld(s.inner, "ws").length, 0, `${c.name}: nothing pending in the workspace's lock`);
      assert.deepEqual(s.personal.view("s1").pending, [], `${c.name}: nor in the person's`);
    });
  }
}

test("the cloud's POST slow (5 s), the station answering from 4 s: pending at 3 s, taken at 4 s, the cloud sent it then and not waited for", async (t) => {
  const s = await setUp({ phone: true });
  const inner = s.inner;
  stationLater(s.r.host, (req) => (req.method === "POST" && new URL(req.url).pathname === "/v1/workspaces/ws/lock"
    ? new Promise((done) => void inner.runner.fork(Effect.andThen(Effect.sleep(5_000), Effect.sync(() => done(jsonResponse(200, s.r.cloud.reply(req)))))))
    : undefined));
  s.st.say.lateUntil = s.r.host.nowMs() + 4_000;
  const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: PHONE });
  t.diagnostic(`lock.removeDevice, station at 4 s, the cloud at 5 s: ${out.ms} ms`);
  answeredWithin("lock.removeDevice, station at 4 s", out, ASKED_MS + SLACK_MS);
  await s.r.host.time.pass(1_000 + SLACK_MS);
  assert.ok(s.st.chain.some(isOut(PHONE)), "the station took it");
  assert.equal(pendingHeld(inner, "ws").length, 0);
  // (the cloud sent it once the station took it, and keeps it as its slow answer comes)
  await s.r.host.time.pass(6_000);
  assert.ok(s.r.cloud.chains.get("ws")!.some(isOut(PHONE)), "and the cloud, behind");
});

// ── pending ──
// What no station of the person's took by the call's wait is pending on their lock (personal-lock.ts `#pend`): kept
// beside the lock on the device, brought to their stations as one is next read (`#deliver`), as it is while its parent
// is the head pinned; where the head moved, it needs the seed to be signed again, which a delivery does not have: it
// fails, saying to look and do it again.

test("a person's lock: pending while their station is silent, kept on the device, and taken as the station is next read", async () => {
  const s = await setUp();
  cloudAs(s.r, "all");
  s.st.say.silent = true;
  const before = s.personal.entries("s1");
  const out = await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY });
  answeredWithin("adb.personalRemove, silent", out, 2 * ASKED_MS + SLACK_MS);
  pendingOnPerson("adb.personalRemove, silent", s, before);
  const kept = await Effect.runPromise(s.r.host.storageGet(`personal-lock-pending-${hex(new TextEncoder().encode("s1"))}`));
  assert.ok(kept !== null, "kept on the device");
  s.st.say.silent = false;
  await s.run(s.personal.refresh("s1"));
  await s.r.host.time.pass(1_000);
  assert.ok(isRemove(LAPTOP_KEY)(s.st.kept.person.at(-1)!), "the station took it");
  assert.ok(isRemove(LAPTOP_KEY)(s.personal.entries("s1").at(-1)!), "pinned here");
  assert.deepEqual(s.personal.view("s1").pending, []);
});

test("a person's lock: the head moved while pending, no seed in hand: failed, said so; dismissed, gone", async () => {
  const s = await setUp();
  cloudAs(s.r, "all");
  s.st.say.silent = true;
  await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY });
  // Another device of theirs put a tablet on meanwhile (signed with this device's key here, as one of theirs would).
  const pinned = s.personal.entries("s1");
  const seed = s.r.host.secure.get("personal-signer")!.value;
  const key = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  const e = { v: 1 as const, ws: personOf("s1"), seq: pinned.length, prev: entryHash(pinned.at(-1)!), at: Math.floor(s.r.host.nowMs() / 1000), kind: "device", body: { key: `ed25519:${"66".repeat(32)}`, id: "66".repeat(32), label: "tablet" } };
  s.st.kept.person = [...pinned, { ...e, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } }];
  s.st.say.silent = false;
  await s.run(s.personal.refresh("s1"));
  await s.r.host.time.pass(1_000);
  const rows = s.personal.view("s1").pending as { id: string; state: string; text: string }[];
  assert.deepEqual(rows.map((r) => r.state), ["failed"]);
  assert.match(rows[0]!.text, /没有生效/);
  assert.ok(!s.st.kept.person.some(isRemove(LAPTOP_KEY)), "nothing brought");
  await timedCall(s.r, "adb.personalPendingDismiss", { sub: "s1", id: rows[0]!.id });
  assert.deepEqual(s.personal.view("s1").pending, []);
});

// ── one safe mode ──
// To people there is one safe mode (the root AGENTS.md): what is pending of the person's own lock is said on the
// workspace's `lock` topic too (设置 › 安全, the one page that shows what is pending), its id saying whose
// (`own:`), one done in both once. 2026-11-12: an own device removed there with only the person's lock's station
// silent was pending on that lock alone, said only on `adbShare`, which that page does not read. (The topic is watched
// after a `timedCall`, which takes every message the core sent, its changes too.)

type Row = { id: string; state: string; text: string; stations: string[] };

test("an own device removed, only its own lock's entry pending: the workspace's lock topic lists it, waiting, its stations named; taken, gone", async () => {
  const s = await setUp();
  cloudAs(s.r, "all");
  s.st.say.personSilent = true;
  const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP });
  answeredWithin("lock.removeDevice, the person's lock silent", out, 2 * ASKED_MS + SLACK_MS);
  const lock = await s.r.watch({ topic: "lock", workspace: "ws" });
  assert.ok(s.st.chain.some(isOut(LAPTOP)), "out of the workspace's lock: the station took it");
  assert.equal(pendingHeld(s.inner, "ws").length, 0, "nothing pending in the workspace's");
  assert.deepEqual(s.personal.view("s1").pending.map((p: Row) => p.state), ["waiting"], "pending on the person's");
  const rows = (await lock()).pending as Row[];
  assert.deepEqual(rows.map((r) => [r.id.startsWith("own:"), r.state, r.stations]), [[true, "waiting", ["studio"]]], JSON.stringify(rows));
  assert.match(rows[0]!.text, /laptop/);
  assert.equal((out.said as { pending?: Row }).pending?.id, rows[0]!.id, "the call answers with the row the topic shows");
  // Its station answering again: taken, gone from the topic.
  s.st.say.personSilent = false;
  await s.run(s.personal.refresh("s1"));
  await s.r.host.time.pass(1_000);
  assert.ok(isRemove(LAPTOP_KEY)(s.st.kept.person.at(-1)!), "the station took it");
  assert.deepEqual((await lock()).pending, []);
});

test("an own device removed, pending in both locks: one row on the workspace's lock topic, the workspace's", async () => {
  const s = await setUp();
  cloudAs(s.r, "all");
  s.st.say.silent = true;
  const out = await timedCall(s.r, "lock.removeDevice", { workspace: "ws", device: LAPTOP });
  answeredWithin("lock.removeDevice, silent", out, 2 * ASKED_MS + SLACK_MS);
  const lock = await s.r.watch({ topic: "lock", workspace: "ws" });
  assert.equal(s.personal.view("s1").pending.length, 1);
  const rows = (await lock()).pending as Row[];
  assert.deepEqual(rows.map((r) => [r.id, r.state]), [[pendingHeld(s.inner, "ws")[0]!.id, "waiting"]], JSON.stringify(rows));
});

test("a failed change to the person's own lock, on the workspace's lock topic: dismissed through lock.pendingDismiss", async () => {
  const s = await setUp();
  cloudAs(s.r, "all");
  s.st.say.silent = true;
  await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY });
  const lock = await s.r.watch({ topic: "lock", workspace: "ws" });
  // Another device of theirs put a tablet on meanwhile: the head moved, and with no seed in hand it fails.
  const pinned = s.personal.entries("s1");
  const seed = s.r.host.secure.get("personal-signer")!.value;
  const key = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  const e = { v: 1 as const, ws: personOf("s1"), seq: pinned.length, prev: entryHash(pinned.at(-1)!), at: Math.floor(s.r.host.nowMs() / 1000), kind: "device", body: { key: `ed25519:${"66".repeat(32)}`, id: "66".repeat(32), label: "tablet" } };
  s.st.kept.person = [...pinned, { ...e, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } }];
  s.st.say.silent = false;
  await s.run(s.personal.refresh("s1"));
  await s.run(read(s.inner, "ws"));
  await s.r.host.time.pass(1_000);
  assert.equal(pendingHeld(s.inner, "ws").length, 0, "the workspace's taken");
  const rows = (await lock()).pending as Row[];
  assert.deepEqual(rows.map((r) => [r.id.startsWith("own:"), r.state]), [[true, "failed"]], JSON.stringify(rows));
  await s.r.ask("lock.pendingDismiss", { workspace: "ws", id: rows[0]!.id });
  assert.deepEqual((await lock()).pending, []);
  assert.deepEqual(s.personal.view("s1").pending, []);
});

// ── what failed says ──
// A pending entry whose parent is no longer the head pinned fails where no seed is in hand (`#deliver`): named as
// changed meanwhile only where its own subject was (`againOf` `otherwise`); where the lock moved and its subject did not,
// what changed is their trusted devices (2026-11-13: 「移除设备 laptop没有生效：laptop刚被另一台设备改过」 though the
// laptop was not touched, a tablet approved meanwhile; and the name ran into the words).

/// An entry the station keeps after the chain pinned, signed by this device's key as another device of theirs would.
function theirsOnPerson(s: Setup, kind: string, body: unknown) {
  const pinned = s.personal.entries("s1");
  const seed = s.r.host.secure.get("personal-signer")!.value;
  const key = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  const e = { v: 1 as const, ws: personOf("s1"), seq: pinned.length, prev: entryHash(pinned.at(-1)!), at: Math.floor(s.r.host.nowMs() / 1000), kind, body };
  s.st.kept.person = [...pinned, { ...e, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } }];
}

for (const c of [
  { name: "another device put on meanwhile, the laptop untouched: their trusted devices said changed", body: { key: `ed25519:${"66".repeat(32)}`, id: "66".repeat(32), label: "tablet" }, says: "移除设备 laptop：没有生效。另一台设备刚改过受信任设备，请查看现在的状态，仍然需要的话再操作一次" },
  { name: "the laptop itself changed meanwhile (renamed): it said changed", body: { key: LAPTOP_KEY, id: LAPTOP, label: "renamed", sign_key: LAPTOP_SIGNS }, says: "移除设备 laptop：没有生效。另一台设备刚改过「laptop」，请查看现在的状态，仍然需要的话再操作一次" },
]) {
  test(`a person's lock, pending, the head moved, no seed in hand: ${c.name}`, async () => {
    const s = await setUp();
    cloudAs(s.r, "all");
    s.st.say.silent = true;
    await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY });
    theirsOnPerson(s, "device", c.body);
    s.st.say.silent = false;
    await s.run(s.personal.refresh("s1"));
    await s.r.host.time.pass(1_000);
    const rows = s.personal.view("s1").pending as { state: string; text: string }[];
    assert.deepEqual(rows.map((r) => r.state), ["failed"]);
    assert.equal(rows[0]!.text, c.says);
  });
}

// ── a station gone for good ──
// The person's one station taken out of their one workspace: no station of theirs is left to ask, so what was pending
// on their own lock is the cloud's then (personal-lock.ts `#deliver`, told as the workspace's view changes), as a new
// entry with none to ask is (2026-11-13: it waited for good).

test("the person's one station gone for good, taken out of their workspace: an own device's removal pending for it is the cloud's then, pinned, nothing pending", async () => {
  const s = await setUp();
  s.st.say.silent = true;
  const before = s.personal.entries("s1");
  const out = await timedCall(s.r, "adb.personalRemove", { sub: "s1", key: LAPTOP_KEY });
  answeredWithin("adb.personalRemove, silent", out, 2 * ASKED_MS + SLACK_MS);
  pendingOnPerson("adb.personalRemove, silent", s, before);
  // (the cloud from now on: the station's removal taken, the workspace's view without it)
  stationLater(s.r.host, (req) => {
    const path = new URL(req.url).pathname;
    if (req.method === "DELETE" && path === `/v1/workspaces/ws/stations/${A}`) return Promise.resolve(jsonResponse(200, { ok: true }));
    if (req.method === "GET" && path === "/v1/workspaces/ws") return Promise.resolve(jsonResponse(200, { id: "ws", name: "W", role: "owner", lock: s.r.cloud.head("ws"), lock_requests: 0, stations: [] }));
    return undefined;
  });
  const gone = await timedCall(s.r, "workspace.removeStation", { account: "s1", workspace: "ws", station: A });
  assert.ok(gone.ok, JSON.stringify(gone.said));
  await s.r.host.time.pass(1_000);
  assert.deepEqual(s.personal.view("s1").pending, []);
  assert.ok(isRemove(LAPTOP_KEY)(s.personal.entries("s1").at(-1)!), "pinned");
  assert.ok(isRemove(LAPTOP_KEY)(s.personCloud.entries.at(-1)!), "the cloud keeps it");
  assert.deepEqual(pendingHeld(s.inner, "ws"), [], "and the workspace's removal of it taken too");
});
