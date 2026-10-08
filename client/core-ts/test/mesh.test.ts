// The Rust core's mesh.rs tests, ported, on a simulated network (sim-iroh.ts): a station and the client's mesh as they
// talk over iroh, each relay's lines as a test sets them, all on the test's clock. Nothing here waits for real time or
// depends on how busy the machine is: a run is the same every time its seed is (what varies: jitter, how writes are
// cut). Each test runs on the same seeds (sim-seeds.ts); a failure says its seed and network, and SIM_SEED=<seed> runs that
// one again.
// The native addon itself, the few things only it can show, at the end ("over the addon"): what it answers, never how
// long it takes.
import assert from "node:assert/strict";
import { suite, test as register, type TestOptions } from "node:test";
import { Effect, Queue } from "effect";
import type { Credential } from "../src/cloud.ts";
import { CoreError } from "../src/error.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Iroh } from "../src/iroh.ts";
import { ALPN, clearlyBetter, cost, DEVICE_KEY, EXPLORE_MS, FORMER_ALPN, HEDGE_FLOOR_MS, KEEP_WAYS, Mesh, MeshWire, PROBE_MS, RENEW_MS, SPEED_MIN_BYTES, TICK_MS, type CredentialSource, type Link } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { StationAddr } from "../src/station/addr.ts";
import { readAll, type RequestHead } from "../src/station/wire.ts";
import { Status } from "../src/status.ts";
import { FakeHost } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { hex } from "../src/util.ts";
import { Wake, Wakes } from "../src/wake.ts";
import { Station } from "./mesh-station.ts";
import { type RelaySpec, SimNet, SimTime } from "./sim-iroh.ts";
import { seeds } from "./sim-seeds.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const addon = loadAddon() as J;
const noAddon = addon === null ? "the mesh addon is not built here" : false;
type Body = () => Promise<void> | void;
const tests: [string, TestOptions, Body][] = [];
const text = (b: Uint8Array) => new TextDecoder().decode(b);

/// One run of a simulated test: its clock, network, host, and how it waits.
type Sim = {
  time: SimTime;
  net: SimNet;
  host: FakeHost;
  wakes: Wakes;
  runner: Runner;
  /// The device's iroh on this network.
  iroh: Iroh;
  /// Moves the clock on until `p` is done.
  settle<A>(p: Promise<A>, limitMs?: number): Promise<A>;
  /// Runs `effect` on the core's runner, moving the clock on until it is done.
  run<A, E>(effect: Effect.Effect<A, E>, limitMs?: number): Promise<A>;
  /// Moves the clock on until `cond` holds (looked at after each timer); fails after `limitMs`.
  until(cond: () => boolean, limitMs?: number): Promise<void>;
  /// A station on this network.
  station(alpns?: Uint8Array[]): Promise<Station>;
  stationOn(home: string, other: string | string[]): Promise<Station>;
  stationBound(options: J): Promise<Station>;
  /// Sets a relay's lines; gives its url.
  relay(url: string, spec?: RelaySpec): string;
};

/// A test on the simulated network, run on each seed; a failure says which.
function sim(name: string, body: (s: Sim) => Promise<void>) {
  tests.push([
    name,
    {},
    async () => {
      for (const seed of seeds()) {
        const time = new SimTime();
        const net = new SimNet(time.clock, seed);
        const host = new FakeHost(time);
        const wakes = new Wakes();
        const runner = new Runner(time.clock);
        const world = net.world();
        const s: Sim = {
          time,
          net,
          host,
          wakes,
          runner,
          iroh: net.iroh(),
          settle: (p, limitMs) => time.settle(p, limitMs),
          run: (effect, limitMs) => time.settle(runner.run(effect), limitMs),
          until: (cond, limitMs = 10 * 60_000) => time.until(cond, limitMs),
          station: (alpns) => time.settle(Station.start(alpns, world)),
          stationOn: (home, other) => time.settle(Station.on(home, other, world)),
          stationBound: (options) => time.settle(Station.bound(options, world)),
          relay: (url, spec) => net.relay(url, spec),
        };
        try {
          await body(s);
        } catch (e) {
          const error = e instanceof Error ? e : new Error(String(e));
          error.message = `${name} on ${net.describe()}:\n${error.message}`;
          throw error;
        } finally {
          runner.shutdown();
        }
      }
    },
  ]);
}

/// Grants "<prefix>-1", "<prefix>-2", … and counts them.
function grants(prefix: string, count: { n: number }): CredentialSource {
  return (device) =>
    Effect.sync(() => {
      assert.equal(device.length, 64);
      count.n++;
      return { credential: `${prefix}-${count.n}`, issued_at: 0, expires_at: 0, relay_url: "" } as Credential;
    });
}

function env(s: Sim) {
  return { host: s.host, runner: s.runner, tracer: new Tracer(s.host, s.runner, 1), iroh: s.iroh, wakes: s.wakes };
}

