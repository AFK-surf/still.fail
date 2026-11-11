// What a person's other device holds of a station that is down (views/device-cache.ts): it answers only its own person's
// device the lock names, with a credential for that endpoint and a session that stands, only of the workspace proved; the
// device that asks takes what it lacks, the station's own coming back goes on from there. Every core here runs on one
// simulated clock (SimTime), the devices meet on a simulated network (sim-iroh.ts) on it: a test moves that clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { SOON_MS } from "../src/data.ts";
import { CoreError, HostError } from "../src/error.ts";
import type { IrohEndpoint } from "../src/iroh.ts";
import { wrapIroh } from "../src/iroh-bindings.ts";
import { HostWire } from "../src/station/wire.ts";
import type { FakeHost, HostTime } from "../src/testing.ts";
import * as format from "../src/format.ts";
import { t } from "../src/i18n.ts";
import { type Entry, entryHash, next, signedBytes } from "../src/lock.ts";
import { CACHE_ALPN } from "../src/pair.ts";
import { PersonalLock, personOf } from "../src/personal-lock.ts";
import { hex, utf8 } from "../src/util.ts";
import { Wake } from "../src/wake.ts";
import { FILL_DIAL_MS, FILL_OPENED_AGAIN_MS, allowed, fillOver, serveCache, served } from "../src/views/device-cache.ts";
import { fold, held, read } from "../src/views/lock.ts";
import { down } from "../src/views/views.ts";
import { run as runEffect } from "./run.ts";
import { ME, PHONE, elsewhere, genesis, grant, pipe, rig } from "./lock-rig.ts";
import { SimNet, SimTime } from "./sim-iroh.ts";
import { seeds } from "./sim-seeds.ts";
import { base, entries, started, stationLater, threadView } from "./station-fixture.ts";

const ST = "ws/st";
const row = { id: "7", thread: 7, session: "k1", title: "部署", agents: [], last: null, unread: false, mine: true, lastActiveAt: 5, connect: null, origin: null };
const CRED_EXP = 4102444800;

/// A host on the shared clock (before its core is made on it).
const on = (time: HostTime) => (host: FakeHost) => void ((host as { time: HostTime }).time = time);

/// A key on the person's own lock, of nobody's here.
type Key = { id: string; signBytes(b: Uint8Array): string };
const personKey = (n: number): Key => {
  const seed = new Uint8Array(32).fill(n);
  return { id: `ed25519:${hex(ed25519.getPublicKey(seed))}`, signBytes: (b) => hex(ed25519.sign(b, seed)) };
};
/// `chain` (a person's own lock, `s1`'s) and one entry more, signed with `by`; none: its genesis, naming `by` as `id`.
function signed(chain: Entry[], by: Key, kind: string, body: unknown): Entry[] {
  const last = chain.at(-1);
  const e = next(personOf("s1"), last === undefined ? null : { seq: last.seq, hash: entryHash(last), genesis: entryHash(chain[0]!) }, 1500, kind, body);
  return [...chain, { ...e, sig: { key: by.id, alg: "Ed25519", sig: by.signBytes(signedBytes(entryHash(e))) } }];
}
const begun = (by: Key, id: string, label: string) => signed([], by, "genesis", { sub: "s1", device: { key: by.id, id, label } });

