// What a person's other device holds of a station that is down (views/device-cache.ts): it answers only its own person's
// device the lock names, with a credential for that endpoint and a session that stands, only of the workspace proved; the
// device that asks takes what it lacks, the station's own coming back goes on from there.
import assert from "node:assert/strict";
import { test } from "node:test";
import { randomBytes } from "node:crypto";
import { Effect } from "effect";
import { Core } from "../src/core.ts";
import { SOON_MS } from "../src/data.ts";
import { HostError } from "../src/error.ts";
import { HostWire } from "../src/station/wire.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import * as format from "../src/format.ts";
import { t } from "../src/i18n.ts";
import { CACHE_ALPN } from "../src/pair.ts";
import { Wake } from "../src/wake.ts";
import { FILL_OPENED_AGAIN_MS, allowed, fillOver, serveCache, served } from "../src/views/device-cache.ts";
import { run as runEffect } from "./run.ts";
import { ME, PHONE, genesis, grant, pipe, rig } from "./lock-rig.ts";
import { base, entries, started, stationLater, threadView } from "./station-fixture.ts";

const ST = "ws/st";
const row = { id: "7", thread: 7, session: "k1", title: "部署", agents: [], last: null, unread: false, mine: true, lastActiveAt: 5, connect: null, origin: null };

/// A device holding 120 messages of a thread, the phone (the owner's, or `sub`'s) in its lock.
async function holder(sub = "s1") {
  const g = grant();
  const r = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, ME, [{ id: PHONE, sub, kind: "app", label: "Pixel" }]) }));
  r.core.inner.data.set({ topic: "loginSessions", account: "s1" }, { sessions: [{ id: "live" }] });
  r.core.inner.data.set({ topic: "threads", station: ST }, [threadView(7, 120)]);
  r.core.inner.data.set({ topic: "chatRows", station: ST }, [row]);
  r.core.inner.data.putItems("entry", ST, "7", entries(1, 120).map((e) => [e.n, e] as [number, unknown]));
  await r.host.time.pass(100);
  return { ...r, g };
}

test("a device answers only its own person's device, named by the lock, whose session stands", async () => {
  const r = await holder();
  const inner = r.core.inner;
  const token = (o: { device?: string; sub?: string; sid?: string; ws?: string } = {}) => r.g.credential(o.ws ?? "ws", o.device ?? PHONE, o.sub ?? "s1", 4102444800, "sid" in o ? o.sid : "live");
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
  const r = await holder("s2");
  assert.equal(allowed(r.core.inner, "ws", r.g.credential("ws", PHONE, "s2", 4102444800, "live"), PHONE), false);
  r.core.close();
});

test("what it asks is answered only of the workspace it proved itself in", async () => {
  const r = await holder();
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, PHONE, server)));
  const say = async (m: unknown) => {
    const out: unknown[] = [];
    r.core.inner.runner.fork(Effect.ignore(Effect.map(Effect.andThen(client.send(m), client.next()), (x) => out.push(x))));
    for (let i = 0; i < 200 && out.length === 0; i++) await r.host.time.pass(5);
    return out[0] as Record<string, any>;
  };
  assert.deepEqual(await say({ t: "hello", ws: "ws", credential: r.g.credential("ws", PHONE, "s1", 4102444800, "live") }), { t: "ok" });
  const list = await say({ t: "list", station: ST });
  assert.deepEqual(list.rows.map((x: any) => x.id), ["7"]);
  const page = await say({ t: "entries", station: ST, thread: 7, after: 100, limit: 500 });
  assert.equal(page.entries.length, 20);
  assert.equal(page.last, 120);
  assert.deepEqual(await say({ t: "list", station: "w2/st" }), { t: "no" }, "another workspace's station");
  r.core.close();
});

test("a stranger's first word ends it", async () => {
  const r = await holder();
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, "ee".repeat(32), server)));
  const out: unknown[] = [];
  r.core.inner.runner.fork(Effect.ignore(Effect.map(Effect.andThen(client.send({ t: "hello", ws: "ws", credential: r.g.credential("ws", "ee".repeat(32), "s1", 4102444800, "live") }), client.next()), (x) => out.push(x))));
  for (let i = 0; i < 200 && out.length === 0; i++) await r.host.time.pass(5);
  assert.deepEqual(out[0], { t: "no" });
  r.core.close();
});