/// A station of its own and the device's mesh, which knows where it is.
async function setup(s: Sim, station?: Station) {
  const st = station ?? (await s.station());
  const mesh = await s.run(Mesh.make(env(s), []));
  mesh.addAddr(st.addr());
  return { mesh, station: st };
}

const head = (path: string): RequestHead => ({ method: "POST", path, headers: [["content-type", "application/json"]] });

function request(s: Sim, link: Link, h: RequestHead, body = new Uint8Array()) {
  return s.run(link.request(h, body));
}

/// A wire over `mesh`, as the core has one.
function wireOf(s: Sim, mesh: Mesh) {
  const status = new Status(s.host, s.runner);
  return new MeshWire({ mesh: () => Effect.succeed(mesh), meshNow: () => mesh, credentials: () => grants("ok", { n: 0 }), relays: () => [], status: () => status });
}

const network = (host: FakeHost) => new Wake(host.nowMs(), 0, true, false);

async function close(s: Sim, station: Station, mesh: Mesh) {
  await s.settle(station.close());
  await s.run(mesh.close());
}

sim("opens_requests_and_streams_the_reply", async (s) => {
  const { mesh, station } = await setup(s);
  assert.equal(s.host.stored(DEVICE_KEY)?.length, 32);
  const link = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  const reply = await request(s, link, head("/admin/api/sessions"), new TextEncoder().encode('{"a":1}'));
  assert.deepEqual(station.grants, ["ok-1"]);
  assert.equal(reply.status, 200);
  assert.ok(reply.headers.some(([k, v]) => k === "content-type" && v === "text/event-stream"));
  assert.ok(reply.headers.some(([k, v]) => k === "x-method" && v === "POST"));
  const all = text(await s.run(readAll(reply.body)));
  assert.deepEqual(JSON.parse(all.split("|")[0]!), { method: "POST", path: "/admin/api/sessions", headers: { "content-type": "application/json" } });
  assert.equal(all.split("|")[1], '{"a":1}');
  assert.ok(all.endsWith("|one|two|three"), all);
  assert.equal(link.closed(), null);
  await close(s, station, mesh);
});

sim("streams_a_reply_as_it_comes", async (s) => {
  const { mesh, station } = await setup(s);
  const link = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  const reply = await request(s, link, head("/admin/api/sessions"));
  // What the station said first comes before what it says 100 ms later.
  const first = text((await s.run(reply.body.take))!);
  assert.ok(!first.includes("one"), first);
  const rest = text(await s.run(readAll(reply.body)));
  assert.ok((first + rest).endsWith("|one|two|three"), first + rest);
  await close(s, station, mesh);
});

sim("reaches_stations_from_before_and_after_the_rename", async (s) => {
  for (const [alpns, spoken] of [[[FORMER_ALPN], FORMER_ALPN], [[ALPN, FORMER_ALPN], ALPN]] as [Uint8Array[], Uint8Array][]) {
    const { mesh, station } = await setup(s, await s.station(alpns));
    const link = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
    assert.equal((await request(s, link, head("/admin/api/overview"))).status, 200);
    assert.equal(hex(new Uint8Array(station.conns[0].alpn())), hex(spoken));
    await close(s, station, mesh);
  }
});

sim("refused_grant_fails_with_a_reason", async (s) => {
  const { mesh, station } = await setup(s);
  const count = { n: 0 };
  const link = await s.run(mesh.link(station.id(), grants("bad", count)));
  const error = await request(s, link, head("/admin/api/sessions")).then(
    () => null,
    (e) => e as CoreError,
  );
  assert.equal(error?.code, "credential_refused", JSON.stringify(error));
  assert.ok(error?.message.includes("station 拒绝了授权"), error?.message);
  const again = await s.run(mesh.link(station.id(), grants("bad", count)));
  assert.notEqual(link, again);
  assert.equal(count.n, 2);
  await close(s, station, mesh);
});

sim("reuses_the_open_link_and_shares_an_opening", async (s) => {
  const { mesh, station } = await setup(s);
  const count = { n: 0 };
  const id = station.id();
  const [a, b] = await s.settle(Promise.all([s.runner.run(mesh.link(id, grants("ok", count))), s.runner.run(mesh.link(id, grants("ok", count)))]));
  assert.equal(a, b);
  assert.equal(await s.run(mesh.link(id, grants("ok", count))), a);
  assert.equal(count.n, 1);
  await request(s, a, head("/admin/api/overview"));
  assert.equal(station.conns.length, 1);
  await close(s, station, mesh);
});

