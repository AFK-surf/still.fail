// The Rust core's mesh.rs tests, ported: a station on localhost over the native addon (station/native/mesh), the
// client's mesh over the same addon. Real time here (iroh needs its own clock).
// Each test has its own station, endpoints, runner and relays: they all run at once (the suite at the end).
import assert from "node:assert/strict";
import { suite, test as register, type TestOptions } from "node:test";
import { Clock, Duration, Effect } from "effect";
import type { Credential } from "../src/cloud.ts";
import { CoreError } from "../src/error.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import { ALPN, CONNECT_TIMEOUT_MS, DEVICE_KEY, FORMER_ALPN, Mesh, MeshWire, PROBE_MS, RENEW_MS, RETIRE_MS, quicker, sampleRelayRtt, type CredentialSource, type Link } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { StationAddr } from "../src/station/addr.ts";
import { readAll, type RequestHead } from "../src/station/wire.ts";
import { Status } from "../src/status.ts";
import { FakeHost } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { hex } from "../src/util.ts";
import { Wake, Wakes } from "../src/wake.ts";
import { Station } from "./mesh-station.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const addon = loadAddon() as J;
const skip = addon === null ? "the mesh addon is not built here" : false;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
type Body = () => Promise<void> | void;
const tests: [string, TestOptions, Body][] = [];
function test(name: string, options: TestOptions | Body, body?: Body) {
  if (typeof options === "function") tests.push([name, {}, options]);
  else tests.push([name, options, body!]);
}
const text = (b: Uint8Array) => new TextDecoder().decode(b);

/// Grants "<prefix>-1", "<prefix>-2", … and counts them.
function grants(prefix: string, count: { n: number }): CredentialSource {
  return (device) =>
    Effect.sync(() => {
      assert.equal(device.length, 64);
      count.n++;
      return { credential: `${prefix}-${count.n}`, issued_at: 0, expires_at: 0, relay_url: "" } as Credential;
    });
}

/// Real time but for `times`: each timer of a duration there lasts as long as it says instead, read as the timer starts
/// (changed later, it changes the timers started after). By default renewals every 150 ms, as mesh.rs's tests'
/// QuickHost had them. (CONNECT_TIMEOUT_MS and RETIRE_MS are both 10 s: one entry is both. Shortened, a connection on a
/// machine busy with other tests may well take longer: a test shortens them only while nothing it needs is connecting.)
function quickClock(times = new Map([[RENEW_MS, 150]])): Clock.Clock {
  const base = Effect.runSync(Clock.clockWith(Effect.succeed));
  const quick = (ms: number) => times.get(ms) ?? ms;
  return {
    currentTimeMillisUnsafe: () => base.currentTimeMillisUnsafe(),
    currentTimeMillis: base.currentTimeMillis,
    currentTimeNanosUnsafe: () => base.currentTimeNanosUnsafe(),
    currentTimeNanos: base.currentTimeNanos,
    monotonicTimeNanosUnsafe: () => base.monotonicTimeNanosUnsafe(),
    monotonicTimeNanos: base.monotonicTimeNanos,
    sleep: (d: Duration.Duration) => base.sleep(Duration.millis(quick(Duration.toMillis(d)))),
  } as Clock.Clock;
}

function env(host: FakeHost, wakes = new Wakes(), clock?: Clock.Clock) {
  const runner = new Runner(clock);
  return { host, runner, tracer: new Tracer(host, runner, 1), iroh: nodeIroh()!, wakes };
}

async function setup(station?: Station, host = new FakeHost(), wakes = new Wakes(), clock?: Clock.Clock) {
  const s = station ?? (await Station.start());
  const e = env(host, wakes, clock);
  const mesh = await e.runner.run(Mesh.make(e, []));
  mesh.addAddr(s.addr());
  return { mesh, station: s, runner: e.runner, host };
}

const head = (path: string): RequestHead => ({ method: "POST", path, headers: [["content-type", "application/json"]] });

async function request(runner: Runner, link: Link, h: RequestHead, body = new Uint8Array()) {
  return runner.run(link.request(h, body));
}