test("the device away takes what it lacks, before and after what it holds, and says so; the chat shows it", async () => {
  const r = await holder();
  const s = await started({ ...base(), "GET /threads": [threadView(7, 60)], "GET /chats": [{ ...row, lastActiveAt: 1 }], "GET /threads/7/entries?limit=50": { last: 60, entries: entries(11, 60) } });
  await s.host.time.pass(500);
  s.core.inner.data.set({ topic: "threads", station: ST }, [threadView(7, 60)]);
  s.core.inner.data.set({ topic: "chatRows", station: ST }, [{ ...row, lastActiveAt: 1 }]);
  s.core.inner.data.putItems("entry", ST, "7", entries(11, 60).map((e) => [e.n, e] as [number, unknown]));
  const [server, client] = await pipe();
  r.core.inner.runner.fork(Effect.ignore(serveCache(r.core.inner, PHONE, server)));
  const done: { brought: boolean; upTo: number | null }[] = [];
  const hello = Effect.andThen(client.send({ t: "hello", ws: "ws", credential: r.g.credential("ws", PHONE, "s1", 4102444800, "live") }), client.next());
  s.core.inner.runner.fork(Effect.ignore(Effect.map(Effect.andThen(hello, fillOver(s.core.inner, ST, client, () => true)), (c) => done.push(c))));
  for (let i = 0; i < 500 && done.length === 0; i++) {
    await r.host.time.pass(5);
    await s.host.time.pass(5);
  }
  assert.deepEqual(done, [{ brought: true, upTo: 120 }]);
  assert.deepEqual(s.core.inner.data.logSpan("entry", ST, "7"), { min: 1, max: 120, count: 120 });
  assert.equal(s.core.inner.data.logCount("entry", ST, "7", 1, 120), 120);
  assert.equal(s.core.inner.data.threadLast(ST, 7), 120);
  assert.equal((s.core.inner.data.shared({ topic: "chatRows", station: ST }) as any[])[0].lastActiveAt, 5);
  r.core.close();
  s.core.close();
});