sim("reopens_a_closed_link_with_a_new_credential", async (s) => {
  const { mesh, station } = await setup(s);
  const count = { n: 0 };
  const first = await s.run(mesh.link(station.id(), grants("ok", count)));
  await request(s, first, head("/admin/api/overview"));
  station.conns[0].close(3, "credential_expired");
  await s.until(() => first.closed() !== null);
  assert.equal(first.closed(), "授权已过期");
  const second = await s.run(mesh.link(station.id(), grants("ok", count)));
  assert.notEqual(first, second);
  const reply = await request(s, second, head("/admin/api/overview"));
  assert.deepEqual(station.grants, ["ok-1", "ok-2"]);
  assert.equal(reply.status, 200);
  await s.run(readAll(reply.body));
  await close(s, station, mesh);
});

sim("keeps_the_device_key_and_migrates_to_the_pages", async (s) => {
  const e = env(s);
  const first = await s.run(Mesh.make(e, []));
  const again = await s.run(Mesh.make(e, []));
  assert.equal(first.deviceId(), again.deviceId());
  const page = new Uint8Array(32).fill(7);
  await s.run(first.migrate(page));
  assert.deepEqual([...(s.host.stored(DEVICE_KEY) ?? [])], [...page]);
  assert.notEqual(first.deviceId(), again.deviceId());
  const migrated = first.deviceId();
  await s.run(first.migrate(page));
  assert.equal(first.deviceId(), migrated);
  const bad = await s.run(first.migrate(new Uint8Array([1, 2, 3]))).then(
    () => null,
    (err) => err as CoreError,
  );
  assert.equal(bad?.code, "invalid_params");
  await s.run(first.close());
  await s.run(again.close());
});

sim("a_link_that_answers_as_the_network_changes_is_kept", async (s) => {
  const { mesh, station } = await setup(s);
  const link = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  await request(s, link, head("/admin/api/overview"));
  // The one opened beside it never is: it answering decides.
  station.unanswered(1);
  s.wakes.wake(network(s.host));
  // Past every wait the race has (the probe's, the other try's): nothing of it changes the link.
  await s.time.pass(2 * PROBE_MS);
  assert.equal(mesh.current(station.id()), link);
  assert.equal(link.closed(), null);
  await close(s, station, mesh);
});

sim("a_link_gone_quiet_is_replaced_by_one_opened_beside_it_at_once", async (s) => {
  const { mesh, station } = await setup(s);
  const id = station.id();
  const old = await s.run(mesh.link(id, grants("ok", { n: 0 })));
  await request(s, old, head("/admin/api/overview"));
  station.deadBelow = station.conns.length;
  const started = s.time.now();
  const replaced = s.runner.run(mesh.replaced(id, old));
  s.wakes.wake(network(s.host));
  await s.settle(replaced);
  // At once: the new one opened beside it, not after the probe of the old gave up.
  assert.ok(s.time.now() - started < PROBE_MS, `${s.time.now() - started}`);
  const next = mesh.current(id)!;
  assert.notEqual(old, next);
  assert.equal((await request(s, next, head("/admin/api/overview"))).status, 200);
  await close(s, station, mesh);
});

sim("a_write_is_asked_again_only_of_a_station_that_does_it_once", async (s) => {
  const { mesh, station } = await setup(s);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${station.id()}`);
  const ask = (h: RequestHead) => s.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  const post: RequestHead = { method: "POST", path: "/admin/api/x", headers: [["idempotency-key", "k1"]] };
  // Not said to keep writes to once: a write is asked once.
  assert.equal(await ask(post), 200);
  station.idempotent = true;
  assert.equal(await ask(post), 200);
  // Now it said so: the wire may ask it again.
  assert.equal(await ask({ method: "GET", path: "/admin/api/overview", headers: [] }), 200);
  await close(s, station, mesh);
});

/// Ways compared: one is better only beyond what both vary by, and a way's speed counts with its round trip (Hong
/// Kong's line back to the mainland, some 0.5 MB/s, against Beijing's 30).
test("a_way_is_better_only_beyond_what_the_two_vary_by", () => {
  assert.equal(clearlyBetter({ score: 100, dev: 5 }, { score: 98, dev: 5 }), false, "as good as each other");
  assert.equal(clearlyBetter({ score: 100, dev: 0 }, { score: 80, dev: 0 }), false, "not worth a move");
  assert.equal(clearlyBetter({ score: 100, dev: 5 }, { score: 60, dev: 5 }), true);
  assert.equal(clearlyBetter({ score: 100, dev: 80 }, { score: 60, dev: 5 }), false, "it varies more than they differ");
  const MB = 1024 * 1024;
  assert.equal(cost(100, null), 100);
  assert.equal(Math.round(cost(100, MB)), 100 + 250);
  assert.ok(cost(120, 0.5 * MB) > cost(200, 30 * MB), "a quicker round trip on a slow line costs more");
});

sim("renews_the_grant_until_the_link_closes", async (s) => {
  const { mesh, station } = await setup(s);
  const count = { n: 0 };
  const link = await s.run(mesh.link(station.id(), grants("ok", count)));
  // Renewed every RENEW_MS: three renewals by three of them.
  await s.time.pass(3 * RENEW_MS + 1000);
  assert.deepEqual(station.grants, ["ok-1", "ok-2", "ok-3", "ok-4"]);
  // Renewing kept the same link.
  assert.equal(await s.run(mesh.link(station.id(), grants("ok", count))), link);
  link.close();
  const asked = count.n;
  await s.time.pass(2 * RENEW_MS);
  assert.equal(count.n, asked);
  assert.equal(link.closed(), "连接已关闭");
  await close(s, station, mesh);
});

sim("a_refused_renewal_makes_the_next_link_reopen", async (s) => {
  const { mesh, station } = await setup(s);
  let n = 0;
  const refuseLater: CredentialSource = () => Effect.sync(() => ({ credential: ++n === 1 ? "ok" : "revoked", issued_at: 0, expires_at: 0, relay_url: "" }) as Credential);
  const first = await s.run(mesh.link(station.id(), refuseLater));
  await s.until(() => !first.usable(), 2 * RENEW_MS);
  const second = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  assert.notEqual(first, second);
  await close(s, station, mesh);
});

sim("a_read_under_way_on_a_link_that_is_replaced_is_answered_on_the_new_one", async (s) => {
  const { mesh, station } = await setup(s);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${station.id()}`);
  const get: RequestHead = { method: "GET", path: "/admin/api/overview", headers: [] };
  const ask = (h: RequestHead) => s.runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(await s.settle(ask(get)), 200);
  station.deadBelow = station.conns.length;
  // Sent on the dead way: it would never be answered.
  const asked = ask(get);
  await s.time.pass(50);
  const woken = s.time.now();
  s.wakes.wake(network(s.host));
  assert.equal(await s.settle(asked), 200);
  assert.ok(s.time.now() - woken < PROBE_MS / 2, `answered on the new link ${s.time.now() - woken} ms after the wake`);
  assert.equal(station.conns.length, 2);
  await close(s, station, mesh);
});

