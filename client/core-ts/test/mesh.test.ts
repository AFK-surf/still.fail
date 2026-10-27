// The Rust core's mesh.rs tests, ported, on a simulated network (sim-iroh.ts): a station and the client's mesh as they
// talk over iroh, each relay's lines as a test sets them, all on the test's clock. Nothing here waits for real time or
// depends on how busy the machine is: a run is the same every time its seed is (what varies: jitter, how writes are
// cut). Each test runs on the same seeds (sim-seeds.ts); a failure says its seed and network, and SIM_SEED=<seed> runs that
// one again.
// The native addon itself, the few things only it can show, at the end ("over the addon"): what it answers, never how
// long it takes.
import assert from "node:assert/strict";
import { createSocket } from "node:dgram";
import { suite, test as register, type TestOptions } from "node:test";
import { Effect, Fiber, Queue } from "effect";
import type { Credential } from "../src/cloud.ts";
import { CoreError } from "../src/error.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import type { Iroh } from "../src/iroh.ts";
import { ALPN, clearlyBetter, cost, DEVICE_KEY, DIRECT_HOLD_MAX_MS, EXPLORE_MS, FORMER_ALPN, HEDGE_FLOOR_MS, KEEP_WAYS, LAN, Mesh, MeshWire, PING_TIMEOUT_MS, PROBE_MS, REDIAL_MAIN_MS, RENEW_MS, RETIRE_MS, SPEED_FRESH_MS, SPEED_MIN_BYTES, TICK_MS, type CredentialSource, type Link } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { StationAddr } from "../src/station/addr.ts";
import { readAll, type RequestHead } from "../src/station/wire.ts";
import { FrameReader, ackFrame } from "../src/screen-frames.ts";
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