test("opens_requests_and_streams_the_reply", { skip }, async () => {
  const { mesh, station, runner, host } = await setup();
  assert.equal(host.stored(DEVICE_KEY)?.length, 32);
  const link = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  const reply = await request(runner, link, head("/admin/api/sessions"), new TextEncoder().encode('{"a":1}'));
  assert.deepEqual(station.grants, ["ok-1"]);
  assert.equal(reply.status, 200);
  assert.ok(reply.headers.some(([k, v]) => k === "content-type" && v === "text/event-stream"));
  assert.ok(reply.headers.some(([k, v]) => k === "x-method" && v === "POST"));
  const first = text((await runner.run(reply.body.take))!);
  assert.deepEqual(JSON.parse(first.split("|")[0]), { method: "POST", path: "/admin/api/sessions", headers: { "content-type": "application/json" } });
  assert.equal(first.split("|")[1], '{"a":1}');
  assert.ok(!first.includes("three"));
  const rest = text(await runner.run(readAll(reply.body)));
  assert.ok(rest.endsWith("|one|two|three"), rest);
  assert.equal(link.closed(), null);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("reaches_stations_from_before_and_after_the_rename", { skip }, async () => {
  for (const [alpns, spoken] of [[[FORMER_ALPN], FORMER_ALPN], [[ALPN, FORMER_ALPN], ALPN]] as [Uint8Array[], Uint8Array][]) {
    const { mesh, station, runner } = await setup(await Station.start(alpns));
    const link = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
    const reply = await request(runner, link, head("/admin/api/overview"));
    assert.equal(reply.status, 200);
    assert.equal(hex(new Uint8Array(station.conns[0].alpn())), hex(spoken));
    await station.close();
    await runner.run(mesh.close());
  runner.shutdown();
  }
});

test("refused_grant_fails_with_a_reason", { skip }, async () => {
  const { mesh, station, runner } = await setup();
  const count = { n: 0 };
  const link = await runner.run(mesh.link(station.id(), grants("bad", count)));
  const error = await request(runner, link, head("/admin/api/sessions")).then(
    () => null,
    (e) => e as CoreError,
  );
  assert.equal(error?.code, "credential_refused", JSON.stringify(error));
  assert.ok(error?.message.includes("station 拒绝了授权"), error?.message);
  const again = await runner.run(mesh.link(station.id(), grants("bad", count)));
  assert.notEqual(link, again);
  assert.equal(count.n, 2);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("reuses_the_open_link_and_shares_an_opening", { skip }, async () => {
  const { mesh, station, runner } = await setup();
  const count = { n: 0 };
  const id = station.id();
  const [a, b] = await Promise.all([runner.run(mesh.link(id, grants("ok", count))), runner.run(mesh.link(id, grants("ok", count)))]);
  assert.equal(a, b);
  const c = await runner.run(mesh.link(id, grants("ok", count)));
  assert.equal(a, c);
  assert.equal(count.n, 1);
  await request(runner, a, head("/admin/api/overview"));
  assert.equal(station.conns.length, 1);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("reopens_a_closed_link_with_a_new_credential", { skip }, async () => {
  const { mesh, station, runner } = await setup();
  const count = { n: 0 };
  const first = await runner.run(mesh.link(station.id(), grants("ok", count)));
  await request(runner, first, head("/admin/api/overview"));
  station.conns[0].close(3, "credential_expired");
  for (let i = 0; i < 100 && first.closed() === null; i++) await sleep(20);
  assert.equal(first.closed(), "授权已过期");
  const second = await runner.run(mesh.link(station.id(), grants("ok", count)));
  assert.notEqual(first, second);
  const reply = await request(runner, second, head("/admin/api/overview"));
  assert.deepEqual(station.grants, ["ok-1", "ok-2"]);
  assert.equal(reply.status, 200);
  await runner.run(readAll(reply.body));
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("keeps_the_device_key_and_migrates_to_the_pages", { skip }, async () => {
  const host = new FakeHost();
  const e = env(host);
  const first = await e.runner.run(Mesh.make(e, []));
  const again = await e.runner.run(Mesh.make(e, []));
  assert.equal(first.deviceId(), again.deviceId());
  const page = new Uint8Array(32).fill(7);
  await e.runner.run(first.migrate(page));
  assert.deepEqual([...(host.stored(DEVICE_KEY) ?? [])], [...page]);
  assert.notEqual(first.deviceId(), again.deviceId());
  const migrated = first.deviceId();
  await e.runner.run(first.migrate(page));
  assert.equal(first.deviceId(), migrated);
  const bad = await e.runner.run(first.migrate(new Uint8Array([1, 2, 3]))).then(
    () => null,
    (err) => err as CoreError,
  );
  assert.equal(bad?.code, "invalid_params");
  await e.runner.run(first.close());
  await e.runner.run(again.close());
  e.runner.shutdown();
});

const network = (host: FakeHost) => new Wake(host.nowMs(), 0, true, false);

test("a_link_that_answers_as_the_network_changes_is_kept", { skip }, async () => {
  const wakes = new Wakes();
  const { mesh, station, runner, host } = await setup(undefined, new FakeHost(), wakes);
  const link = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  await request(runner, link, head("/admin/api/overview"));
  // The one opened beside it never is: it answering decides, not which of the two is quicker on this machine.
  station.unanswered(1);
  wakes.wake(network(host));
  await sleep(500);
  assert.equal(mesh.current(station.id()), link);
  assert.equal(link.closed(), null);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("a_link_gone_quiet_is_replaced_by_one_opened_beside_it_at_once", { skip }, async () => {
  const wakes = new Wakes();
  const { mesh, station, runner, host } = await setup(undefined, new FakeHost(), wakes);
  const id = station.id();
  const old = await runner.run(mesh.link(id, grants("ok", { n: 0 })));
  await request(runner, old, head("/admin/api/overview"));
  station.deadBelow = station.conns.length;
  const started = Date.now();
  const replaced = runner.run(mesh.replaced(id, old));
  wakes.wake(network(host));
  await replaced;
  assert.ok(Date.now() - started < 2500, `${Date.now() - started}`);
  const next = mesh.current(id)!;
  assert.notEqual(old, next);
  assert.equal((await request(runner, next, head("/admin/api/overview"))).status, 200);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
});

test("a_write_is_asked_again_only_of_a_station_that_does_it_once", { skip }, async () => {
  const wakes = new Wakes();
  const { mesh, station, runner, host } = await setup(undefined, new FakeHost(), wakes);
  const status = new Status(host, runner);
  const wire = new MeshWire({ mesh: () => Effect.succeed(mesh), meshNow: () => mesh, credentials: () => grants("ok", { n: 0 }), relays: () => [], status: () => status });
  const addr = StationAddr.parse(`w/${station.id()}`);
  const post: RequestHead = { method: "POST", path: "/admin/api/x", headers: [["idempotency-key", "k1"]] };
  // Not said to keep writes to once: a write is asked once.
  const ask = (h: RequestHead) => runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(await ask(post), 200);
  station.idempotent = true;
  assert.equal(await ask(post), 200);
  // Now it said so: the wire may ask it again.
  assert.equal(await ask({ method: "GET", path: "/admin/api/overview", headers: [] }), 200);
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
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

const close = async (station: Station, runner: Runner, mesh: Mesh) => {
  await station.close();
  await runner.run(mesh.close());
  runner.shutdown();
};

test("renews_the_grant_until_the_link_closes", { skip }, async () => {
  const { mesh, station, runner } = await setup(undefined, new FakeHost(), new Wakes(), quickClock());
  const count = { n: 0 };
  const link = await runner.run(mesh.link(station.id(), grants("ok", count)));
  // Renewed every 150 ms: three by some 300 ms, waited for as long as a busy machine takes.
  for (let i = 0; i < 250 && station.grants.length < 3; i++) await sleep(20);
  const seen = [...station.grants];
  assert.ok(seen.length >= 3, JSON.stringify(seen));
  assert.deepEqual(seen.slice(0, 3), ["ok-1", "ok-2", "ok-3"]);
  // Renewing kept the same link.
  assert.equal(await runner.run(mesh.link(station.id(), grants("ok", count))), link);
  link.close();
  const asked = count.n;
  await sleep(400);
  assert.equal(count.n, asked);
  assert.equal(link.closed(), "连接已关闭");
  await close(station, runner, mesh);
});

test("a_refused_renewal_makes_the_next_link_reopen", { skip }, async () => {
  const { mesh, station, runner } = await setup(undefined, new FakeHost(), new Wakes(), quickClock());
  let n = 0;
  const refuseLater: CredentialSource = () => Effect.sync(() => ({ credential: ++n === 1 ? "ok" : "revoked", issued_at: 0, expires_at: 0, relay_url: "" }) as Credential);
  const first = await runner.run(mesh.link(station.id(), refuseLater));
  // Its renewal (150 ms on) refused, as a busy machine takes.
  for (let i = 0; i < 250 && first.usable(); i++) await sleep(20);
  const second = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  assert.notEqual(first, second);
  await close(station, runner, mesh);
});

/// A wire over `mesh` for the station `id`, as the core has one.
function wireOf(mesh: Mesh, runner: Runner, host: FakeHost) {
  const status = new Status(host, runner);
  return new MeshWire({ mesh: () => Effect.succeed(mesh), meshNow: () => mesh, credentials: () => grants("ok", { n: 0 }), relays: () => [], status: () => status });
}
const within = <A>(ms: number, p: Promise<A>, what: string) => Promise.race([p, sleep(ms).then(() => Promise.reject(new Error(`${what}: not within ${ms} ms`)))]);

test("a_read_under_way_on_a_link_that_is_replaced_is_answered_on_the_new_one", { skip }, async () => {
  const wakes = new Wakes();
  const { mesh, station, runner, host } = await setup(undefined, new FakeHost(), wakes);
  const wire = wireOf(mesh, runner, host);
  const addr = StationAddr.parse(`w/${station.id()}`);
  const get: RequestHead = { method: "GET", path: "/admin/api/overview", headers: [] };
  const ask = (h: RequestHead) => runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(await ask(get), 200);
  station.deadBelow = station.conns.length;
  // Sent on the dead way: it would never be answered.
  const asked = ask(get);
  await sleep(50);
  wakes.wake(network(host));
  assert.equal(await within(PROBE_MS / 2, asked, "answered on the new link"), 200);
  assert.equal(station.conns.length, 2);
  await close(station, runner, mesh);
});

test("a_write_whose_link_went_before_its_answer_is_asked_again_once_its_station_is_back", { skip }, async () => {
  const { mesh, station, runner, host } = await setup();
  station.idempotent = true;
  const wire = wireOf(mesh, runner, host);
  const addr = StationAddr.parse(`w/${station.id()}`);
  const ask = (h: RequestHead) => runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, h, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  // Its first answer says it keeps writes to once.
  assert.equal(await ask({ method: "GET", path: "/admin/api/overview", headers: [] }), 200);
  station.deadBelow = station.conns.length;
  const asked = ask({ method: "POST", path: "/admin/api/sessions/k/pin", headers: [["idempotency-key", "k1"]] });
  await sleep(50);
  // Its link goes before it is answered (the station restarting): asked again, with its key, on the next.
  station.conns[0].close(0, "restart");
  assert.equal(await within(5_000, asked, "asked again"), 200);
  assert.equal(station.conns.length, 2);
  await close(station, runner, mesh);
});

test("a_try_not_answered_makes_the_next_go_on_an_endpoint_bound_anew", { skip }, async () => {
  // A connection unanswered after 1 s (time enough, on a busy machine, for the try to reach the station, which holds it
  // unanswered: given up on sooner, the next would be the one held).
  const times = new Map([[CONNECT_TIMEOUT_MS, 1000]]);
  const { mesh, station, runner } = await setup(undefined, new FakeHost(), new Wakes(), quickClock(times));
  station.unanswered(1);
  const before = mesh.endpoint();
  const device = mesh.deviceId();
  const error = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 }))).then(
    () => null,
    (e) => e as CoreError,
  );
  assert.equal(error?.message, "连不上这台 station：没有回应");
  times.clear();
  const link = await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  assert.equal((await request(runner, link, head("/admin/api/overview"))).status, 200);
  // Another endpoint (other sockets), the same device.
  assert.notEqual(mesh.endpoint(), before);
  assert.equal(mesh.deviceId(), device);
  // Answered: the next try stays on it.
  const now = mesh.endpoint();
  link.close();
  await runner.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  assert.equal(mesh.endpoint(), now);
  await close(station, runner, mesh);
});

test("a_wake_while_a_try_goes_unanswered_opens_one_beside_it", { skip }, async () => {
  const wakes = new Wakes();
  const { mesh, station, runner, host } = await setup(undefined, new FakeHost(), wakes);
  station.unanswered(1);
  const id = station.id();
  const opening = runner.run(mesh.link(id, grants("ok", { n: 0 })));
  await sleep(50);
  // A person taps 重试 (client.wake, network) while a try that will never be answered is under way: another beside it
  // opens.
  wakes.wake(network(host));
  await within(5_000, opening, "opened beside it");
  const link = mesh.current(id)!;
  assert.equal((await request(runner, link, head("/admin/api/overview"))).status, 200);
  await close(station, runner, mesh);
});

// ── relays: iroh-relay in dev mode (plain HTTP) on this machine, as many as a test needs ──

import { spawn, type ChildProcess } from "node:child_process";
import { createServer as tcpServer, connect as tcpConnect } from "node:net";
import { existsSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const RELAY_BIN = process.env.STILLFAIL_RELAY_BIN ?? join(homedir(), ".config/ember-spike/relay/iroh-relay");
const noRelay = skip || (existsSync(RELAY_BIN) ? false : "no iroh-relay here (STILLFAIL_RELAY_BIN)");
/// A port free now: the system's choice, let go for the relay to take (another run of these tests at once on this
/// machine has relays too).
function freePort(): Promise<number> {
  return new Promise((resolve) => {
    const server = tcpServer();
    server.listen(0, "127.0.0.1", () => {
      const port = (server.address() as J).port;
      server.close(() => resolve(port));
    });
  });
}

/// A relay on localhost: its url, and a way to stop it.
async function relay(): Promise<[string, ChildProcess]> {
  const port = await freePort();
  const config = join(tmpdir(), `relay-${process.pid}-${port}.toml`);
  writeFileSync(config, `enable_relay = true\nhttp_bind_addr = "127.0.0.1:${port}"\nenable_metrics = false\nenable_quic_addr_discovery = false\n`);
  const child = spawn(RELAY_BIN, ["--dev", "--config-path", config], { stdio: "ignore" });
  const url = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 100; i++) {
    if (await fetch(url).then(() => true, () => false)) break;
    await sleep(50);
  }
  return [url, child];
}

/// The relay at `url` reached through a proxy that holds what goes through it, either way, `delay` ms (a delay line:
/// what comes meanwhile is held as long, behind it, as a far away relay is): its url for those who should find it slow.
/// The first `quick` relay connections through it (asking to upgrade to the relay's protocol) are not held.
async function slowed(url: string, delay: number, quick = 0): Promise<string> {
  const upstream = new URL(url);
  type Way = { held: number | null };
  const pump = (from: import("node:net").Socket, to: import("node:net").Socket, way: Way) => {
    const pass = (f: () => void) => (way.held === 0 ? f() : setTimeout(f, way.held!));
    from.on("data", (chunk: Buffer) => {
      if (way.held === null) way.held = quick > 0 && /^upgrade:/im.test(chunk.toString("latin1")) && quick-- > 0 ? 0 : delay;
      pass(() => to.write(chunk));
    });
    from.on("close", () => (way.held === null ? to.destroy() : pass(() => to.destroy())));
  };
  const server = tcpServer((down) => {
    const up = tcpConnect(Number(upstream.port), upstream.hostname);
    // The client speaks first: what it says first decides.
    const way: Way = { held: null };
    pump(down, up, way);
    pump(up, down, way);
    up.on("error", () => down.destroy());
    down.on("error", () => up.destroy());
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", () => r()));
  server.unref();
  return `http://127.0.0.1:${(server.address() as J).port}`;
}

const sameRelay = (a: string | null, b: string) => a !== null && new URL(a).host === new URL(b).host;

test("relay_probes_disable_ip_without_disabling_live_hole_punching", { skip: noRelay }, async () => {
  const [url, server] = await relay();
  const probe = await addon.bind({ secretKey: Buffer.alloc(32, 31), alpns: [], relayUrls: [url], discovery: false, relayOnly: true });
  assert.deepEqual(probe.sockets(), []);
  const live = await addon.bind({ secretKey: Buffer.alloc(32, 32), alpns: [], relayUrls: [url], discovery: false });
  assert.ok(live.sockets().length > 0);
  await probe.close();
  await live.close();
  server.kill();
});

test("a_direct_rtt_is_never_reported_as_a_relay_measurement", { skip }, async () => {
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

/// A phone's link to a station abroad went through the relay nearest the phone, the station's way there slow
/// (2026-10-01, bft: 11 s a round trip); measured, it moves to the relay that is quicker the whole way.
test("a_link_through_a_slow_relay_moves_to_the_quicker_one", { skip: noRelay }, async () => {
  const [[a, ra], [b, rb]] = await Promise.all([relay(), relay()]);
  // The station reaches a slowly (65 ms each way: a round trip through a at least 130 ms, QUIC's estimate never below
  // its least sample; well past what quicker() asks of a move, QUICKER_MS and QUICKER_SHARE, and each round trip of the
  // connecting and measuring through a is the test's time), b at once; the device reaches both at once. (Its keeper on a
  // (keep.rs), on the relay before the station dials it there, is the first relay connection through: not held, not
  // being what is measured.)
  const station = await Station.on(b, await slowed(a, 65, 1));
  const id = station.id();
  const host = new FakeHost();
  // Real timers until the last measuring (connecting through the slow relay takes its time), then quick ones.
  const times = new Map<number, number>();
  const e = env(host, new Wakes(), quickClock(times));
  // As it went: through a, the only relay the device was on then.
  const mesh = await e.runner.run(Mesh.make(e, [a]));
  const runner = e.runner;
  let link: Link | null = null;
  for (let i = 0; i < 40 && link === null; i++) {
    const tried = await runner.run(mesh.link(id, grants("ok", { n: 0 }))).catch(() => null);
    if (tried && (await request(runner, tried, head("/admin/api/overview")).then((r) => r.status === 200, () => false))) link = tried;
    else await sleep(250);
  }
  assert.ok(link, "reached through a");
  const asked = await Promise.all([1, 2, 3].map(() => request(runner, link!, head("/admin/api/overview"))));
  for (const reply of asked) assert.equal(reply.status, 200);
  const slow = link.net().rttMs!;
  assert.ok(sameRelay(link.via(), a), `${link.via()}`);
  assert.ok(slow > 125, `${slow}`);
  // Now on both: measured, it moves to b.
  (mesh.relays as string[]).push(b);
  await runner.run(mesh.remeasure(id));
  const moved = mesh.current(id)!;
  assert.notEqual(moved, link);
  assert.ok(sameRelay(moved.via(), b), `${moved.via()}`);
  assert.ok(moved.pinned !== null && sameRelay(moved.pinned, b));
  for (let i = 0; i < 5; i++) assert.equal((await request(runner, moved, head("/admin/api/overview"))).status, 200);
  const quick = moved.net().rttMs!;
  assert.ok(quick < slow / 2, `${quick} vs ${slow}`);
  // On b's own endpoint, under a key of its own: the station sees another device.
  const device = station.conns.filter((c: J) => !c.isClosed()).at(-1).remoteId();
  assert.notEqual(device, mesh.deviceId());
  const shown = mesh.measured(id)!;
  assert.equal(shown.measuring, false);
  assert.equal(shown.moved, new URL(b).hostname);
  assert.equal(shown.relays.length, 2);
  assert.ok(shown.relays.every(([, ms]) => ms !== null), JSON.stringify(shown));
  // Measured again, as a person asks: it stays, nothing is quicker than where it is. What is let go after it goes soon:
  // no link is opened from here on (the probes have their own timeout), so of the 10 s timers only RETIRE_MS is to come.
  const retired = 100;
  times.set(RETIRE_MS, retired);
  await runner.run(mesh.remeasure(id));
  assert.equal(mesh.measured(id)!.moved, null);
  assert.equal(mesh.current(id), moved);
  // The endpoint only measured on is let go (RETIRE_MS after measuring); b's, with the link on it, stays.
  await sleep(retired + 300);
  assert.equal((await request(runner, moved, head("/admin/api/overview"))).status, 200);
  await runner.run(mesh.close());
  runner.shutdown();
  // The station's close waits out the draining of its connection to its keeper on a (keep.rs), its close never
  // acknowledged (the keeper goes first) and the round trip there long: some 8 s, over by itself, not waited for.
  void station.close();
  ra.kill();
  rb.kill();
});

/// A relay far from the device and near the station is measured by its round trips, not by the probe's getting onto
/// it: QUIC's smoothed estimate began at the handshake, held while the probe's endpoint got onto the relay, so it
/// carried the device's distance to the relay several times over (2026-10-05: bft in Tokyo, the device in China, never
/// measured quickest through Cloudflare or Hong Kong).
test("a_relay_far_from_the_device_is_measured_by_its_round_trips", { skip: noRelay }, async () => {
  const [b, rb] = await relay();
  const station = await Station.bound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [b], discovery: false, relayOnly: true });
  await station.endpoint.online();
  const id = station.id();
  // The device reaches the relay 150 ms away each way (getting onto it as well), the station reaches it at once.
  const far = await slowed(b, 150);
  const e = env(new FakeHost(), new Wakes(), quickClock(new Map()));
  const mesh = await e.runner.run(Mesh.make(e, [far]));
  const runner = e.runner;
  let link: Link | null = null;
  for (let i = 0; i < 40 && link === null; i++) {
    const tried = await runner.run(mesh.link(id, grants("ok", { n: 0 }))).catch(() => null);
    if (tried && (await request(runner, tried, head("/admin/api/overview")).then((r) => r.status === 200, () => false))) link = tried;
    else await sleep(250);
  }
  assert.ok(link, "reached");
  await runner.run(mesh.remeasure(id));
  const [[, ms]] = mesh.measured(id)!.relays;
  // A round trip is 300 ms (a Mac measures 303–306); an acknowledgement may wait besides, and a busy machine adds its
  // own (Linux CI some 70 ms more, 2026-10-05): up to half more is allowed. QUIC's smoothed estimate, what this
  // replaced, carried the getting onto the relay several times over: 515–580 ms. (At 80 ms each way the two came too
  // close: the old way measured 264–296, under a bound with room for Linux.)
  assert.ok(ms !== null && ms >= 290 && ms < 450, `${ms}`);
  await runner.run(mesh.close());
  runner.shutdown();
  void station.close();
  rb.kill();
});

/// A workspace's own relay (cloud directory.ts setRelays): its station is on that relay alone, the device's endpoint on
/// still.fail's; told the workspace's relays, the device reaches the station through it, and measures it.
test("reaches_a_station_through_its_workspaces_own_relay", { skip: noRelay }, async () => {
  const [[a, ra], [b, rb]] = await Promise.all([relay(), relay()]);
  const station = await Station.bound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [b], discovery: false, relayOnly: true });
  await station.endpoint.online();
  const id = station.id();
  const e = env(new FakeHost(), new Wakes());
  const mesh = await e.runner.run(Mesh.make(e, [a]));
  const runner = e.runner;
  let link: Link | null = null;
  for (let i = 0; i < 40 && link === null; i++) {
    const tried = await runner.run(mesh.link(id, grants("ok", { n: 0 }), [b])).catch(() => null);
    if (tried && (await request(runner, tried, head("/admin/api/overview")).then((r) => r.status === 200, () => false))) link = tried;
    else await sleep(250);
  }
  assert.ok(link, "reached through the workspace's relay");
  assert.ok(sameRelay(link.via(), b), `${link.via()}`);
  assert.deepEqual(mesh.relaysFor(id), [a, b]);
  // Its endpoint stays on still.fail's relay alone; a link asked for again without saying keeps the station's relays.
  assert.deepEqual(mesh.relays, [a]);
  assert.equal(await runner.run(mesh.link(id, grants("ok", { n: 0 }))), link);
  assert.deepEqual(mesh.relaysFor(id), [a, b]);
  await runner.run(mesh.close());
  runner.shutdown();
  void station.close();
  ra.kill();
  rb.kill();
});

// ── adb.rs ──

import { createServer } from "node:net";
import { Adb } from "../src/adb.ts";
import { parseAdb, MAX_MINUTES } from "../src/adb-parse.ts";
import { Store } from "../src/store.ts";
import { nodeTcp } from "../src/hosts/node.ts";

/// adbd: says back what it hears.
function adbd(): Promise<number> {
  return new Promise((resolve) => {
    const server = createServer((socket) => socket.pipe(socket));
    server.listen(0, "127.0.0.1", () => resolve((server.address() as J).port));
    server.unref();
  });
}

test("offers_the_phone_and_tunnels_what_the_station_opens_to_its_adbd", { skip }, async () => {
  const port = await adbd();
  // A station that takes a credential, then an offer: answers it, opens a tunnel and says "hello" through it.
  const key = new Uint8Array(32);
  crypto.getRandomValues(key);
  const endpoint = await addon.bind({ secretKey: Buffer.from(key), alpns: [Buffer.from(ALPN)], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const seen: { offer?: J; echoed?: string; stopped?: boolean } = {};
  void (async () => {
    const conn = await endpoint.accept();
    const control = await conn.acceptBi();
    const c1 = { bytes: Buffer.alloc(0) };
    await Station.readLine(control, c1);
    await control.write(Buffer.from(`${JSON.stringify({ ok: true, station: "测试" })}\n`));
    const offer = await conn.acceptBi();
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
  const host = new FakeHost();
  (host as J).tcp = nodeTcp;
  const e = env(host);
  const mesh = await e.runner.run(Mesh.make(e, []));
  mesh.addAddr({ id: endpoint.id(), ips: [endpoint.sockets().find((a: string) => a.startsWith("127.0.0.1"))] });
  const store = new Store(host, e.runner);
  const adb = new Adb({ host, runner: e.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential), relays: () => [] });
  const station = `ws/${endpoint.id()}`;
  await e.runner.run(adb.run({ kind: "share", offer: { station, connect: port, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 } }));
  for (let i = 0; i < 200 && (seen.echoed === undefined || adb.value().tunnels !== 1 || adb.value().adb !== "connected"); i++) await sleep(20);
  const head = seen.offer;
  assert.equal(head.path, "/admin/api/adb");
  assert.equal(head.adb.phone.length, 64);
  delete head.adb.phone;
  assert.deepEqual(head.adb, { op: "share", device: "Pixel 8", android: "14", package: "fail.still.android", adbd: true, pair: false });
  assert.equal(seen.echoed, "hello");
  const value = adb.value();
  assert.deepEqual([value.sharing, value.station, value.phase, value.serial], [true, station, "offered", "127.0.0.1:37001"]);
  await e.runner.run(adb.run({ kind: "stop" }));
  for (let i = 0; i < 250 && !seen.stopped; i++) await sleep(20);
  assert.ok(seen.stopped, "the station sees the offer stop");
  const after = adb.value();
  assert.deepEqual([after.sharing, after.phase], [false, "off"]);
  await e.runner.run(mesh.close());
  await endpoint.close();
  e.runner.shutdown();
});

test("reads_its_calls", () => {
  const share = parseAdb("adb.share", { station: "ws/st", connect: 41234, minutes: 10_000 });
  assert.deepEqual(share, { kind: "share", offer: { station: "ws/st", connect: 41234, pair: null, device: "", android: "", package: "", minutes: MAX_MINUTES } });
  assert.throws(() => parseAdb("adb.share", {}));
  assert.deepEqual(parseAdb("adb.pair", { code: "123456" }), { kind: "pair", code: "123456" });
  assert.equal(parseAdb("job.stop", {}), null);
});

suite("mesh", { concurrency: true }, () => {
  for (const [name, options, body] of tests) register(name, options, body);
});