sim("a_write_whose_link_went_before_its_answer_is_asked_again_once_its_station_is_back", async (s) => {
  const { mesh, station } = await setup(s);
  station.idempotent = true;
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${station.id()}`);
  const ask = (h: RequestHead) => s.runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  // Its first answer says it keeps writes to once.
  assert.equal(await s.settle(ask({ method: "GET", path: "/admin/api/overview", headers: [] })), 200);
  station.deadBelow = station.conns.length;
  const asked = ask({ method: "POST", path: "/admin/api/sessions/k/pin", headers: [["idempotency-key", "k1"]] });
  await s.time.pass(50);
  // Its link goes before it is answered (the station restarting): asked again, with its key, on the next.
  station.conns[0].close(0, "restart");
  assert.equal(await s.settle(asked, 5_000), 200);
  assert.equal(station.conns.length, 2);
  await close(s, station, mesh);
});

sim("a_try_not_answered_makes_the_next_go_on_an_endpoint_bound_anew", async (s) => {
  const { mesh, station } = await setup(s);
  station.unanswered(1);
  const before = mesh.endpoint();
  const device = mesh.deviceId();
  const error = await s.run(mesh.link(station.id(), grants("ok", { n: 0 }))).then(
    () => null,
    (e) => e as CoreError,
  );
  assert.equal(error?.message, "连不上这台 station：没有回应");
  const link = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  assert.equal((await request(s, link, head("/admin/api/overview"))).status, 200);
  // Another endpoint (other sockets), the same device.
  assert.notEqual(mesh.endpoint(), before);
  assert.equal(mesh.deviceId(), device);
  // Answered: the next try stays on it.
  const now = mesh.endpoint();
  link.close();
  await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  assert.equal(mesh.endpoint(), now);
  await close(s, station, mesh);
});

sim("a_wake_while_a_try_goes_unanswered_opens_one_beside_it", async (s) => {
  const { mesh, station } = await setup(s);
  station.unanswered(1);
  const id = station.id();
  const opening = s.runner.run(mesh.link(id, grants("ok", { n: 0 })));
  await s.time.pass(50);
  // A person taps 重试 (client.wake, network) while a try that will never be answered is under way: another beside it
  // opens.
  const woken = s.time.now();
  s.wakes.wake(network(s.host));
  await s.settle(opening);
  assert.ok(s.time.now() - woken < 5_000, `${s.time.now() - woken}`);
  const link = mesh.current(id)!;
  assert.equal((await request(s, link, head("/admin/api/overview"))).status, 200);
  await close(s, station, mesh);
});

// ── relays ──

const sameRelay = (a: string | null, b: string) => a !== null && new URL(a).host === new URL(b).host;

/// The device's first link to the station, through its relays as they are.
async function reach(s: Sim, mesh: Mesh, id: string, relays?: string[]): Promise<Link> {
  const link = await s.run(mesh.link(id, grants("ok", { n: 0 }), relays));
  assert.equal((await request(s, link, head("/admin/api/overview"))).status, 200);
  return link;
}

/// A station at home on the first of `relays`, held on the others; the device's mesh on all of them, the first its own
/// (the one nearest it).
async function onRelays(s: Sim, relays: string[]) {
  const station = await s.stationOn(relays[0]!, relays.slice(1));
  const mesh = await s.run(Mesh.make(env(s), relays));
  return { station, mesh, id: station.id() };
}

/// The relay the station's requests go through now.
const via = (mesh: Mesh, id: string) => mesh.current(id)?.via() ?? null;

/// What a way costs as it truly is: its round trip, and a typical reply at its speed.
const truly = (s: Sim, relay: string) => {
  const [d, st] = [s.net.leg(relay, "device"), s.net.leg(relay, "station")];
  const bps = Math.min(d.bps ?? Infinity, st.bps ?? Infinity);
  return cost(2 * (d.ms + st.ms), Number.isFinite(bps) ? bps : null);
};

/// 2026-10-08: bft in Tokyo, phones in China. The phone's own relay (Beijing's, nearest it) lost a third of what went
/// between it and the station, and the phone dialled the station there alone: most tries waited out CONNECT_TIMEOUT_MS,
/// those that got through answered in seconds. Dialled every way at once, the link is the first through; the requests
/// settle on the way that answers quickest, and stay there.
sim("a_device_whose_own_relay_loses_the_station_is_linked_through_the_others", async (s) => {
  // a: next to the device, the station 70 ms away losing 35% (Beijing); b: 30 ms each side (Hong Kong); c: the station
  // next to it, the device 150 ms away (Cloudflare, Tokyo).
  const a = s.relay("https://a.relay.test/", { station: { ms: 70, loss: 0.35 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 30 }, station: { ms: 30 } });
  const c = s.relay("https://c.relay.test/", { device: { ms: 150 }, station: { ms: 5 } });
  const { station, mesh, id } = await onRelays(s, [a, b, c]);
  // A read as the core asks one, whole: how long it takes.
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${id}`);
  const read = async () => {
    const started = s.time.now();
    const status = await s.run(Effect.scoped(Effect.flatMap(wire.request(addr, { method: "GET", path: "/admin/api/overview", headers: [] }, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
    assert.equal(status, 200);
    return s.time.now() - started;
  };
  // The first: answered, not failed, though the way that came through first may be a's (its head is asked on another
  // way too if slow, but its body comes the way its head did: through a, losing a third, that can take a while).
  await read();
  // A minute on: through b, the best of them, and only KEEP_WAYS ways open; reads answered at once.
  await s.time.pass(60_000);
  for (let i = 0; i < 10; i++) {
    const took = await read();
    assert.ok(took < 2 * truly(s, b) + 400, `a read after ${took} ms`);
  }
  assert.ok(sameRelay(via(mesh, id), b), `through ${via(mesh, id)}: ${JSON.stringify(mesh.measured(id))}`);
  assert.ok(mesh.ways(id).length <= KEEP_WAYS, `${mesh.ways(id).length} ways open`);
  // Half an hour on, a lossy way among them: requests stay on b.
  const moves = mesh.moves(id);
  await s.time.pass(30 * 60_000);
  assert.ok(sameRelay(via(mesh, id), b), `through ${via(mesh, id)}`);
  assert.ok(mesh.moves(id) - moves <= 1, `moved ${mesh.moves(id) - moves} times`);
  // Closed: nothing of it left open.
  await close(s, station, mesh);
  await s.time.pass(60_000);
  assert.equal(s.net.open().length, 0, s.net.open().map((c) => `${c.endpoint.side} ${c.way.relay} ${c.reason?.kind ?? "open"} peer ${c.peer.reason?.kind ?? "open"}`).join("; "));
});

/// 2026-10-08, bft and phones in the mainland again: Beijing's machine took a way on into Hong Kong's relay (an entry,
/// cloud relays.ts), handed to devices among their relays. Their main endpoint went onto Hong Kong's relay straight and
/// through the entry under one key, and their endpoints of a relay of their own, looking the station up, onto its home
/// relay besides: one key on a relay twice, each connection taking the other's place there, and a phone's connects to
/// any station failed one in five. An entry is dialled on an endpoint of its own, relay-only, and through it alone: no
/// key is on a relay twice, and the station is reached through the entry, its best way.
sim("an_entry_is_dialled_on_its_own_endpoint_and_no_key_is_on_a_relay_twice", async (s) => {
  // a: next to the device, its line to the station losing a third (Beijing); b: the device's line to it long (Hong
  // Kong's back to the mainland); the entry: on a's machine, on to b over a good line.
  const a = s.relay("https://a.relay.test/", { device: { ms: 5 }, station: { ms: 70, loss: 0.35 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 60 }, station: { ms: 30 } });
  const entry = s.net.entry("https://a.relay.test:8443/", b, { device: { ms: 5 }, station: { ms: 40 } });
  const station = await s.stationOn(b, a);
  const id = station.id();
  const mesh = await s.run(Mesh.make(env(s), [a, b], [entry]));
  await reach(s, mesh, id);
  await s.time.pass(5 * 60_000);
  assert.equal(via(mesh, id), entry, JSON.stringify(mesh.measured(id)));
  // Dialled again on every way past EXPLORE_MS, and let go of: no key went onto a relay twice meanwhile.
  await s.time.pass(EXPLORE_MS + 60_000);
  assert.equal(via(mesh, id), entry, JSON.stringify(mesh.measured(id)));
  assert.deepEqual(s.net.twice(), []);
  assert.deepEqual(mesh.relays, [a, b]);
  await close(s, station, mesh);
});

/// A way that turns bad under requests (its relay's line to the station starts losing packets): they move to another
/// within a minute, not at the next measuring minutes later.
sim("requests_leave_a_way_that_turns_bad", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 10 } });
  const b = s.relay("https://b.relay.test/", { station: { ms: 40 } });
  const { station, mesh, id } = await onRelays(s, [a, b]);
  await reach(s, mesh, id);
  await s.time.pass(60_000);
  assert.ok(sameRelay(via(mesh, id), a), `${via(mesh, id)}`);
  s.relay(a, { station: { ms: 10, loss: 0.5 } });
  const turned = s.time.now();
  await s.until(() => sameRelay(via(mesh, id), b), 2 * 60_000);
  assert.ok(s.time.now() - turned <= 12 * TICK_MS, `moved ${s.time.now() - turned} ms after a turned bad`);
  await close(s, station, mesh);
});