/// `r`'s core given `chain` as its person's own lock, pinned, its own key `mine`; and the workspace's lock bound to it
/// (a `person` entry, signed by `owner`, the device the lock names this one as signing with). Read before it returns.
async function bind(time: SimTime, r: Awaited<ReturnType<typeof rig>>, owner: Key, chain: Entry[], mine: Key) {
  const inner = r.core.inner;
  const kept = { entries: chain };
  r.host.storage.set(`personal-lock-${hex(utf8("s1"))}`, utf8(JSON.stringify(chain)));
  r.host.storage.set("personal-signer-id", utf8(mine.id));
  const personal = new PersonalLock({ host: r.host, runner: inner.runner, device: () => Effect.succeed(ME), label: () => "this", changed: () => {}, cloud: () => Effect.sync(() => ({ entries: kept.entries })) });
  inner.adb.personal = () => personal;
  await time.settle(inner.runner.run(personal.refresh("s1")));
  const ws = r.cloud.chains.get("ws")!;
  const last = ws.at(-1)!;
  const e = next("ws", { seq: last.seq, hash: entryHash(last), genesis: entryHash(ws[0]!) }, 1100, "person", { sub: "s1", person: personal.root("s1") });
  r.cloud.chains.set("ws", [...ws, { ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(signedBytes(entryHash(e))) } }]);
  await time.settle(inner.runner.run(read(inner, "ws")));
  assert.equal(fold(held(inner, "ws")!.entries).persons.get("s1"), personal.root("s1"), "the workspace's lock bound to it");
  /// The person's lock as it goes on: pinned here as this device reads it.
  const goesOn = async (longer: Entry[]) => {
    kept.entries = longer;
    await time.settle(inner.runner.run(personal.refresh("s1")));
  };
  return { personal, goesOn };
}