test("over iroh: a station down, the phone asks its person's other device, and its chat shows what came", { skip: loadAddon() === null ? "the mesh addon is not built here" : false }, async () => {
  const addon = loadAddon() as any;
  const seen: any[] = [];
  const iroh = nodeIroh({ bind: async (o: any) => { const e = await addon.bind(o); seen.push(e); return e; } })!;
  const holderEnd = await runEffect(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false, alpns: [CACHE_ALPN] }));
  const phoneEnd = await runEffect(iroh.bind({ secretKey: randomBytes(32), relayUrls: [], lookup: false, relayOnly: false }));
  const socket = (seen[0].sockets() as string[]).find((x) => !x.startsWith("["))!;
  phoneEnd.addAddr({ id: holderEnd.id(), ips: [`127.0.0.1:${socket.slice(socket.lastIndexOf(":") + 1)}`] });
  const g = grant();
  const holding = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, holderEnd.id(), [{ id: phoneEnd.id(), sub: "s1", kind: "app", label: "Pixel" }]) }));
  holding.core.inner.data.set({ topic: "loginSessions", account: "s1" }, { sessions: [{ id: "live" }] });
  holding.core.inner.data.set({ topic: "threads", station: ST }, [threadView(7, 120)]);
  holding.core.inner.data.set({ topic: "chatRows", station: ST }, [row]);
  holding.core.inner.data.putItems("entry", ST, "7", entries(1, 120).map((e) => [e.n, e] as [number, unknown]));
  await holding.host.time.pass(100);
  void (async () => {
    for (;;) {
      const taken = await runEffect(holderEnd.accept!());
      if (taken === null) return;
      served(holding.core.inner, taken.connection);
    }
  })();

  const phone = await rig((me) => ({ ws: genesis("ws", me, true, [], g.keys, phoneEnd.id(), [{ id: holderEnd.id(), sub: "s1", kind: "app", label: "Mac" }]) }));
  await phone.watch({ topic: "lock", workspace: "ws" });
  const inner = phone.core.inner;
  inner.mesh = () => Effect.succeed({ deviceId: () => phoneEnd.id(), endpoint: () => phoneEnd, lockClaim: () => null } as never);
  inner.cloudSync.credential = () => Effect.succeed({ credential: g.credential("ws", phoneEnd.id(), "s1", 4102444800, "live") }) as never;
  const chat = await phone.watch({ topic: "chat", station: ST, thread: 7 });
  await phone.host.time.pass(100);
  assert.notEqual(inner.data.logSpan("entry", ST, "7")?.max, 120, "not there yet");
  // Up, nothing is asked: the station's own is the way.
  await phone.host.time.pass(10 * 60_000, 1000);
  assert.notEqual(inner.data.logSpan("entry", ST, "7")?.max, 120, "not while the station is up");
  // It goes: the link finds it down, as a phone's does.
  stationLater(phone.host, (req) => (req.url.includes("/admin/api") ? Promise.reject(new HostError("连不上")) : undefined));
  phone.gate.stream = "fail";
  phone.end();
  // As it is found down, once; on the test's clock, slowly enough for what goes over a real connection.
  const until = async (done: () => boolean) => {
    for (let i = 0; i < 3000 && !done(); i++) {
      await phone.host.time.pass(200);
      await holding.host.time.pass(5);
      await new Promise((d) => setTimeout(d, 2));
    }
  };
  await until(() => inner.data.logSpan("entry", ST, "7")?.count === 120);
  assert.equal((inner.stations.link(ST)?.state as { state: string }).state, "offline");
  assert.equal(inner.data.logSpan("entry", ST, "7")?.count, 120);
  for (let i = 0; i < 50; i++) await phone.host.time.pass(50);
  const shown = await chat();
  assert.equal(shown.offline, true);
  // What came, from which device, as far as when: kept with what came.
  assert.deepEqual(inner.data.record("deviceFill", ST), { state: "filled", from: "Mac", upTo: 120 });
  assert.ok(String(shown.offlineNote).includes("Mac"), String(shown.offlineNote));
  assert.ok(String(shown.offlineNote).includes(t("core-logic.looks.offline.fill.upTo", { device: "Mac", time: format.relativeTime(120, phone.host.nowMs(), phone.host.utcOffsetMin(phone.host.nowMs())) })), String(shown.offlineNote));
  // More there now: not asked on a timer, however long; asked as the UI comes back.
  holding.core.inner.data.putThread(ST, threadView(7, 130));
  holding.core.inner.data.putItems("entry", ST, "7", entries(121, 130).map((e) => [e.n, e] as [number, unknown]));
  await holding.host.time.pass(100);
  await phone.host.time.pass(10 * 60_000, 10_000);
  await new Promise((d) => setTimeout(d, 50));
  assert.equal(inner.data.logSpan("entry", ST, "7")?.count, 120, "no timer asks");
  inner.wakes.wake(new Wake(phone.host.nowMs(), 1000, false, false));
  await until(() => inner.data.logSpan("entry", ST, "7")?.count === 130);
  assert.equal(inner.data.logSpan("entry", ST, "7")?.count, 130);
  // More again: a chat opened asks too, at once, but not again right after it was asked.
  holding.core.inner.data.putThread(ST, threadView(7, 140));
  holding.core.inner.data.putItems("entry", ST, "7", entries(131, 140).map((e) => [e.n, e] as [number, unknown]));
  await holding.host.time.pass(100);
  await new Promise((d) => setTimeout(d, 100));
  await phone.host.time.pass(FILL_OPENED_AGAIN_MS + 1000, 1000);
  await new Promise((d) => setTimeout(d, 50));
  await phone.watch({ topic: "chat", station: ST, session: "k1" });
  await until(() => inner.data.logSpan("entry", ST, "7")?.count === 140);
  assert.equal(inner.data.logSpan("entry", ST, "7")?.count, 140);
  // Nothing newer: what it brought stays said.
  assert.equal((inner.data.record("deviceFill", ST) as { state: string }).state, "filled");
  // Started again, still down: it still says so.
  await phone.host.time.pass(SOON_MS + 50, 100);
  await Effect.runPromise(inner.data.written);
  const kept = inner.data.record("deviceFill", ST);
  phone.core.close();
  phone.host.takeEmitted();
  const again = await Core.create(phone.host, { clock: phone.host.time.clock, sample: 0, wire: () => new HostWire(phone.host) });
  await phone.host.time.pass(500);
  assert.deepEqual(again.inner.data.record("deviceFill", ST), kept);
  again.close();
  holding.core.close();
  await runEffect(phoneEnd.close());
  await runEffect(holderEnd.close());
});