/// A read whose way stops answering is asked on the next best way as well, and answered there, before the pings tell;
/// the requests follow once the pings do.
sim("a_read_slow_on_its_way_is_answered_on_another", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 10 } });
  const b = s.relay("https://b.relay.test/", { station: { ms: 40 } });
  const { station, mesh, id } = await onRelays(s, [a, b]);
  await reach(s, mesh, id);
  await s.time.pass(60_000);
  assert.ok(sameRelay(via(mesh, id), a), `${via(mesh, id)}`);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${id}`);
  // Down: a ping on it tells after PING_TIMEOUT_MS at the soonest, the read is asked on b well before.
  s.net.down(a, 5 * 60_000);
  const started = s.time.now();
  const status = await s.run(Effect.scoped(Effect.flatMap(wire.request(addr, { method: "GET", path: "/admin/api/overview", headers: [] }, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(status, 200);
  const took = s.time.now() - started;
  assert.ok(took < HEDGE_FLOOR_MS + 1_000, `answered after ${took} ms`);
  await s.until(() => sameRelay(via(mesh, id), b), 2 * 60_000);
  await close(s, station, mesh);
});

/// Two ways as good as each other: the requests are not moved back and forth between them.
sim("ways_as_good_as_each_other_are_not_swapped", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 20 } });
  const b = s.relay("https://b.relay.test/", { station: { ms: 20 } });
  const { station, mesh, id } = await onRelays(s, [a, b]);
  await reach(s, mesh, id);
  await s.time.pass(60 * 60_000);
  assert.ok(mesh.moves(id) <= 1, `moved ${mesh.moves(id)} times in an hour`);
  await close(s, station, mesh);
});

/// Judged by what it chooses: b answers sooner than a but brings a reply slowly (the device 60 ms away each way on a
/// 256 KiB/s line, as Hong Kong's back to the mainland). Its speed not known, requests go there; a large reply through
/// it shows how slow it is, and they go back to a, where the same reply comes sooner.
sim("requests_leave_a_way_found_slow_for_one_that_brings_replies_sooner", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 100 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 60, bps: 256 * 1024 } });
  const { station, mesh, id } = await onRelays(s, [b, a]);
  await reach(s, mesh, id);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${id}`);
  const big = async () => {
    const started = s.time.now();
    const bytes = await s.run(Effect.scoped(Effect.flatMap(wire.request(addr, { method: "GET", path: "/admin/api/big", headers: [] }, new Uint8Array()), (r) => readAll(r.body))));
    assert.ok(bytes.length >= SPEED_MIN_BYTES, `${bytes.length}`);
    return s.time.now() - started;
  };
  await s.until(() => sameRelay(via(mesh, id), b), 5 * 60_000);
  const throughB = await big();
  assert.ok(mesh.speed(id, b) !== null, "how fast b is, seen");
  await s.until(() => sameRelay(via(mesh, id), a), 5 * 60_000);
  const throughA = await big();
  assert.ok(throughA < throughB, `the reply through a ${throughA} ms, through b ${throughB} ms`);
  // And it stays on a.
  await s.time.pass(30 * 60_000);
  assert.ok(sameRelay(via(mesh, id), a), `${via(mesh, id)}`);
  await close(s, station, mesh);
});

