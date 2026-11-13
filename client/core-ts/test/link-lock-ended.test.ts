// A device taken out of a workspace's lock by another's entry, its station ending its connection for that
// (station/src/mesh/serve.ts `gone`: closed with `lock_unconfirmed`): the station is dialled again at once, and its
// refusal, with the entries it tells, shows this device's lock page waiting to be approved, not RECONNECT_MS later
// (station/link.ts LOCK_ENDED; 2026-11-11, with real stations: 0.1 to 2.3 s of 正在重连 first). Once only: a station that
// keeps ending the link so is dialled at the old pace from the second try. The station is the mesh's as this core
// meets it (MeshWire): one connection for every request, each request on none dialling one; refused there, the core
// told as the mesh tells it (`hooks.lockRefused`, `hooks.lockWaiting`). On the test clock.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Deferred, Effect, type Scope } from "effect";
import { hooks } from "../src/core/execute.ts";
import type { Inner } from "../src/core.ts";
import { type CoreError, HostError } from "../src/error.ts";
import { type Entry, type Head, entryHash, next, signedBytes } from "../src/lock.ts";
import { LockUnconfirmed } from "../src/station/mesh-wire.ts";
import type { StationAddr } from "../src/station/addr.ts";
import { RECONNECT_MS } from "../src/station/link.ts";
import { HostWire, type RequestHead, type StationWire, type WireReply } from "../src/station/wire.ts";
import type { FakeHost } from "../src/testing.ts";
import { utf8 } from "../src/util.ts";
import { fold, held, read } from "../src/views/lock.ts";
import { ME, elsewhere, genesis, grant, rig } from "./lock-rig.ts";

const A = "aa".repeat(32);
/// The owner's other device, which takes this one out.
const OTHER = "ee".repeat(32);

/// A connection of this device's to the station: why the station ended it (its close's reason), once it did.
type Conn = { reason: string | null; gone: Deferred.Deferred<void> };

/// The station A as the mesh brings it: its lock's chain, the connection open now, when each was dialled.
function station(host: FakeHost, first: Entry) {
  const chain: Entry[] = [first];
  const at = { inner: null as Inner | null, conn: null as Conn | null, streams: 0 };
  const dials: number[] = [];
  const ends: number[] = [];
  const head = (): Head => ({ seq: chain.length - 1, hash: entryHash(chain.at(-1)!), genesis: entryHash(chain[0]!) });
  const names = () => fold(chain).devices.has(ME);
  /// Ends the connection open, saying why (as serve.ts closes it).
  const end = (reason: string) => {
    const c = at.conn;
    if (c === null) return;
    at.conn = null;
    c.reason = reason;
    ends.push(host.nowMs());
    Deferred.doneUnsafe(c.gone, Effect.void);
  };
  const json = (c: Conn, status: number, value: unknown): WireReply => {
    let done = false;
    const body = { take: Effect.sync(() => (done ? null : ((done = true), utf8(JSON.stringify(value))))) };
    return { status, headers: [["content-type", "application/json"]], body, via: "direct", ended: () => c.reason };
  };
  const lockAnswer = (method: string, path: string, body: Uint8Array): [number, unknown] => {
    const serves = { takes: ["person"], serves: ["person", "devices", "told"] };
    if (method === "GET" && (path === "/lock" || path.startsWith("/lock?after="))) {
      const after = path === "/lock" ? -1 : Number(path.split("=")[1]);
      return [200, { head: head(), entries: chain.filter((e) => e.seq > after), ...serves }];
    }
    if (method === "POST" && path === "/lock") {
      for (const e of (JSON.parse(new TextDecoder().decode(body)) as { entries: Entry[] }).entries) if (e.seq === chain.length) chain.push(e);
      return [200, { taken: 1, head: head() }];
    }
    if (method === "GET" && path === "/lock/devices") return [200, { devices: [] }];
    if (method === "GET" && path === "/lock/person") return [200, { chains: [] }];
    if (method === "POST" && path === "/lock/person") return [200, { taken: 1 }];
    return [404, { error: "no route" }];
  };
  const wire = (h: FakeHost): StationWire => {
    const other = new HostWire(h);
    return {
      request(addr: StationAddr, rh: RequestHead, body: Uint8Array): Effect.Effect<WireReply, CoreError, Scope.Scope> {
        if (addr.station !== A) return other.request(addr, rh, body);
        return Effect.suspend((): Effect.Effect<WireReply, CoreError, Scope.Scope> => {
          // (none yet while the core is made)
          const inner = at.inner;
          // (as MeshWire.request: a station that refused this device is not asked again until the lock moves on)
          const waits = inner === null ? null : (hooks.lockWaiting?.(inner, "ws", A) ?? null);
          if (waits) return Effect.fail(waits);
          if (at.conn === null) {
            dials.push(h.nowMs());
            if (!names()) {
              // Refused at its hello, telling its lock's last entries (serve.ts `refusalOf`).
              const e = new LockUnconfirmed("not approved", head(), [], chain.slice(1));
              return Effect.fail((inner === null ? null : hooks.lockRefused?.(inner, "ws", A, e.lock, { person: e.person, entries: e.entries })) ?? e);
            }
            at.conn = { reason: null, gone: Deferred.makeUnsafe<void>() };
          }
          const c = at.conn;
          const path = rh.path.replace("/admin/api", "");
          if (path.startsWith("/lock")) {
            const [status, value] = lockAnswer(rh.method.toUpperCase(), path, body);
            return Effect.succeed(json(c, status, value));
          }
          if (path.startsWith("/events")) {
            at.streams++;
            // Open until the connection ends: then gone, as a stream on a connection closed is.
            const take = Effect.flatMap(Deferred.await(c.gone), () => Effect.fail(new HostError("connection lost")));
            return Effect.succeed({ status: 200, headers: [["content-type", "text/event-stream"]], body: { take }, via: "direct", ended: () => c.reason } as WireReply);
          }
          return Effect.map(other.request(addr, rh, body), (r) => ({ ...r, ended: () => c.reason }));
        });
      },
    };
  };
  return { chain, at, dials, ends, head, names, end, wire };
}