/// A device holding `held` messages of thread 7 (its last `last`), the phone (`peer`, the owner's or `sub`'s) in its lock.
/// `more`: other devices in its lock. `person`: its person's own lock pinned here, its own key on it `mine`, the
/// workspace's lock bound to it (the lock naming this device as signing with another key, so nothing here signs to
/// keep that lock to the person's: what a test puts in it stays).
async function holder(time: SimTime, o: { sub?: string; me?: string; peer?: string; held?: [number, number][]; last?: number; more?: Record<string, unknown>[]; person?: { chain: Entry[]; mine: Key } } = {}) {
  const g = grant();
  const owner = elsewhere();
  const r = await rig((me) => ({ ws: genesis("ws", o.person ? owner : me, true, [], g.keys, o.me ?? ME, [{ id: o.peer ?? PHONE, sub: o.sub ?? "s1", kind: "app", label: "Pixel" }, ...(o.more ?? [])]) }), on(time));
  const bound = o.person ? await bind(time, r, owner, o.person.chain, o.person.mine) : null;
  // Its own link to the station gone too: what it holds is what it read before.
  stationLater(r.host, (req) => (req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
  r.gate.stream = "fail";
  r.end();
  // Its own asking of other devices left out: it is the one asked here.
  r.core.inner.mesh = () => Effect.succeed({ deviceId: () => o.me ?? ME, lockClaim: () => null, link: () => Effect.fail(new CoreError("unsupported", "the station is reached another way here")) } as never);
  r.core.inner.cloudSync.credential = () => Effect.fail(new CoreError("unsupported", "it asks no one here")) as never;
  r.core.inner.data.set({ topic: "loginSessions", account: "s1" }, { sessions: [{ id: "live" }] });
  r.core.inner.data.set({ topic: "threads", station: ST }, [threadView(7, o.last ?? 120)]);
  r.core.inner.data.set({ topic: "chatRows", station: ST }, [row]);
  for (const [from, to] of o.held ?? [[1, 120]]) r.core.inner.data.putItems("entry", ST, "7", entries(from, to).map((e) => [e.n, e] as [number, unknown]));
  await time.pass(100);
  return { ...r, g, bound };
}

/// What `client` is answered to `m`, over a pipe a holder serves.
const asks = (time: SimTime, client: Awaited<ReturnType<typeof pipe>>[1]) => (m: unknown) => time.settle(Effect.runPromise(Effect.andThen(client.send(m), client.next())) as Promise<Record<string, any>>);

test("a device answers only its own person's device, named by the lock, whose session stands", async () => {
  const time = new SimTime();
  const r = await holder(time);
  const inner = r.core.inner;
  const token = (o: { device?: string; sub?: string; sid?: string; ws?: string } = {}) => r.g.credential(o.ws ?? "ws", o.device ?? PHONE, o.sub ?? "s1", CRED_EXP, "member", "sid" in o ? o.sid : "live");
  assert.equal(allowed(inner, "ws", token(), PHONE), true);
  assert.equal(allowed(inner, "ws", token({ sid: "gone" }), PHONE), false, "its login session gone");
  assert.equal(allowed(inner, "ws", r.g.credential("ws", PHONE, "s1"), PHONE), false, "no session said");
  assert.equal(allowed(inner, "ws", token({ device: "ee".repeat(32) }), PHONE), false, "a credential for another device");
  assert.equal(allowed(inner, "ws", token({ device: "ee".repeat(32) }), "ee".repeat(32)), false, "a device the lock does not name");
  assert.equal(allowed(inner, "ws", token({ sub: "s2" }), PHONE), false, "another person's credential");
  assert.equal(allowed(inner, "w9", token({ ws: "w9" }), PHONE), false, "a workspace it is not in");
  assert.equal(allowed(inner, "ws", "not a credential", PHONE), false);
  r.core.close();
});

test("another member's device, though the lock names it, is told nothing", async () => {
  const time = new SimTime();
  const r = await holder(time, { sub: "s2" });
  assert.equal(allowed(r.core.inner, "ws", r.g.credential("ws", PHONE, "s2", CRED_EXP, "member", "live"), PHONE), false);
  r.core.close();
});

// ── bound to the person's own lock ──

const GONE = "e1".repeat(32);
const NEW = "e2".repeat(32);
const WEB = "e3".repeat(32);
const [K_ME, K_PHONE, K_GONE, K_NEW] = [personKey(0x31), personKey(0x32), personKey(0x33), personKey(0x34)];
/// s1's own lock begun by this device: the phone on it, GONE put on and taken off again, NEW put on since.
const ownLock = () => {
  let c = begun(K_ME, ME, "this");
  c = signed(c, K_ME, "device", { key: K_PHONE.id, id: PHONE, label: "Pixel" });
  c = signed(c, K_ME, "device", { key: K_GONE.id, id: GONE, label: "Old Mac" });
  c = signed(c, K_ME, "device", { key: K_NEW.id, id: NEW, label: "New Mac" });
  return c;
};
/// The workspace's lock beside it: the phone, GONE (still), and a web page of s1's; NEW not (yet).
const named = [{ id: GONE, sub: "s1", kind: "app", label: "Old Mac" }, { id: WEB, sub: "s1", kind: "web", label: "Chrome", exp: CRED_EXP }];

test("bound to their own lock, an app device is its person's as that lock says, a web page as the workspace's lock says", async () => {
  const time = new SimTime();
  const r = await holder(time, { more: named, person: { chain: signed(ownLock(), K_ME, "device.remove", { key: K_GONE.id }), mine: K_ME } });
  const inner = r.core.inner;
  const token = (device: string) => r.g.credential("ws", device, "s1", CRED_EXP, "member", "live");
  const ids = fold(held(inner, "ws")!.entries).devices;
  assert.ok(ids.has(GONE) && !ids.has(NEW), "the workspace's lock names GONE, not NEW");
  assert.equal(allowed(inner, "ws", token(PHONE), PHONE), true, "on both locks: answered");
  assert.equal(allowed(inner, "ws", token(GONE), GONE), false, "taken off the person's lock, though the workspace's lock still names it: refused");
  assert.equal(allowed(inner, "ws", token(NEW), NEW), true, "put on the person's lock, before the workspace's lock names it: answered");
  assert.equal(allowed(inner, "ws", token(WEB), WEB), true, "a web page, by its entry in the workspace's lock");
  assert.equal(allowed(inner, "ws", r.g.credential("ws", NEW, "s1", CRED_EXP, "member", "gone"), NEW), false, "its credential still checked: a session gone");
  r.core.close();
});

test("bound, a device taken off the person's lock as this device reads it is refused from then on", async () => {
  const time = new SimTime();
  const r = await holder(time, { more: named, person: { chain: ownLock(), mine: K_ME } });
  const inner = r.core.inner;
  const token = r.g.credential("ws", GONE, "s1", CRED_EXP, "member", "live");
  assert.equal(allowed(inner, "ws", token, GONE), true, "on it: answered");
  await r.bound!.goesOn(signed(ownLock(), K_ME, "device.remove", { key: K_GONE.id }));
  assert.ok(fold(held(inner, "ws")!.entries).devices.has(GONE), "the workspace's lock names it still");
  assert.equal(allowed(inner, "ws", token, GONE), false, "taken off: refused");
  r.core.close();
});

test("bound to a lock this device is not on, it answers no one", async () => {
  const time = new SimTime();
  // Begun by NEW, the phone on it; this device's own key is not.
  const chain = signed(begun(K_NEW, NEW, "New Mac"), K_NEW, "device", { key: K_PHONE.id, id: PHONE, label: "Pixel" });
  const r = await holder(time, { more: named, person: { chain, mine: K_ME } });
  const inner = r.core.inner;
  assert.equal(r.bound!.personal.standing("s1"), "outside");
  assert.equal(allowed(inner, "ws", r.g.credential("ws", PHONE, "s1", CRED_EXP, "member", "live"), PHONE), false, "the phone, on both locks: refused");
  assert.equal(allowed(inner, "ws", r.g.credential("ws", WEB, "s1", CRED_EXP, "member", "live"), WEB), false, "a web page too");
  r.core.close();
});

test("what it asks is answered only of the workspace it proved itself in", async () => {
  const time = new SimTime();
  const r = await holder(time);
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, PHONE, server)));
  const say = asks(time, client);
  assert.deepEqual(await say({ t: "hello", ws: "ws", credential: r.g.credential("ws", PHONE, "s1", CRED_EXP, "member", "live") }), { t: "ok" });
  const list = await say({ t: "list", station: ST });
  assert.deepEqual(list.rows.map((x: any) => x.id), ["7"]);
  const page = await say({ t: "entries", station: ST, thread: 7, after: 100, limit: 500 });
  assert.equal(page.entries.length, 20);
  assert.equal(page.last, 120);
  assert.deepEqual(await say({ t: "list", station: "w2/st" }), { t: "no" }, "another workspace's station");
  r.core.close();
});