/// A way let go (past KEEP_WAYS) is dialled again every EXPLORE_MS: once it became the best, the requests go there.
sim("a_way_let_go_is_tried_again_and_taken_once_it_is_the_best", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 50 } });
  const b = s.relay("https://b.relay.test/", { station: { ms: 60 } });
  const c = s.relay("https://c.relay.test/", { station: { ms: 200 } });
  const { station, mesh, id } = await onRelays(s, [a, b, c]);
  await reach(s, mesh, id);
  await s.time.pass(60_000);
  assert.ok(sameRelay(via(mesh, id), a), `${via(mesh, id)}`);
  assert.ok(!mesh.ways(id).some((w) => sameRelay(w.link.via(), c)), "c let go");
  s.relay(c, { station: { ms: 2 } });
  await s.until(() => sameRelay(via(mesh, id), c), EXPLORE_MS + 2 * 60_000);
  assert.ok(truly(s, c) < truly(s, a));
  await close(s, station, mesh);
});

/// Asked to measure (remeasure), a way just dialled that is clearly quicker is moved to at once, and each way shows
/// on its own, relays on the same host too. Its deviation started at half its round trip (RFC 6298's start, for a
/// timeout) and it scored twice its round trip: the requests stayed on a way 40% slower (side run, 2026-10-08).
sim("a_way_just_dialled_and_clearly_quicker_is_taken_when_asked", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 100 } });
  const b = s.relay("https://a.relay.test:444/", { device: { ms: 60 } });
  const station = await s.stationOn(b, a);
  const id = station.id();
  const mesh = await s.run(Mesh.make(env(s), [a]));
  await reach(s, mesh, id);
  assert.ok(sameRelay(via(mesh, id), a), `${via(mesh, id)}`);
  (mesh.relays as string[]).push(b);
  await s.run(mesh.remeasure(id));
  assert.equal(via(mesh, id), b, JSON.stringify(mesh.measured(id)));
  assert.equal(mesh.measured(id)!.relays.length, 2, JSON.stringify(mesh.measured(id)));
  await close(s, station, mesh);
});