/// A locked workspace `ws` (s1 the owner: this device, and OTHER, which signs elsewhere), its station A made before the
/// core (the rig's wire is asked for as the core is made), the lock read of it and held, the link to it up.
async function begun() {
  const g = grant();
  const owner = elsewhere();
  const slot: { st: ReturnType<typeof station> | null; first: Entry | null } = { st: null, first: null };
  const r = await rig(
    (me) => {
      const first = genesis("ws", me, true, [{ key: A, name: "a" }], g.keys, ME, [{ id: OTHER, sub: "s1", kind: "app", label: "other", sign_key: owner.id }]);
      slot.first = first;
      return { ws: first };
    },
    (h) => {
      slot.st = station(h, slot.first!);
    },
    A,
    [],
    (h) => slot.st!.wire(h),
  );
  const inner = r.core.inner;
  const st = slot.st!;
  st.at.inner = inner;
  const run = async <X>(e: Effect.Effect<X, any>) => {
    let done = false;
    let out: X | undefined;
    let failed: unknown;
    inner.runner.fork(Effect.match(e, { onSuccess: (x) => { out = x; done = true; }, onFailure: (f) => { failed = f; done = true; } }));
    await r.host.time.passUntil(5000, () => done);
    assert.ok(done, "no answer");
    if (failed !== undefined) throw failed;
    return out as X;
  };
  // (its key of its person's lock made before, as lock-stations.test.ts has it: these tests count no such entries)
  await run(inner.adb.personal().makeKey());
  await run(read(inner, "ws"));
  // The link to A up, its stream open.
  await r.host.time.passUntil(5000, () => st.at.streams !== 0);
  assert.ok(st.at.streams > 0, "the link's stream is open");
  assert.ok(fold(held(inner, "ws")!.entries).devices.has(ME), "this device is in the lock as held");
  /// Moves the clock on in steps of 10 ms until `cond` holds; how long that took.
  const until = async (cond: () => boolean, limitMs = 30_000) => {
    const from = r.host.nowMs();
    while (!cond()) {
      assert.ok(r.host.nowMs() - from < limitMs, "never");
      await r.host.time.pass(10);
    }
    return r.host.nowMs() - from;
  };
  /// The removal of this device, signed by OTHER.
  const removal = () => {
    const e = next("ws", st.head(), r.host.nowMs() / 1000, "device.remove", { id: ME });
    return { ...e, sig: { key: owner.id, alg: "Ed25519", sig: owner.signBytes(signedBytes(entryHash(e))) } } as Entry;
  };
  return { r, inner, st, until, removal };
}

test("a device taken out by another's entry, its connection ended for it, shows its waiting page at once", async () => {
  const { r, inner, st, until, removal } = await begun();
  // Up a while, as a device is when another takes it out.
  await r.host.time.pass(5_000);
  const lock = await r.watch({ topic: "lock", workspace: "ws" });
  assert.equal((await lock()).me.waiting, false);
  // The station takes the entry and ends this device's connection (13 ms later on a real one: at once here).
  st.chain.push(removal());
  const took = r.host.nowMs();
  st.end("lock_unconfirmed");
  const waited = await until(() => !fold(held(inner, "ws")!.entries).devices.has(ME));
  assert.ok(waited < 100, `the waiting page came ${waited} ms after the station took the entry (dialled at ${st.dials.map((d) => d - took).filter((d) => d >= 0).join(", ")} ms)`);
  assert.equal((await lock()).me.waiting, true);
  // Dialled once for it, refused, and not again while the lock stays where it is.
  const after = st.dials.filter((d) => d >= took);
  await r.host.time.pass(60_000);
  assert.equal(st.dials.filter((d) => d >= took).length, after.length, `dialled again at ${st.dials.filter((d) => d >= took).map((d) => d - took).join(", ")} ms`);
});

test("a station that keeps ending the link for its lock is dialled at once the first time only, at the old pace after", async () => {
  const { r, st } = await begun();
  // A station at odds with itself: it lets this device in and ends its connection for the lock once it has stood 3 s.
  for (let n = 0; n < 4; n++) {
    const streams = st.at.streams;
    for (let i = 0; i < 6_000 && st.at.streams === streams && n > 0; i++) await r.host.time.pass(10);
    await r.host.time.pass(3_000);
    st.end("lock_unconfirmed");
  }
  await r.host.time.pass(1_000);
  // How long after each end the station was dialled next.
  const gaps = st.ends.map((e) => (st.dials.find((d) => d >= e) ?? Infinity) - e);
  assert.ok(gaps[0]! < 100, `the first end dialled again at once: ${gaps.join(", ")} ms`);
  for (const g of gaps.slice(1, 3)) assert.ok(g >= RECONNECT_MS, `from the second try, at the old pace: ${gaps.join(", ")} ms`);
});