test("a stranger's first word ends it", async () => {
  const time = new SimTime();
  const r = await holder(time);
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, "ee".repeat(32), server)));
  assert.deepEqual(await asks(time, client)({ t: "hello", ws: "ws", credential: r.g.credential("ws", "ee".repeat(32), "s1", CRED_EXP, "member", "live") }), { t: "no" });
  r.core.close();
});

/// The device away: a core holding 11–60 of thread 7, as its station gave them (`held`); or none of it.
async function away(time: HostTime, held: [number, number] | null) {
  const answers = held === null ? { ...base(), "GET /threads": [], "GET /chats": [] } : { ...base(), "GET /threads": [threadView(7, 60)], "GET /chats": [{ ...row, lastActiveAt: 1 }], "GET /threads/7/entries?limit=50": { last: 60, entries: entries(11, 60) } };
  const s = await started(answers, 0, undefined, (x) => on(time)(x.host));
  await time.pass(500);
  if (held !== null) {
    s.core.inner.data.set({ topic: "threads", station: ST }, [threadView(7, 60)]);
    s.core.inner.data.set({ topic: "chatRows", station: ST }, [{ ...row, lastActiveAt: 1 }]);
    s.core.inner.data.putItems("entry", ST, "7", entries(held[0], held[1]).map((e) => [e.n, e] as [number, unknown]));
  }
  return s;
}

