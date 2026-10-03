// client/core/src/mesh.rs tests, ported: a station on localhost over the native addon (station/native/mesh), the
// client's mesh over the same addon. Real time here (iroh needs its own clock).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import type { Credential } from "../src/cloud.ts";
import { CoreError } from "../src/error.ts";
import { loadAddon, nodeIroh } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import { ALPN, DEVICE_KEY, FORMER_ALPN, Mesh, MeshWire, quicker, type CredentialSource, type Link } from "../src/mesh.ts";
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

function env(host: FakeHost, wakes = new Wakes()) {
  const runner = new Runner();
  return { host, runner, tracer: new Tracer(host, runner, 1), iroh: nodeIroh()!, wakes };
}

async function setup(station?: Station, host = new FakeHost(), wakes = new Wakes()) {
  const s = station ?? (await Station.start());
  const e = env(host, wakes);
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
  const wire = new MeshWire({ mesh: () => Effect.succeed(mesh), meshNow: () => mesh, credentials: () => grants("ok", { n: 0 }), status: () => status });
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
  const adb = new Adb({ host, runner: e.runner, store, mesh: () => Effect.succeed(mesh), credentials: () => () => Effect.succeed({ credential: "ok", issued_at: 0, expires_at: 0, relay_url: "" } as Credential) });
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