/// A workspace's own relay (cloud directory.ts setRelays): its station is on that relay alone, the device's endpoint on
/// still.fail's; told the workspace's relays, the device reaches the station through it.
sim("reaches_a_station_through_its_workspaces_own_relay", async (s) => {
  const a = s.relay("https://a.relay.test/", { device: { ms: 5 }, station: { ms: 5 } });
  const b = s.relay("https://ws.relay.test/", { device: { ms: 20 }, station: { ms: 5 } });
  const station = await s.stationBound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [b], discovery: false, relayOnly: true });
  await s.settle(station.endpoint.online());
  const id = station.id();
  const mesh = await s.run(Mesh.make(env(s), [a]));
  const link = await reach(s, mesh, id, [b]);
  assert.ok(sameRelay(link.via(), b), `${link.via()}`);
  assert.deepEqual(mesh.relaysFor(id), [a, b]);
  // Its endpoint stays on still.fail's relay alone; a link asked for again without saying keeps the station's relays.
  assert.deepEqual(mesh.relays, [a]);
  assert.equal(await s.run(mesh.link(id, grants("ok", { n: 0 }))), link);
  assert.deepEqual(mesh.relaysFor(id), [a, b]);
  await close(s, station, mesh);
});

// ── adb.rs ──

import { Adb } from "../src/adb.ts";
import { parseAdb, MAX_MINUTES } from "../src/adb-parse.ts";
import { Store } from "../src/store.ts";
import type { TcpConnection } from "../src/host.ts";

/// adbd, as the host reaches it: says back what it hears.
function echoTcp(_port: number) {
  return Effect.gen(function* () {
    const said = yield* Queue.unbounded<Uint8Array | null>();
    return {
      read: { take: Queue.take(said) },
      write: (bytes: Uint8Array) => Effect.asVoid(Queue.offer(said, bytes)),
      end: () => void Queue.offerUnsafe(said, null),
    } satisfies TcpConnection;
  });
}