/// `fillOver` from `r` to `s` over a pipe, hello answered.
async function filledOver(time: SimTime, r: Awaited<ReturnType<typeof holder>>, s: Awaited<ReturnType<typeof away>>) {
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, PHONE, server)));
  const hello = Effect.andThen(client.send({ t: "hello", ws: "ws", credential: r.g.credential("ws", PHONE, "s1", CRED_EXP, "member", "live") }), client.next());
  return time.settle(s.core.inner.runner.run(Effect.andThen(hello, fillOver(s.core.inner, ST, client, () => true))));
}

test("the device away takes what it lacks, before and after what it holds, and says so; the chat shows it", async () => {
  const time = new SimTime();
  const r = await holder(time);
  const s = await away(time, [11, 60]);
  assert.deepEqual(await filledOver(time, r, s), { brought: true, upTo: 120 });
  assert.deepEqual(s.core.inner.data.logSpan("entry", ST, "7"), { min: 1, max: 120, count: 120 });
  assert.equal(s.core.inner.data.logCount("entry", ST, "7", 1, 120), 120);
  assert.equal(s.core.inner.data.threadLast(ST, 7), 120);
  assert.equal((s.core.inner.data.shared({ topic: "chatRows", station: ST }) as any[])[0].lastActiveAt, 5);
  r.core.close();
  s.core.close();
});

test("a hole in what the device asked holds ends no page: both stretches come", async () => {
  const time = new SimTime();
  const r = await holder(time, { held: [[1, 50], [100, 120]] });
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, PHONE, server)));
  const say = asks(time, client);
  await say({ t: "hello", ws: "ws", credential: r.g.credential("ws", PHONE, "s1", CRED_EXP, "member", "live") });
  const page = await say({ t: "entries", station: ST, thread: 7, after: 50, limit: 50 });
  assert.deepEqual(page.entries.map((e: any) => e.n), Array.from({ length: 21 }, (_, i) => 100 + i), "the next held above 50");
  assert.deepEqual((await say({ t: "entries", station: ST, thread: 7, after: 40, limit: 15 })).entries.map((e: any) => e.n), [41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 100, 101, 102, 103, 104]);
  assert.deepEqual((await say({ t: "entries", station: ST, thread: 7, after: 120, limit: 50 })).entries, [], "nothing above it");
  // The device that asks, holding none of it, gets both.
  const s = await away(time, null);
  assert.deepEqual(await filledOver(time, r, s), { brought: true, upTo: 120 });
  assert.equal(s.core.inner.data.logSpan("entry", ST, "7")?.count, 71);
  assert.equal(s.core.inner.data.logCount("entry", ST, "7", 1, 50), 50);
  assert.equal(s.core.inner.data.logCount("entry", ST, "7", 100, 120), 21);
  r.core.close();
  s.core.close();
});

// ── over the simulated network ──