sim("tells_how_far_a_body_has_gone_as_it_goes", async (s) => {
  const { mesh, station } = await setup(s);
  const link = await s.run(mesh.link(station.id(), grants("ok", { n: 0 })));
  const body = new Uint8Array(200 * 1024).fill(97);
  const wrote: number[] = [];
  const reply = await s.run(link.request(head("/admin/api/sessions"), body, (n) => wrote.push(n)));
  assert.deepEqual(wrote, [65536, 131072, 196608, 204800]);
  // All of it went, in its order.
  assert.equal(text(await s.run(readAll(reply.body))).split("|")[1], "a".repeat(200 * 1024));
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

/// A screen view over the mesh (docs/remote-screens.md): its head line carries `screen`, its frames come whole however
/// the network cuts them, and the station sends only as the client acknowledges (never more than 2 ahead).
sim("a_screen_view_brings_frames_as_they_are_acknowledged", async (s) => {
  const { mesh, station } = await setup(s);
  const big = (n: number, b: number) => new Uint8Array(n).map((_, i) => (i * 31 + b) & 255);
  station.screenFrames = [
    { key: true, ts: 0, data: big(300_000, 1) },
    { key: false, ts: 33_333, data: big(4_000, 2) },
    { key: false, ts: 66_666, data: big(9, 3) },
    { key: true, ts: 100_000, data: big(120_000, 4) },
    { key: false, ts: 133_333, data: big(70_000, 5) },
  ];
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${station.id()}`);
  const ask = { maxWidth: 1280, maxHeight: 720, codecs: ["jpeg"], control: false };
  const seen = await s.run(
    Effect.scoped(
      Effect.gen(function* () {
        const view = yield* wire.screen!(addr, { method: "POST", path: "/admin/api/screens/desktop/view", headers: [] }, ask);
        assert.equal(view.reply.status, 200);
        const reader = new FrameReader();
        const frames: J[] = [];
        for (;;) {
          const chunk = yield* view.reply.body.take;
          if (chunk === null) return frames;
          reader.push(chunk);
          for (let f = reader.next(); f !== null; f = reader.next()) {
            frames.push(f);
            if ("video" in f) yield* view.send.write(ackFrame(f.video.ts));
          }
        }
      }),
    ),
  );
  assert.deepEqual(station.views.map((v) => v.head), [{ method: "POST", path: "/admin/api/screens/desktop/view", headers: {}, screen: ask }]);
  assert.deepEqual(seen[0], { config: { codec: "jpeg", width: 640, height: 480, description: null } });
  const videos = seen.filter((f: J) => "video" in f).map((f: J) => f.video);
  assert.deepEqual(videos.map((v: J) => [v.key, v.ts, v.data.length]), station.screenFrames.map((f) => [f.key, f.ts, f.data.length]));
  for (const [i, v] of videos.entries()) assert.deepEqual(v.data, station.screenFrames[i]!.data);
  assert.deepEqual(seen.at(-1), { state: { ended: "done" } });
  assert.deepEqual(station.views[0]!.got, station.screenFrames.map((f) => ({ ack: f.ts })));
  assert.ok(station.views[0]!.mostUnacked <= 2);
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

/// docs/multi-workspace.md: a station in two workspaces is reached in each on a link of its own (one station id, two
/// addresses), opened and renewed with that workspace's credential; one dropped leaves the other.
sim("a_station_in_two_workspaces_has_a_link_in_each_with_its_own_credential", async (s) => {
  const { mesh, station } = await setup(s);
  const [a, b] = [`wa/${station.id()}`, `wb/${station.id()}`];
  const [countA, countB] = [{ n: 0 }, { n: 0 }];
  const linkA = await s.run(mesh.link(a, grants("ok-a", countA)));
  const linkB = await s.run(mesh.link(b, grants("ok-b", countB)));
  assert.notEqual(linkA, linkB);
  // Handed out as its credential is sent: the station reads it a moment later.
  await s.until(() => station.firsts.length === 2);
  assert.deepEqual(station.firsts, ["ok-a-1", "ok-b-1"]);
  // Each asked again keeps its own.
  assert.equal(await s.run(mesh.link(a, grants("ok-a", countA))), linkA);
  assert.equal(await s.run(mesh.link(b, grants("ok-b", countB))), linkB);
  assert.equal(station.conns.length, 2);
  // Each renewed with its own workspace's.
  await s.time.pass(RENEW_MS + 1000);
  assert.deepEqual([linkA.credential, linkB.credential], ["ok-a-2", "ok-b-2"]);
  // One dropped: the other stays, and still answers.
  mesh.dropLink(a);
  await s.until(() => linkA.closed() !== null);
  assert.equal(mesh.current(a), null);
  assert.equal(mesh.current(b), linkB);
  assert.equal(linkB.closed(), null);
  assert.equal((await request(s, linkB, head("/admin/api/overview"))).status, 200);
  // Asked again: opened anew with its own.
  const again = await s.run(mesh.link(a, grants("ok-a", countA)));
  assert.notEqual(again, linkA);
  await s.until(() => station.firsts.length === 3);
  assert.equal(station.firsts.at(-1), "ok-a-3");
  assert.equal(mesh.current(b), linkB);
  await close(s, station, mesh);
});

/// Through the wire, as the core asks: the credential refused in one workspace refuses the station there alone; the
/// next asking there opens its link anew with a fresh one, and a reset there drops that link alone.
sim("a_refusal_or_reset_in_one_workspace_leaves_the_stations_link_in_another", async (s) => {
  const { mesh, station } = await setup(s);
  const status = new Status(s.host, s.runner);
  const said = new Map([["wa", "ok-a"], ["wb", "bad-b"]]);
  const counts = new Map([["wa", { n: 0 }], ["wb", { n: 0 }]]);
  const credentials = (ws: string): CredentialSource => (device, fresh) => grants(said.get(ws)!, counts.get(ws)!)(device, fresh);
  const wire = new MeshWire({ mesh: () => Effect.succeed(mesh), meshNow: () => mesh, credentials, relays: () => [], status: () => status });
  const [a, b] = [new StationAddr("wa", station.id()), new StationAddr("wb", station.id())];
  const get: RequestHead = { method: "GET", path: "/admin/api/overview", headers: [] };
  const ask = (at: StationAddr) => s.run(Effect.scoped(Effect.flatMap(wire.request(at, get, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(await ask(a), 200);
  const linkA = mesh.current(a.toString())!;
  const refused = await ask(b).then(
    () => null,
    (e) => e as CoreError,
  );
  assert.equal(refused?.code, "credential_refused", JSON.stringify(refused));
  assert.equal(mesh.current(a.toString()), linkA);
  assert.equal(linkA.closed(), null);
  // Its credential good again: b's link opened anew with a fresh one, a's untouched.
  said.set("wb", "ok-b");
  assert.equal(await ask(b), 200);
  const linkB = mesh.current(b.toString())!;
  assert.notEqual(linkB, linkA);
  assert.deepEqual(station.firsts, ["ok-a-1", "bad-b-1", "ok-b-2"]);
  // Reset in b: a's link stays and answers.
  wire.reset(b);
  await s.until(() => linkB.closed() !== null);
  assert.equal(mesh.current(b.toString()), null);
  assert.equal(await ask(a), 200);
  assert.equal(mesh.current(a.toString()), linkA);
  assert.equal(linkA.closed(), null);
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

/// The side run, seed 705982920 (2026-10-15): a link gone quiet was replaced, and the new one lost within RETIRE_MS; the
/// read asked then went back on the old, which was closed under it as it retired.
sim("a_link_lost_soon_after_it_replaced_one_gone_quiet_is_not_traded_for_that_one", async (s) => {
  const { mesh, station } = await setup(s);
  // The mesh asked by the station's address, as the wire asks it.
  const id = `w/${station.id()}`;
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(id);
  const get: RequestHead = { method: "GET", path: "/admin/api/overview", headers: [] };
  const ask = () => s.runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, get, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  const old = await s.run(mesh.link(id, grants("ok", { n: 0 })));
  await request(s, old, head("/admin/api/overview"));
  station.deadBelow = station.conns.length;
  const replaced = s.runner.run(mesh.replaced(id, old));
  s.wakes.wake(network(s.host));
  await s.settle(replaced);
  const next = mesh.current(id)!;
  // The old one answers again (it was only slow to): a way, for all the mesh knows.
  station.deadBelow = 0;
  // Lost as a read is asked on it, near the end of RETIRE_MS.
  await s.time.pass(RETIRE_MS - 200);
  station.conns.at(-1)!.close(0, "restart");
  assert.equal(await s.settle(ask()), 200);
  assert.ok(next.closed() !== null);
  assert.notEqual(mesh.current(id), old);
  await close(s, station, mesh);
});

/// The side run, seed 143365259 (2026-10-17): the station dropped both its connections to the device at once (a restart);
/// the read asked then failed on its link, was asked again on the other way, which was gone too though the device was
/// not told so yet, and failed. It is asked again until a link holds.
sim("a_read_asked_as_its_station_drops_every_connection_is_answered", async (s) => {
  const relays = [s.relay("https://a.relay.test/", { device: { ms: 20 }, station: { ms: 20 } }), s.relay("https://b.relay.test/", { device: { ms: 50 }, station: { ms: 120 } })];
  const { station, mesh, id } = await onRelays(s, relays);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(`w/${id}`);
  const get: RequestHead = { method: "GET", path: "/admin/api/overview", headers: [] };
  const ask = () => s.runner.run(Effect.scoped(Effect.flatMap(wire.request(addr, get, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(await s.settle(ask()), 200);
  await s.until(() => mesh.ways(addr.toString()).length >= 2);
  for (const c of station.conns.filter((c) => !c.isClosed())) c.close(0, "restart");
  assert.equal(await s.settle(ask()), 200);
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
  assert.equal(error?.message, "无法连接此 station：无响应");
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

sim("its_pings_say_when_no_way_answers_and_when_one_answers_again", async (s) => {
  const a = s.relay("https://a.relay.test/", { device: { ms: 20 }, station: { ms: 20 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 30 }, station: { ms: 30 } });
  const { station, mesh, id } = await onRelays(s, [a, b]);
  const link = await s.run(mesh.link(id, grants("ok", { n: 0 })));
  await request(s, link, head("/admin/api/overview"));
  await s.time.pass(2 * TICK_MS);
  assert.equal(mesh.healthy(id), true);
  // Its way answers nothing more: once it missed DEAD_PINGS (3) in a row, and not before.
  station.deadBelow = station.conns.length;
  const went = s.time.now();
  const lost = await s.settle(s.runner.run(mesh.healthChange(id, true)));
  assert.equal(lost, false);
  const after = s.time.now() - went;
  assert.ok(after >= 2 * TICK_MS && after <= 4 * TICK_MS + PING_TIMEOUT_MS, `${after}`);
  // It answers again: told at the next tick.
  station.deadBelow = 0;
  const back = await s.settle(s.runner.run(mesh.healthChange(id, false)));
  assert.equal(back, true);
  await close(s, station, mesh);
});

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
  const { station, mesh, id: bare } = await onRelays(s, [a, b, c]);
  const id = `w/${bare}`;
  // A read as the core asks one, whole: how long it takes.
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(id);
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

/// A run whose mesh came up on the relays kept from the last, from a cloud that had the entries among them: its first
/// `/v1/me` tells them apart (`retune`). The endpoint is bound anew on the relays alone, and from then on no key is on a
/// relay twice; the station is reached through the entry, its own endpoint's.
sim("told_the_entries_apart_the_mesh_binds_anew_on_the_relays_alone", async (s) => {
  const a = s.relay("https://a.relay.test/", { device: { ms: 5 }, station: { ms: 70, loss: 0.35 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 60 }, station: { ms: 30 } });
  const entry = s.net.entry("https://a.relay.test:8443/", b, { device: { ms: 5 }, station: { ms: 40 } });
  const station = await s.stationOn(b, a);
  const id = station.id();
  const mesh = await s.run(Mesh.make(env(s), [a, b, entry]));
  assert.notDeepEqual(s.net.twice(true), [], "kept from before, the entry among the relays: on b twice");
  const before = mesh.endpoint();
  mesh.retune([a, b], [entry]);
  await s.until(() => mesh.endpoint() !== before);
  assert.deepEqual([mesh.relays, mesh.entries], [[a, b], [entry]]);
  await reach(s, mesh, id);
  await s.time.pass(5 * 60_000);
  assert.equal(via(mesh, id), entry, JSON.stringify(mesh.measured(id)));
  assert.deepEqual(s.net.twice(true), []);
  // Told the same again: nothing changes.
  const now = mesh.endpoint();
  mesh.retune([a, b], [entry]);
  await s.time.pass(TICK_MS);
  assert.equal(mesh.endpoint(), now);
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
  const { station, mesh, id: bare } = await onRelays(s, [a, b]);
  const id = `w/${bare}`;
  await reach(s, mesh, id);
  await s.time.pass(60_000);
  assert.ok(sameRelay(via(mesh, id), a), `${via(mesh, id)}`);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(id);
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

/// A read let go of while the station is slow to answer it (a player gone elsewhere, its view closed): its stream goes
/// with it, and the station stops sending what no one would read.
sim("a_read_let_go_of_before_its_answer_stops_the_station_sending_it", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 10 } });
  const { station, mesh, id: bare } = await onRelays(s, [a]);
  const id = `w/${bare}`;
  await reach(s, mesh, id);
  const wire = wireOf(s, mesh);
  station.lateMs = 5_000;
  const read = Effect.scoped(Effect.flatMap(wire.request(StationAddr.parse(id), { method: "GET", path: "/admin/api/part", headers: [] }, new Uint8Array()), (r) => readAll(r.body)));
  await s.run(
    Effect.gen(function* () {
      const reading = yield* Effect.forkChild(read);
      yield* Effect.sleep(1_000);
      yield* Fiber.interrupt(reading);
    }),
  );
  await s.time.pass(10_000);
  assert.deepEqual(station.letGo, ["/admin/api/part"]);
  await close(s, station, mesh);
});

/// A read asked on another way as well, the station slow to answer it on both: once one answer is taken, the other
/// attempt is let go of, not left to bring its answer to no one.
sim("a_read_asked_on_two_ways_lets_go_of_the_one_not_taken", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 10 } });
  const b = s.relay("https://b.relay.test/", { station: { ms: 40 } });
  const { station, mesh, id: bare } = await onRelays(s, [a, b]);
  const id = `w/${bare}`;
  await reach(s, mesh, id);
  await s.time.pass(60_000);
  const wire = wireOf(s, mesh);
  station.lateMs = 3_000;
  const status = await s.run(Effect.scoped(Effect.flatMap(wire.request(StationAddr.parse(id), { method: "GET", path: "/admin/api/part", headers: [] }, new Uint8Array()), (r) => Effect.map(readAll(r.body), () => r.status))));
  assert.equal(status, 200);
  assert.equal(station.served.filter((h) => h.path === "/admin/api/part").length, 2, "asked on both ways");
  await s.time.pass(10_000);
  assert.deepEqual(station.letGo, ["/admin/api/part"]);
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
  const { station, mesh, id: bare } = await onRelays(s, [b, a]);
  const id = `w/${bare}`;
  await reach(s, mesh, id);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(id);
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

/// b brings replies fast, then slowly (its line to the device down to 256 KiB/s: more crowded, a hop further). Past
/// SPEED_FRESH_MS the slower replies say how fast it is now, and the requests leave it for a, not held there for hours
/// by how fast it once was. And a network change: what was seen is let go, to be found out again from there.
sim("a_way_grown_slower_is_judged_by_how_it_brings_replies_now_and_a_new_network_by_its_own", async (s) => {
  const a = s.relay("https://a.relay.test/", { station: { ms: 100 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 60 } });
  const { station, mesh, id: bare } = await onRelays(s, [b, a]);
  const id = `w/${bare}`;
  await reach(s, mesh, id);
  const wire = wireOf(s, mesh);
  const addr = StationAddr.parse(id);
  const big = () => s.run(Effect.scoped(Effect.flatMap(wire.request(addr, { method: "GET", path: "/admin/api/big", headers: [] }, new Uint8Array()), (r) => readAll(r.body))));
  await s.until(() => sameRelay(via(mesh, id), b), 5 * 60_000);
  await big();
  const fast = mesh.speed(id, b);
  assert.ok(fast !== null, "how fast b is, seen");
  await s.time.pass(SPEED_FRESH_MS);
  s.relay(b, { device: { ms: 60, bps: 256 * 1024 } });
  await big();
  const now = mesh.speed(id, b);
  assert.ok(now !== null && now < fast / 2, `b at ${now} B/s now, at ${fast} before`);
  await s.until(() => sameRelay(via(mesh, id), a), 5 * 60_000);
  // Elsewhere now: nothing seen on the last network counts.
  s.wakes.wake(network(s.host));
  await s.time.pass(TICK_MS);
  assert.equal(mesh.speed(id, b), null);
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

/// A station on the phone's LAN, at home on a (the device's own relay, far) and held on b (near): the phone's link to it
/// on b's own endpoint comes through first, the main endpoint's through a after it and direct once iroh punches a hole.
async function onLan(s: Sim, quietAfterMs?: number) {
  s.net.direct = { ms: 3 };
  s.net.lan = { punchMs: 500, quietAfterMs };
  const a = s.relay("https://a.relay.test/", { device: { ms: 40 }, station: { ms: 40 } });
  const b = s.relay("https://b.relay.test/", { device: { ms: 10 }, station: { ms: 10 } });
  const station = await s.stationBound({ alpns: [Buffer.from(ALPN), Buffer.from(FORMER_ALPN)], relayUrls: [a], discovery: false, bindAddr: "127.0.0.1:0" });
  await s.settle(station.endpoint.online());
  station.endpoint.keep([b]);
  const e = env(s);
  const mesh = await s.run(Mesh.make(e, [a, b]));
  return { station, mesh, id: station.id(), tracer: e.tracer };
}

/// The spans `tracer` sends from now on, by name, each with its attributes.
function spansOf(tracer: Tracer): { name: string; at: Record<string, unknown> }[] {
  const seen: { name: string; at: Record<string, unknown> }[] = [];
  tracer.setExport((body) =>
    Effect.sync(() => {
      for (const r of JSON.parse(Buffer.from(body).toString()).resourceSpans)
        for (const sc of r.scopeSpans)
          for (const sp of sc.spans) seen.push({ name: sp.name, at: Object.fromEntries(sp.attributes.map((a: { key: string; value: Record<string, unknown> }) => [a.key, Object.values(a.value)[0]])) });
    }),
  );
  return seen;
}

const direct = (mesh: Mesh, id: string) => mesh.current(id)?.path() === "direct";

/// 2026-10-17: a phone on its station's LAN went on through a relay most of the time. Its link came through first on a
/// relay's own endpoint, and the main endpoint's, gone direct beside it, waited BETTER_TICKS and MIN_STAY_MS to be
/// taken, minutes on a phone opened for a while; gone quiet as the phone slept, it waited EXPLORE_MS to be dialled
/// again. The requests go direct within seconds, from the start and as the phone comes back.
sim("a_phone_on_its_stations_lan_goes_direct_within_seconds", async (s) => {
  const { station, mesh, id } = await onLan(s);
  const started = s.time.now();
  await reach(s, mesh, id);
  await s.until(() => direct(mesh, id), 60_000);
  assert.ok(s.time.now() - started <= 3 * TICK_MS, `direct ${s.time.now() - started} ms after the first link`);
  // Its ways as a span says them: the one chosen, at the station's address.
  assert.match(mesh.current(id)!.paths(), /^\*127\.0\.0\.1:\d+ \d+ms \d+\/\d+$/);
  // Back from sleep: every connection it had is gone at the station.
  station.deadBelow = station.conns.length;
  s.wakes.wake(network(s.host));
  await s.until(() => !direct(mesh, id), 60_000);
  const woke = s.time.now();
  await s.until(() => direct(mesh, id), 5 * 60_000);
  assert.ok(s.time.now() - woke <= 3 * TICK_MS, `direct again ${s.time.now() - woke} ms after the phone came back`);
  // And stays so.
  const moves = mesh.moves(id);
  await s.time.pass(30 * 60_000);
  assert.ok(direct(mesh, id));
  assert.equal(mesh.moves(id), moves);
  await close(s, station, mesh);
});

/// The direct link lost alone (the requests on to a relay meanwhile): the main endpoint dials the station again well
/// before EXPLORE_MS, and the requests go direct again.
sim("a_direct_link_lost_is_dialled_again_soon", async (s) => {
  const { station, mesh, id } = await onLan(s);
  await reach(s, mesh, id);
  await s.until(() => direct(mesh, id), 60_000);
  await s.time.pass(60_000);
  const lost = s.time.now();
  for (const c of station.conns) if (c.remoteId() === mesh.deviceId() && c.reason === null) c.close(0, "restart");
  await s.until(() => !direct(mesh, id), 60_000);
  await s.until(() => direct(mesh, id), EXPLORE_MS);
  assert.ok(s.time.now() - lost <= REDIAL_MAIN_MS + 3 * TICK_MS, `direct again ${s.time.now() - lost} ms after it was lost`);
  await close(s, station, mesh);
});

/// 2026-10-17, studio and a phone on its LAN: the path iroh punched went quiet seconds after it opened, and the requests
/// on it waited out iroh's 15 s each time before going back through a relay. The station says its LAN addresses with its
/// answer to the credential; the device dials them on an endpoint of its own, by address alone, and the requests go
/// there and stay.
sim("a_station_on_the_lan_is_dialled_at_its_lan_addresses_and_the_requests_stay_there", async (s) => {
  const { station, mesh, id } = await onLan(s, 5_000);
  station.lan = station.addr().ips;
  await reach(s, mesh, id);
  await s.until(() => mesh.current(id)?.pinned === LAN, 60_000);
  assert.ok(direct(mesh, id));
  const moves = mesh.moves(id);
  await s.time.pass(10 * 60_000);
  assert.equal(mesh.current(id)?.pinned, LAN, JSON.stringify(mesh.measured(id)));
  assert.ok(mesh.moves(id) - moves <= 1, `moved ${mesh.moves(id) - moves} times in ten minutes`);
  assert.equal((await request(s, mesh.current(id)!, head("/admin/api/overview"))).status, 200);
  await close(s, station, mesh);
});

/// 2026-10-18, a phone on studio's LAN: each way direct went quiet within a minute of the requests moving to it, and
/// they moved to the next one dialled, and back to a relay once it went quiet too, every minute or so. Lost soon after
/// twice in a row, ways direct are held off a while, longer each time; once one stays, they are taken again.
sim("ways_direct_that_keep_going_quiet_are_held_off_a_while", async (s) => {
  const { station, mesh, id } = await onLan(s);
  station.lan = station.addr().ips;
  await reach(s, mesh, id);
  await s.until(() => mesh.current(id)?.path() === "direct", 60_000);
  // Each way direct goes quiet 20 s after the requests move to it, for good.
  let flaky = true;
  let on: Link | null = null;
  let since = s.time.now();
  let quieted = 0;
  const watch = () => {
    const cur = mesh.current(id);
    if (cur !== on) [on, since] = [cur, s.time.now()];
    if (!flaky || cur?.path() !== "direct" || s.time.now() - since < 20_000) return;
    for (const c of station.conns) {
      if (c.reason !== null || c.way.relay !== null || c.way.silentUntil === Infinity) continue;
      c.way.silentUntil = c.peer.way.silentUntil = Infinity;
      quieted++;
    }
  };
  const moves = mesh.moves(id);
  for (let t = 0; t < 30 * 60_000; t += TICK_MS) {
    watch();
    await s.time.pass(TICK_MS);
  }
  // Moved to a way direct and off it again a few times in half an hour, not every minute.
  assert.ok(quieted >= 3, `${quieted} ways quieted`);
  assert.ok(mesh.moves(id) - moves <= 16, `moved ${mesh.moves(id) - moves} times in half an hour, ${quieted} ways quieted`);
  // The LAN well again: the requests go direct once the hold is over, and stay.
  flaky = false;
  await s.until(() => mesh.current(id)?.path() === "direct", DIRECT_HOLD_MAX_MS + 2 * 60_000);
  await s.time.pass(10 * 60_000);
  assert.equal(mesh.current(id)?.path(), "direct");
  await close(s, station, mesh);
});

/// On its station's LAN, the requests keep off the main endpoint: the LAN way is enough, and the main endpoint's link
/// would only punch one more path to the station. It is not dialled again every REDIAL_MAIN_MS: its LAN way lost, they
/// go to a relay's own way until the LAN endpoint's is dialled again.
sim("on_its_stations_lan_the_requests_keep_off_the_main_endpoint", async (s) => {
  const { station, mesh, id } = await onLan(s);
  station.lan = station.addr().ips;
  await reach(s, mesh, id);
  await s.until(() => mesh.current(id)?.pinned === LAN, 60_000);
  await s.time.pass(30_000);
  const on: string[] = [];
  let mains = 0;
  const note = () => {
    const cur = mesh.current(id);
    on.push(cur === null ? "none" : cur.pinned === LAN ? "lan" : cur.pinned === null ? "main" : "relay");
    if (mesh.ways(id).some((w) => w.link.pinned === null)) mains++;
  };
  for (let t = 0; t < 2 * 60_000; t += TICK_MS) {
    note();
    await s.time.pass(TICK_MS);
  }
  // The LAN endpoint's link goes quiet for good.
  for (const c of station.conns) if (c.reason === null && c.peer.endpoint.relays.length === 0) c.way.silentUntil = c.peer.way.silentUntil = Infinity;
  for (let t = 0; t < 5 * 60_000; t += TICK_MS) {
    note();
    await s.time.pass(TICK_MS);
  }
  assert.ok(!on.includes("main"), on.join(" "));
  assert.ok(on.includes("relay"), on.join(" "));
  assert.equal(on.at(-1), "lan", on.join(" "));
  assert.equal(mains, 0, `a way on the main endpoint open ${mains} ticks of ${on.length}`);
  assert.equal((await request(s, mesh.current(id)!, head("/admin/api/overview"))).status, 200);
  await close(s, station, mesh);
});

/// 2026-10-17: a phone's punched paths went quiet seconds after they opened, which no Mac on the LAN did again. A
/// `mesh.path` span says each change of a way's paths and its first ping missed, with its paths then and a tick before.
sim("a_ways_paths_changing_and_going_quiet_are_told_in_spans", async (s) => {
  const { station, mesh, id, tracer } = await onLan(s, 5_000);
  const spans = spansOf(tracer);
  await reach(s, mesh, id);
  await s.time.pass(2 * 60_000);
  tracer.flush();
  await s.time.pass(TICK_MS);
  const told = spans.filter((x) => x.name === "mesh.path");
  const direct = /^\*127\.0\.0\.1:\d+ \d+ms \d+\/\d+$/;
  const punched = told.find((x) => x.at["stillfail.why"] === "paths" && direct.test(String(x.at["stillfail.paths"])));
  assert.ok(punched, JSON.stringify(told));
  assert.equal(punched.at["stillfail.way"], "direct");
  // Gone quiet: its first ping missed, said with the punched path it was missed on; then back through the relay.
  assert.ok(told.some((x) => x.at["stillfail.why"] === "missed" && direct.test(String(x.at["stillfail.paths"]))), JSON.stringify(told));
  assert.ok(told.some((x) => x.at["stillfail.why"] === "paths" && direct.test(String(x.at["stillfail.before.paths"])) && /^\*a\.relay\.test /.test(String(x.at["stillfail.paths"]))), JSON.stringify(told));
  // Not every tick: a few changes in two minutes.
  assert.ok(told.length < 20, `${told.length} spans`);
  await close(s, station, mesh);
});

/// Off the station's LAN, its LAN addresses lead nowhere: tried once, not again every while; tried again once the
/// network changes.
sim("off_the_stations_lan_its_lan_addresses_are_tried_once_and_again_as_the_network_changes", async (s) => {
  const { station, mesh, id } = await onLan(s);
  s.net.away = true;
  station.lan = station.addr().ips;
  await reach(s, mesh, id);
  await s.time.pass(60_000);
  const lanTries = () => s.net.tries.filter((t) => t.ips && t.to === id).length;
  assert.equal(lanTries(), 1);
  await s.time.pass(10 * 60_000);
  assert.equal(lanTries(), 1);
  assert.notEqual(mesh.current(id)?.pinned, LAN);
  s.wakes.wake(network(s.host));
  await s.time.pass(60_000);
  assert.equal(lanTries(), 2);
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
  const adb = new Adb({ host: s.host, runner: s.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential), relays: () => [], lends: () => true });
  const station = `ws/${endpoint.id()}`;
  await s.run(adb.run({ kind: "share", offer: { station, connect: 5555, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 } }));
  await s.until(() => seen.echoed !== undefined && adb.value().tunnels === 1 && adb.value().adb === "connected");
  const offered = seen.offer;
  assert.equal(offered.path, "/admin/api/adb");
  assert.equal(offered.adb.phone.length, 64);
  delete offered.adb.phone;
  assert.deepEqual(offered.adb, { op: "share", device: "Pixel 8", android: "14", package: "fail.still.android", adbd: true, pair: false, connect: 5555 });
  assert.equal(seen.echoed, "hello");
  const value = adb.value();
  assert.deepEqual([value.sharing, value.station, value.phase, value.serial], [true, station, "offered", "127.0.0.1:37001"]);
  // A link to the station's 共享调试 says so, with the minutes left; one to another station's, that it is lent elsewhere.
  const card = adb.card(station);
  assert.deepEqual({ ...card, line: card.line.replace(/\d+/, "N") }, { title: "共享调试", line: "共享中 · 剩余 N 分钟", sharing: true, lendable: true });
  assert.deepEqual(adb.card("ws/other"), { title: "共享调试", line: "正在共享给另一台 station", sharing: false, lendable: true });
  await s.run(adb.run({ kind: "stop" }));
  await s.until(() => seen.stopped === true);
  assert.ok(seen.stopped, "the station sees the offer stop");
  const after = adb.value();
  assert.deepEqual([after.sharing, after.phase], [false, "off"]);
  assert.deepEqual(adb.card(station), { title: "共享调试", line: "未共享", sharing: false, lendable: true });
  await s.run(mesh.close());
  await s.settle(endpoint.close());
});

/// 2026-10-27: the app lends at the tap and its service offers the same once Android has started it; the station hears
/// one offer, and it is not made anew (its phase back to connecting) by the second.
sim("the_same_offer_again_is_not_made_anew", async (s) => {
  const endpoint = s.net.bindStation({ secretKey: s.net.key(), alpns: [ALPN], relayUrls: [], bindAddr: "127.0.0.1:0" });
  const offers: J[] = [];
  void (async () => {
    const conn = (await endpoint.accept())!;
    const control = (await conn.acceptBi())!;
    await Station.readLine(control, { bytes: Buffer.alloc(0) });
    await control.write(Buffer.from(`${JSON.stringify({ ok: true, station: "测试" })}\n`));
    for (;;) {
      const offer = await conn.acceptBi();
      if (offer === null) break;
      offers.push(JSON.parse((await Station.readLine(offer, { bytes: Buffer.alloc(0) }))!).adb);
      await offer.write(Buffer.from(`${JSON.stringify({ status: 200, headers: {} })}\n`));
      await offer.write(Buffer.from(`${JSON.stringify({ serial: "127.0.0.1:37001", adb: "off", message: "" })}\n`));
    }
  })().catch(() => {});
  const mesh = await s.run(Mesh.make(env(s), []));
  mesh.addAddr({ id: endpoint.id(), ips: endpoint.sockets() });
  const store = new Store(s.host, s.runner);
  const adb = new Adb({ host: s.host, runner: s.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential), relays: () => [], lends: () => true });
  const station = `ws/${endpoint.id()}`;
  const offer = { station, connect: null, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 };
  await s.run(adb.run({ kind: "share", offer }));
  assert.deepEqual([adb.value().sharing, adb.value().phase], [true, "connecting"]);
  await s.until(() => adb.value().adb === "off");
  await s.run(adb.run({ kind: "share", offer: { ...offer } }));
  assert.equal(adb.value().phase, "offered");
  // adbd found: offered with its port
  await s.run(adb.run({ kind: "share", offer: { ...offer, connect: 5555 } }));
  await s.until(() => offers.length === 2);
  assert.deepEqual(offers.map((o) => o.connect), [null, 5555]);
  await s.run(adb.run({ kind: "stop" }));
  await s.run(mesh.close());
  await s.settle(endpoint.close());
});

/// 2026-10-26, an OPPO: adbd gone from the port the app found (Wireless debugging turned off and on), every tunnel
/// refused and the station's adb let go until the phone offered again, which it did only as DNS-SD said something new.
/// The port refused is said (`refusedPort`), so that the app looks again; the station hears the port each offer has.
sim("a_connect_port_nothing_listens_on_is_said_so_the_app_looks_again", async (s) => {
  const endpoint = s.net.bindStation({ secretKey: s.net.key(), alpns: [ALPN], relayUrls: [], bindAddr: "127.0.0.1:0" });
  const offers: J[] = [];
  const answers: J[] = [];
  void (async () => {
    const conn = (await endpoint.accept())!;
    const control = (await conn.acceptBi())!;
    await Station.readLine(control, { bytes: Buffer.alloc(0) });
    await control.write(Buffer.from(`${JSON.stringify({ ok: true, station: "测试" })}\n`));
    for (;;) {
      const offer = await conn.acceptBi();
      if (offer === null) break;
      offers.push(JSON.parse((await Station.readLine(offer, { bytes: Buffer.alloc(0) }))!).adb);
      await offer.write(Buffer.from(`${JSON.stringify({ status: 200, headers: {} })}\n`));
      await offer.write(Buffer.from(`${JSON.stringify({ serial: "127.0.0.1:37001", adb: "connecting", message: "" })}\n`));
      if (offers.length === 1) {
        const tunnel = await conn.openBi();
        await tunnel.write(Buffer.from(`${JSON.stringify({ tunnel: "connect" })}\n`));
        answers.push(JSON.parse((await Station.readLine(tunnel, { bytes: Buffer.alloc(0) }))!));
      }
    }
  })().catch(() => {});
  const mesh = await s.run(Mesh.make(env(s), []));
  mesh.addAddr({ id: endpoint.id(), ips: endpoint.sockets() });
  const store = new Store(s.host, s.runner);
  const adb = new Adb({ host: s.host, runner: s.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential), relays: () => [], lends: () => true });
  const station = `ws/${endpoint.id()}`;
  const offer = { station, connect: 5555, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 };
  await s.run(adb.run({ kind: "share", offer }));
  await s.until(() => answers.length === 1);
  assert.deepEqual(answers[0], { error: "无法连接手机上的 adb：nothing listens on 5555" });
  assert.equal(adb.value().refusedPort, 5555);
  // The app found adbd on another port: offered with it, the refusal is of before.
  s.host.tcpConnect = echoTcp;
  await s.run(adb.run({ kind: "share", offer: { ...offer, connect: 5600 } }));
  await s.until(() => offers.length === 2);
  assert.deepEqual([offers[0].connect, offers[1].connect], [5555, 5600]);
  assert.equal(adb.value().refusedPort, null);
  await s.run(adb.run({ kind: "stop" }));
  await s.run(mesh.close());
  await s.settle(endpoint.close());
});

/// The station's tunnel on `conn` (station/src/mesh/adb.ts `tunnel`): what the phone answered to `{"tunnel": "connect"}`
/// within the station's 10 s, or null.
async function tunnelOn(s: Sim, conn: J): Promise<J> {
  const opened = (async () => {
    const tunnel = await conn.openBi();
    await tunnel.write(Buffer.from(`${JSON.stringify({ tunnel: "connect" })}\n`));
    const line = await Station.readLine(tunnel, { bytes: Buffer.alloc(0) });
    tunnel.reset?.(0);
    return line === null ? null : JSON.parse(line);
  })();
  return s.settle(opened, 10_000).catch(() => null);
}

/// 2026-10-17, a phone on ccvm's LAN: every tunnel the station opened went unanswered ("the phone did not answer"), adb
/// connect and pair alike, while the phone's requests went on its LAN way. The phone answers each tunnel on the link its
/// latest offer went on, whichever way that is, for as long as it is offered.
sim("tunnels_are_answered_on_the_lan_way", async (s) => {
  const { station, mesh, id } = await onLan(s, 5_000);
  station.lan = station.addr().ips;
  s.host.tcpConnect = echoTcp;
  const store = new Store(s.host, s.runner);
  const adb = new Adb({ host: s.host, runner: s.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => grants("ok", { n: 0 }), relays: () => [], lends: () => true });
  const addr = `ws/${id}`;
  await s.run(adb.run({ kind: "share", offer: { station: addr, connect: 5555, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 } }));
  await s.until(() => mesh.current(addr)?.pinned === LAN && station.offers.length > 0, 5 * 60_000);
  const answers: string[] = [];
  for (let i = 0; i < 12; i++) {
    const answer = await tunnelOn(s, station.offers.at(-1)!.conn);
    answers.push(answer?.ok === true ? "ok" : JSON.stringify(answer));
    await s.time.pass(10_000);
  }
  assert.deepEqual(answers, Array(12).fill("ok"), `offers: ${station.offers.length}`);
  await s.run(adb.run({ kind: "stop" }));
  await close(s, station, mesh);
});

/// 2026-10-17: the phone offers again as its ports change (twice within 1.5 s); a tunnel the station opened in between
/// was turned down as 已停止共享. It is served by the offer as it is when its head comes.
sim("a_tunnel_opened_as_the_phone_offers_again_is_served", async (s) => {
  const endpoint = s.net.bindStation({ secretKey: s.net.key(), alpns: [ALPN], relayUrls: [], bindAddr: "127.0.0.1:0" });
  let conn: J = null;
  void (async () => {
    conn = (await endpoint.accept())!;
    const control = (await conn.acceptBi())!;
    await Station.readLine(control, { bytes: Buffer.alloc(0) });
    await control.write(Buffer.from(`${JSON.stringify({ ok: true, station: "测试" })}\n`));
    // Every offer answered, as the station does, each on its own.
    for (let offer = await conn.acceptBi(); offer !== null; offer = await conn.acceptBi()) {
      const o = offer;
      void (async () => {
        await Station.readLine(o, { bytes: Buffer.alloc(0) });
        await o.write(Buffer.from(`${JSON.stringify({ status: 200, headers: {} })}\n`));
        await o.write(Buffer.from(`${JSON.stringify({ serial: "127.0.0.1:37001", adb: "connected", message: "" })}\n`));
      })().catch(() => {});
    }
  })().catch(() => {});
  s.host.tcpConnect = echoTcp;
  const mesh = await s.run(Mesh.make(env(s), []));
  mesh.addAddr({ id: endpoint.id(), ips: endpoint.sockets() });
  const store = new Store(s.host, s.runner);
  const adb = new Adb({ host: s.host, runner: s.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential), relays: () => [], lends: () => true });
  const station = `ws/${endpoint.id()}`;
  const offer = { station, connect: 5555, pair: null, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 };
  await s.run(adb.run({ kind: "share", offer }));
  await s.until(() => adb.value().adb === "connected");
  // A tunnel taken by the phone, its head not come yet.
  const tunnel = await s.settle(conn.openBi() as Promise<J>);
  await s.settle(tunnel.write(Buffer.from(" ")) as Promise<void>);
  await s.time.pass(100);
  // Its pairing port found: offered again, and answered.
  await s.run(adb.run({ kind: "share", offer: { ...offer, pair: 6666 } }));
  await s.until(() => adb.value().phase === "offered" && adb.value().pairPort === 6666);
  await s.settle(tunnel.write(Buffer.from(`${JSON.stringify({ tunnel: "connect" })}\n`)) as Promise<void>);
  const answer = await s.settle(Station.readLine(tunnel, { bytes: Buffer.alloc(0) }));
  assert.deepEqual(JSON.parse(answer!.trim()), { ok: true });
  await s.run(adb.run({ kind: "stop" }));
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

/// A device gone half way through its handshake (its app updating, a phone out of signal) holds up no other: the
/// station takes the next device while the first is still unanswered. Taken one at a time, every connection behind it
/// waited until it timed out, half a minute (2026-10-08). The first goes through a hole that lets its packets on and
/// drops the station's answers.
test("over_the_addon_a_handshake_left_hanging_holds_up_no_other", { skip: noAddon }, async () => {
  const station = await Station.start();
  const [host, port] = station.addr().ips[0].split(":");
  const hole = createSocket("udp4");
  await new Promise<void>((r) => hole.bind(0, "127.0.0.1", r));
  let answered = false;
  hole.on("message", (msg, from) => {
    if (from.port === Number(port)) answered = true;
    else hole.send(msg, Number(port), host);
  });
  const gone = await addon.bind({ secretKey: Buffer.alloc(32, 41), alpns: [], relayUrls: [], discovery: false });
  let goneSettled = false;
  const dialled = gone.connect({ id: station.id(), ips: [`127.0.0.1:${hole.address().port}`] }, Buffer.from(ALPN)).then(
    () => (goneSettled = true),
    () => (goneSettled = true),
  );
  // The station is on its handshake: it answered, into the hole.
  while (!answered) await new Promise((r) => setTimeout(r, 10));
  const next = await addon.bind({ secretKey: Buffer.alloc(32, 42), alpns: [], relayUrls: [], discovery: false });
  const conn = await next.connect(station.addr(), Buffer.from(ALPN));
  assert.equal(conn.remoteId(), station.id());
  assert.equal(goneSettled, false, "the first handshake is still left hanging");
  await gone.close();
  await dialled;
  await next.close();
  await station.close();
  hole.close();
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