sim("offers_the_phone_and_tunnels_what_the_station_opens_to_its_adbd", async (s) => {
  // A station that takes a credential, then an offer: answers it, opens a tunnel and says "hello" through it.
  const endpoint = s.net.bindStation({ secretKey: s.net.key(), alpns: [ALPN], relayUrls: [], bindAddr: "127.0.0.1:0" });
  const seen: { offer?: J; echoed?: string; stopped?: boolean } = {};
  void (async () => {
    const conn = (await endpoint.accept())!;
    const control = (await conn.acceptBi())!;
    const c1 = { bytes: Buffer.alloc(0) };
    await Station.readLine(control, c1);
    await control.write(Buffer.from(`${JSON.stringify({ ok: true, station: "测试" })}\n`));
    const offer = (await conn.acceptBi())!;
    const c2 = { bytes: Buffer.alloc(0) };
    seen.offer = JSON.parse((await Station.readLine(offer, c2))!);
    await offer.write(Buffer.from(`${JSON.stringify({ status: 200, headers: {} })}\n`));
    await offer.write(Buffer.from(`${JSON.stringify({ serial: "127.0.0.1:37001", adb: "connected", message: "" })}\n`));
    const tunnel = await conn.openBi();
    await tunnel.write(Buffer.from(`${JSON.stringify({ tunnel: "connect" })}\n`));
    const c3 = { bytes: Buffer.alloc(0) };
    assert.deepEqual(JSON.parse((await Station.readLine(tunnel, c3))!), { ok: true });
    await tunnel.write(Buffer.from("hello"));
    let back = c3.bytes;
    while (back.length < 5) {
      const chunk = await tunnel.read();
      if (chunk === null) break;
      back = Buffer.concat([back, chunk]);
    }
    seen.echoed = back.toString();
    await offer.stopped();
    seen.stopped = true;
  })().catch(() => {});
  s.host.tcpConnect = echoTcp;
  const mesh = await s.run(Mesh.make(env(s), []));
  mesh.addAddr({ id: endpoint.id(), ips: endpoint.sockets() });
  const store = new Store(s.host, s.runner);
  const adb = new Adb({ host: s.host, runner: s.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential), relays: () => [] });
  const station = `ws/${endpoint.id()}`;
  await s.run(adb.run({ kind: "share", offer: { station, connect: 5555, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 } }));
  await s.until(() => seen.echoed !== undefined && adb.value().tunnels === 1 && adb.value().adb === "connected");
  const offered = seen.offer;
  assert.equal(offered.path, "/admin/api/adb");
  assert.equal(offered.adb.phone.length, 64);
  delete offered.adb.phone;
  assert.deepEqual(offered.adb, { op: "share", device: "Pixel 8", android: "14", package: "fail.still.android", adbd: true, pair: false });
  assert.equal(seen.echoed, "hello");
  const value = adb.value();
  assert.deepEqual([value.sharing, value.station, value.phase, value.serial], [true, station, "offered", "127.0.0.1:37001"]);
  await s.run(adb.run({ kind: "stop" }));
  await s.until(() => seen.stopped === true);
  assert.ok(seen.stopped, "the station sees the offer stop");
  const after = adb.value();
  assert.deepEqual([after.sharing, after.phase], [false, "off"]);
  await s.run(mesh.close());
  await s.settle(endpoint.close());
});

test("reads_its_calls", () => {
  const share = parseAdb("adb.share", { station: "ws/st", connect: 41234, minutes: 10_000 });
  assert.deepEqual(share, { kind: "share", offer: { station: "ws/st", connect: 41234, pair: null, device: "", android: "", package: "", minutes: MAX_MINUTES } });
  assert.throws(() => parseAdb("adb.share", {}));
  assert.deepEqual(parseAdb("adb.pair", { code: "123456" }), { kind: "pair", code: "123456" });
  assert.equal(parseAdb("job.stop", {}), null);
});

// ── over the addon: what only it can show, never timed ──

function test(name: string, options: TestOptions | Body, body?: Body) {
  if (typeof options === "function") tests.push([name, {}, options]);
  else tests.push([name, options, body!]);
}

test("over_the_addon_opens_requests_and_streams_the_reply", { skip: noAddon }, async () => {
  const station = await Station.start();
  const host = new FakeHost();
  const runner = new Runner();
  const mesh = await runner.run(Mesh.make({ host, runner, tracer: new Tracer(host, runner, 1), iroh: nodeIroh()!, wakes: new Wakes() }, []));
  mesh.addAddr(station.addr());
  const link = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  const reply = await runner.run(link.request(head("/admin/api/sessions"), new TextEncoder().encode('{"a":1}')));
  assert.equal(reply.status, 200);
  const all = text(await runner.run(readAll(reply.body)));
  assert.equal(all.split("|")[1], '{"a":1}');
  assert.ok(all.endsWith("|one|two|three"), all);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("over_the_addon_relay_probes_disable_ip_without_disabling_live_hole_punching", { skip: noAddon }, async () => {
  // No relay needed to see it: a relay-only endpoint has no sockets of its own, another has.
  const probe = await addon.bind({ secretKey: Buffer.alloc(32, 31), alpns: [], relayUrls: ["http://127.0.0.1:9/"], discovery: false, relayOnly: true });
  assert.deepEqual(probe.sockets(), []);
  const live = await addon.bind({ secretKey: Buffer.alloc(32, 32), alpns: [], relayUrls: ["http://127.0.0.1:9/"], discovery: false });
  assert.ok(live.sockets().length > 0);
  await probe.close();
  await live.close();
});

suite("mesh", { concurrency: true }, () => {
  for (const [name, options, body] of tests) register(name, options, body);
});