/// A phone and the person's other devices on a simulated network: `holders` of them answer, holding 1–120 of thread 7;
/// `silent` are in the lock but never reached. Every dial the phone makes is in `dials`. `bound`: the phone's lock bound
/// to s1's own, which the phone is on: the holders on it but not in the workspace's lock, GONE in that lock but taken off
/// the person's.
async function meeting(seed: number, o: { holders: number; silent: number; bound?: boolean }) {
  const time = new SimTime();
  const net = new SimNet(time.clock, seed);
  const relay = net.relay("https://relay.test/", { device: { ms: 20 }, station: { ms: 20 } });
  const g = grant();
  const iroh = net.iroh();
  const phoneEnd = await time.settle(runEffect(iroh.bind({ secretKey: net.key(), relayUrls: [relay], lookup: false, relayOnly: false })));
  const dials: string[] = [];
  const counted: IrohEndpoint = { ...phoneEnd, connect: (addr, alpn, more) => (dials.push(addr.id), phoneEnd.connect(addr, alpn, more)) };
  // The devices that answer: endpoints taking CACHE_ALPN (as an app's main endpoint does), each served by its own core.
  const holding: { r: Awaited<ReturnType<typeof holder>>; end: IrohEndpoint }[] = [];
  for (let i = 0; i < o.holders; i++) {
    const sim = net.bindStation({ secretKey: net.key(), alpns: [CACHE_ALPN], relayUrls: [relay] });
    const end = await time.settle(runEffect(wrapIroh(async () => sim as never, (b) => b).bind({ secretKey: new Uint8Array(32), relayUrls: [relay], lookup: false, relayOnly: false })));
    const r = await holder(time, { me: end.id(), peer: phoneEnd.id() });
    void (async () => {
      for (;;) {
        const taken = await runEffect(end.accept!());
        if (taken === null) return;
        served(r.core.inner, taken.connection);
      }
    })();
    holding.push({ r, end });
  }
  const silent = Array.from({ length: o.silent }, (_, i) => `${(0xe0 + i).toString(16)}`.repeat(32));
  // Those that never answer first: one after another, they would hold the one that does back.
  const label = (i: number) => (i === 0 ? "Mac" : `Mac ${i + 1}`);
  const others = [...silent.map((id, i) => ({ id, sub: "s1", kind: "app", label: `off ${i + 1}` })), ...(o.bound ? [{ id: GONE, sub: "s1", kind: "app", label: "Old Mac" }] : holding.map((h, i) => ({ id: h.end.id(), sub: "s1", kind: "app", label: label(i) })))];
  const owner = elsewhere();
  const phone = await rig((me) => ({ ws: genesis("ws", o.bound ? owner : me, true, [], g.keys, phoneEnd.id(), others) }), on(time));
  if (o.bound) {
    let chain = signed(begun(K_ME, phoneEnd.id(), "phone"), K_ME, "device", { key: K_GONE.id, id: GONE, label: "Old Mac" });
    for (const [i, h] of holding.entries()) chain = signed(chain, K_ME, "device", { key: personKey(0x40 + i).id, id: h.end.id(), label: label(i) });
    await bind(time, phone, owner, signed(chain, K_ME, "device.remove", { key: K_GONE.id }), K_ME);
  }
  await phone.watch({ topic: "lock", workspace: "ws" });
  const inner = phone.core.inner;
  inner.mesh = () => Effect.succeed({ deviceId: () => phoneEnd.id(), endpoint: () => counted, lockClaim: () => null, link: () => Effect.fail(new CoreError("unsupported", "the station is reached another way here")) } as never);
  inner.cloudSync.credential = () => Effect.succeed({ credential: g.credential("ws", phoneEnd.id(), "s1", CRED_EXP, "member", "live") }) as never;
  const span = () => inner.data.logSpan("entry", ST, "7");
  const isDown = () => down(inner.stations.link(ST)?.state);
  /// The station goes: its link finds it down, as a phone's does.
  const goes = async () => {
    stationLater(phone.host, (req) => (req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
    phone.gate.stream = "fail";
    phone.end();
    await time.until(isDown);
  };
  const close = async () => {
    phone.core.close();
    for (const h of holding) {
      h.r.core.close();
      await time.settle(runEffect(h.end.close()));
    }
    await time.settle(runEffect(phoneEnd.close()));
  };
  return { time, net, phone, inner, holding, dials, span, isDown, goes, close };
}

/// Each seed's run of a test on the simulated network; a failure says the seed.
function sim(name: string, body: (seed: number) => Promise<void>) {
  test(name, async () => {
    for (const seed of seeds()) {
      try {
        await body(seed);
      } catch (e) {
        const error = e instanceof Error ? e : new Error(String(e));
        error.message = `${name} (SIM_SEED=${seed}):\n${error.message}`;
        throw error;
      }
    }
  });
}

sim("a station down, the phone asks its person's other device, and its chat shows what came; asked again only as the UI comes back or a chat opens", async (seed) => {
  const m = await meeting(seed, { holders: 1, silent: 0 });
  const { time, inner, phone, dials, span } = m;
  const holding = m.holding[0]!.r;
  const chat = await phone.watch({ topic: "chat", station: ST, thread: 7 });
  await time.pass(100);
  assert.notEqual(span()?.max, 120, "not there yet");
  // Up, nothing is asked: the station's own is the way.
  await time.pass(10 * 60_000);
  assert.deepEqual(dials, [], "not while the station is up");
  await m.goes();
  // As it is found down, once.
  await time.until(() => inner.data.record("deviceFill", ST) !== undefined);
  assert.equal(dials.length, 1);
  assert.equal(span()?.count, 120);
  const shown = await chat();
  assert.equal(shown.offline, true);
  // What came, from which device, as far as when: kept with what came.
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "filled", from: "Mac", upTo: 120 });
  assert.ok(String(shown.offlineNote).includes(t("core-logic.looks.offline.fill.upTo", { device: "Mac", time: format.relativeTime(120, phone.host.nowMs(), phone.host.utcOffsetMin(phone.host.nowMs())) })), String(shown.offlineNote));
  // More there now: not asked on a timer, however long (the link's own tries at the station included).
  holding.core.inner.data.putThread(ST, threadView(7, 130));
  holding.core.inner.data.putItems("entry", ST, "7", entries(121, 130).map((e) => [e.n, e] as [number, unknown]));
  await time.pass(30 * 60_000);
  assert.equal(dials.length, 1, "no timer asks");
  assert.equal(span()?.count, 120);
  assert.ok(m.isDown(), "still down");
  // Asked as the UI comes back.
  inner.wakes.wake(new Wake(phone.host.nowMs(), 1000, false, false));
  await time.until(() => span()?.count === 130);
  await time.pass(1000);
  assert.equal(dials.length, 2);
  // More again: a chat opened right after it was asked asks nothing; one opened FILL_OPENED_AGAIN_MS after it does.
  holding.core.inner.data.putThread(ST, threadView(7, 140));
  holding.core.inner.data.putItems("entry", ST, "7", entries(131, 140).map((e) => [e.n, e] as [number, unknown]));
  await phone.watch({ topic: "chat", station: ST, thread: 8 });
  assert.equal(dials.length, 2, "opened too soon after");
  await time.pass(FILL_OPENED_AGAIN_MS);
  await phone.watch({ topic: "chat", station: ST, session: "k1" });
  await time.until(() => span()?.count === 140);
  assert.equal(dials.length, 3);
  // Nothing newer: what it brought stays said.
  await time.pass(FILL_OPENED_AGAIN_MS + 1000);
  await phone.watch({ topic: "chat", station: ST, thread: 9 });
  await time.until(() => dials.length === 4);
  await time.pass(5000);
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "filled", from: "Mac", upTo: 140 });
  // Started again, still down: it still says so.
  await time.pass(SOON_MS + 50);
  await Effect.runPromise(inner.data.written);
  const kept = inner.data.record("deviceFill", ST);
  phone.core.close();
  phone.host.takeEmitted();
  const again = await Core.create(phone.host, { clock: phone.host.time.clock, sample: 0, wire: () => new HostWire(phone.host) });
  await time.pass(500);
  assert.deepEqual(again.inner.data.record("deviceFill", ST), kept);
  again.close();
  await m.close();
});

