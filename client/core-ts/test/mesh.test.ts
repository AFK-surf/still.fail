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
import { ALPN, cost, DEVICE_KEY, FORMER_ALPN, Mesh, MeshWire, PROBE_MS, RENEW_MS, RETIRE_MS, quicker, sampleRelayRtt, SPEED_MIN_BYTES, type CredentialSource, type Link } from "../src/mesh.ts";
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
  stationOn(home: string, other: string): Promise<Station>;
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

test("moves_only_to_a_clearly_quicker_relay", () => {
  const a = "https://a.relay.test/";
  const b = "https://b.relay.test/";
  assert.equal(quicker(300, a, [[a, 300], [b, 250]]), null, "50 ms is not 20% of 300");
  assert.equal(quicker(300, a, [[a, 300], [b, 200]]), b);
  assert.equal(quicker(300, b, [[a, 300], [b, 200]]), null, "already through it");
  assert.equal(quicker(null, a, [[a, null], [b, 100]]), null, "nothing to compare with");
  assert.equal(quicker(1000, a, [[a, 11_000], [b, 82]]), b, "fresh measurements of the same round win over the link's estimate");
});

/// A way's speed is weighed with its round trip: a relay with the shorter round trip but a slow line (Hong Kong's back
/// to the mainland, some 0.5 MB/s, against Beijing's 30) is not moved to, and a link on one is moved off it.
test("weighs_each_relays_speed_with_its_round_trip", () => {
  const a = "https://a.relay.test/";
  const b = "https://b.relay.test/";
  const MB = 1024 * 1024;
  const speeds = (sa: number | null, sb: number | null) => (r: string) => (r === a ? sa : r === b ? sb : null);
  assert.equal(quicker(200, a, [[a, 200], [b, 120]], speeds(30 * MB, 0.5 * MB)), null, "b answers sooner, but a reply takes half a second more");
  assert.equal(quicker(200, a, [[a, 200], [b, 120]], speeds(30 * MB, null)), b, "b's speed not known yet: it is tried");
  assert.equal(quicker(120, b, [[a, 200], [b, 120]], speeds(30 * MB, 0.5 * MB)), a, "found slow, the link goes back");
  assert.equal(quicker(200, a, [[a, 200], [b, 120]], speeds(30 * MB, 20 * MB)), b, "both fast: the round trip decides");
  assert.equal(cost(100, null), 100);
  assert.equal(Math.round(cost(100, MB)), 100 + 250);
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

/// A phone's link to a station abroad went through the relay nearest the phone, the station's way there slow
/// (2026-10-01, bft: 11 s a round trip); measured, it moves to the relay that is quicker the whole way.
sim("a_link_through_a_slow_relay_moves_to_the_quicker_one", async (s) => {
  // a: the station 65 ms away each way; b: next to both.
  const a = s.relay("https://a.relay.test/", { station: { ms: 65 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 2 }, station: { ms: 2 } });
  const station = await s.stationOn(b, a);
  const id = station.id();
  // As it went: through a, the only relay the device was on then.
  const mesh = await s.run(Mesh.make(env(s), [a]));
  const link = await reach(s, mesh, id);
  const slow = link.net().rttMs!;
  assert.ok(sameRelay(link.via(), a), `${link.via()}`);
  // Now on both: measured, it moves to b.
  (mesh.relays as string[]).push(b);
  await s.run(mesh.remeasure(id));
  const moved = mesh.current(id)!;
  assert.notEqual(moved, link);
  assert.ok(sameRelay(moved.via(), b), `${moved.via()}`);
  assert.ok(moved.pinned !== null && sameRelay(moved.pinned, b));
  for (let i = 0; i < 5; i++) assert.equal((await request(s, moved, head("/admin/api/overview"))).status, 200);
  assert.ok(moved.net().rttMs! < slow / 2, `${moved.net().rttMs} vs ${slow}`);
  // On b's own endpoint, under a key of its own: the station sees another device.
  const device = station.conns.filter((c: J) => !c.isClosed()).at(-1).remoteId();
  assert.notEqual(device, mesh.deviceId());
  const shown = mesh.measured(id)!;
  assert.equal(shown.measuring, false);
  assert.equal(shown.moved, new URL(b).hostname);
  assert.equal(shown.relays.length, 2);
  assert.ok(shown.relays.every(([, ms]) => ms !== null), JSON.stringify(shown));
  // Measured again, as a person asks: it stays, nothing is quicker than where it is.
  await s.run(mesh.remeasure(id));
  assert.equal(mesh.measured(id)!.moved, null);
  assert.equal(mesh.current(id), moved);
  // The endpoint only measured on is let go (RETIRE_MS after measuring); b's, with the link on it, stays.
  await s.time.pass(RETIRE_MS + 1000);
  assert.equal((await request(s, moved, head("/admin/api/overview"))).status, 200);
  await close(s, station, mesh);
});

/// How long a request takes on `link`, on the test's clock.
async function took(s: Sim, link: Link): Promise<number> {
  const started = s.time.now();
  assert.equal((await request(s, link, head("/admin/api/overview"))).status, 200);
  return s.time.now() - started;
}

/// The choice judged by what it chooses: of two relays, one next to the device but far from the station, one far from the
/// device but next to the station, the link ends up on the one its requests are answered quicker through. Measured with
/// QUIC's smoothed estimate, the probe's getting onto the far relay counted (several times the device's distance to it),
/// and the link stayed on the near one (2026-10-05: bft in Tokyo, the device in China, kept on Beijing's relay, never
/// on Cloudflare's or Hong Kong's).
sim("a_link_moves_to_the_relay_its_requests_go_quicker_through_far_from_the_device_or_not", async (s) => {
  // a: the device at once, the station 100 ms each way (200 ms a round trip); b: the device 60 ms each way (getting
  // onto it as well), the station at once (120 ms).
  const a = s.relay("https://a.relay.test/", { station: { ms: 100 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 60 } });
  const station = await s.stationOn(b, a);
  const id = station.id();
  const mesh = await s.run(Mesh.make(env(s), [a]));
  const link = await reach(s, mesh, id);
  assert.ok(sameRelay(link.via(), a), `${link.via()}`);
  const throughA = await took(s, link);
  (mesh.relays as string[]).push(b);
  await s.run(mesh.remeasure(id));
  const now = mesh.current(id)!;
  assert.ok(sameRelay(now.via(), b), `still through ${now.via()}: ${JSON.stringify(mesh.measured(id))}`);
  const throughB = await took(s, now);
  assert.ok(throughB < throughA, `requests through b ${throughB} ms, through a ${throughA} ms`);
  await close(s, station, mesh);
});

/// Judged by what it chooses, again: b answers sooner than a but brings a reply slowly (the device 60 ms away each way
/// on a 256 KiB/s line, as Hong Kong's back to the mainland). Its speed not known, the link goes there; a large reply
/// through it shows how slow it is, and the link goes back to a, where the same reply comes sooner.
sim("a_link_leaves_a_relay_found_slow_for_one_that_brings_replies_sooner", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 100 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 60, bps: 256 * 1024 } });
  const station = await s.stationOn(b, a);
  const id = station.id();
  const mesh = await s.run(Mesh.make(env(s), [a]));
  await reach(s, mesh, id);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${id}`);
  // A large reply, as the core reads one: how long it takes.
  const big = async () => {
    const started = s.time.now();
    const bytes = await s.run(Effect.scoped(Effect.flatMap(wire.request(addr, head("/admin/api/big"), new Uint8Array()), (r) => readAll(r.body))));
    assert.ok(bytes.length >= SPEED_MIN_BYTES, `${bytes.length}`);
    return s.time.now() - started;
  };
  (mesh.relays as string[]).push(b);
  await s.run(mesh.remeasure(id));
  assert.ok(sameRelay(mesh.current(id)!.via(), b), `${mesh.current(id)!.via()}`);
  const throughB = await big();
  assert.ok(mesh.speed(id, b) !== null, "how fast b is, seen");
  await s.run(mesh.remeasure(id));
  assert.ok(sameRelay(mesh.current(id)!.via(), a), `still through ${mesh.current(id)!.via()}: ${JSON.stringify({ ...mesh.measured(id), speedB: mesh.speed(id, b), throughB })}`);
  const throughA = await big();
  assert.ok(throughA < throughB, `the reply through a ${throughA} ms, through b ${throughB} ms`);
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

test("over_the_addon_a_direct_rtt_is_never_reported_as_a_relay_measurement", { skip: noAddon }, async () => {
  const station = await Station.start();
  const runner = new Runner();
  const endpoint = await runner.run(nodeIroh()!.bind({ secretKey: new Uint8Array(32).fill(5), relayUrls: [], lookup: false, relayOnly: false }));
  endpoint.addAddr(station.addr());
  const conn = await runner.run(endpoint.connect({ id: station.id(), relays: [] }, ALPN, []));
  assert.equal(await runner.run(sampleRelayRtt(conn, "https://relay.test/")), null);
  conn.close(0, "done");
  await runner.run(endpoint.close());
  await station.close();
  runner.shutdown();
});

suite("mesh", { concurrency: true }, () => {
  for (const [name, options, body] of tests) register(name, options, body);
});