sim("the other devices are dialled together: two never reached hold back none that answers", async (seed) => {
  const m = await meeting(seed, { holders: 1, silent: 2 });
  const { time, inner, phone, span } = m;
  const chat = await phone.watch({ topic: "chat", station: ST, thread: 7 });
  await m.goes();
  const began = time.now();
  assert.equal(m.dials.length, 3, "all three at once");
  await time.until(() => inner.data.record("deviceFill", ST) !== undefined);
  assert.ok(time.now() - began < FILL_DIAL_MS, `filled after ${time.now() - began} ms`);
  assert.equal(span()?.count, 120);
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "filled", from: "Mac", upTo: 120 });
  // The two not reached still dialled meanwhile; what came is said all the while, and kept as they are given up on.
  const upTo = t("core-logic.looks.offline.fill.upTo", { device: "Mac", time: format.relativeTime(120, phone.host.nowMs(), phone.host.utcOffsetMin(phone.host.nowMs())) });
  assert.ok(String((await chat()).offlineNote).includes(upTo), "said before the others are given up on");
  await time.pass(FILL_DIAL_MS);
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "filled", from: "Mac", upTo: 120 });
  assert.equal(m.net.open().length, 0, "every connection closed");
  assert.equal(m.dials.length, 3, "none dialled again");
  await m.close();
});

sim("none of the other devices reached: unreached after FILL_DIAL_MS, not after each one's", async (seed) => {
  const m = await meeting(seed, { holders: 0, silent: 3 });
  const { time, inner, phone } = m;
  const chat = await phone.watch({ topic: "chat", station: ST, thread: 7 });
  await m.goes();
  const began = time.now();
  assert.equal(m.dials.length, 3);
  assert.ok(String((await chat()).offlineNote).includes(t("core-logic.looks.offline.fill.dialing")), "reaching them, none answered yet");
  await time.until(() => inner.data.record("deviceFill", ST) !== undefined);
  const took = time.now() - began;
  assert.ok(took >= FILL_DIAL_MS && took < 2 * FILL_DIAL_MS, `unreached after ${took} ms`);
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "unreached" });
  assert.ok(String((await chat()).offlineNote).includes(t("core-logic.looks.offline.fill.unreached")));
  await m.close();
});

sim("bound to the person's own lock, the phone dials the devices on it: one the workspace's lock does not name yet, not one taken off", async (seed) => {
  const m = await meeting(seed, { holders: 1, silent: 0, bound: true });
  const { time, inner, span } = m;
  const holder = m.holding[0]!.end.id();
  const ids = fold(held(inner, "ws")!.entries).devices;
  assert.ok(ids.has(GONE) && !ids.has(holder), "the workspace's lock names GONE, not the holder");
  await m.goes();
  await time.until(() => inner.data.record("deviceFill", ST) !== undefined);
  assert.deepEqual(m.dials, [holder], "the holder alone");
  assert.equal(span()?.count, 120);
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "filled", from: "Mac", upTo: 120 }, "named as the person's lock names it");
  assert.ok(fold(held(inner, "ws")!.entries).devices.has(GONE), "GONE named by the workspace's lock all the while");
  await m.close();
});

sim("the cloud says the station is offline while this device's link is up: nobody is dialled", async (seed) => {
  const m = await meeting(seed, { holders: 1, silent: 0 });
  const { time, inner, phone } = m;
  await time.until(() => (inner.stations.link(ST)?.state as { state?: string } | undefined)?.state === "online");
  // still.fail cloud says it went, on the account's events socket (sync/cloud.ts); then one of its chats is opened.
  const events = phone.host.sockets.find((x) => x.url.includes("/v1/events") && !x.closed);
  assert.ok(events, "the events socket open");
  events.send(JSON.stringify({ type: "station", workspace: "ws", id: "st", online: false }));
  await time.pass(1000);
  const listed = inner.data.shared({ topic: "workspace", workspace: "ws" }) as { stations?: { id: string; online: boolean }[] } | undefined;
  assert.equal(listed?.stations?.find((s) => s.id === "st")?.online, false, "the cloud says it is offline");
  await phone.watch({ topic: "chat", station: ST, thread: 7 });
  await time.pass(1000);
  assert.equal((inner.stations.link(ST)?.state as { state?: string } | undefined)?.state, "online", "its link still up");
  assert.deepEqual(m.dials, []);
  assert.equal(inner.data.record("deviceFill", ST), undefined);
  await m.close();
});
