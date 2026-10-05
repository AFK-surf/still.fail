// A station in Comma end to end, over the real mesh addon and a fake Comma control plane (test/fake-control-plane.ts):
// enrolled with `--provider comma`, online on Comma's presence socket (its gateways named there), a member's credential
// Comma signed taken on `stillfail/admin/1`, a viewer's write refused, and the gateway's `comma/tools/1` admitted —
// exec refused under the default `read`, done once an owner sets `full`, a chat started and driven — while another
// iroh id is turned away.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Fiber, Stream, SubscriptionRef } from "effect";
import { Admin } from "../src/api/admin.ts";
import { enroll } from "../src/cli.ts";
import { loadKey } from "../src/cloud/key.ts";
import { makeControlPlane } from "../src/cloud/plane.ts";
import { Cloud } from "../src/cloud/state.ts";
import { DeviceTools, accessOf } from "../src/device/tools.ts";
import { Jobs } from "../src/jobs/jobs.ts";
import { loadMesh, type Connection, type Stream as MeshStream } from "../src/mesh/native.ts";
import { ALPN, Reader, serve } from "../src/mesh/serve.ts";
import { TOOLS_ALPN, adminSessions, serveTools } from "../src/mesh/tools.ts";
import { ABOUT } from "../src/api/routes/tools.ts";
import { ConfigFile } from "../src/ops/config.ts";
import { checkConfig } from "../src/accounts/check.ts";
import { Readers } from "../src/read/pool.ts";
import { hubConfig } from "../src/sessions/config.ts";
import { Hub } from "../src/sessions/hub.ts";
import { InternalChat } from "../src/sessions/internal.ts";
import { Store } from "../src/store/store.ts";
import { FakeControlPlane } from "./fake-control-plane.ts";
import { FakeDriver, settle } from "./hub-fakes.ts";

const until = async (what: () => boolean, ms = 10_000) => {
  const end = Date.now() + ms;
  while (!what()) {
    if (Date.now() > end) throw new Error("timed out");
    await new Promise((r) => setTimeout(r, 20));
  }
};

const line = (stream: MeshStream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));

/// A member's connection: its credential first, answered.
async function member(conn: Connection, credential: string) {
  const first = await conn.openBi();
  await line(first, { credential, protocol: 2 });
  return new Reader(first).line();
}

/// One admin API request on its own stream: its status and JSON body.
async function ask(conn: Connection, method: string, path: string, body?: unknown) {
  const stream = await conn.openBi();
  await line(stream, { method, path, headers: { "content-type": "application/json" } });
  if (body !== undefined) await stream.write(Buffer.from(JSON.stringify(body)));
  await stream.finish();
  const reader = new Reader(stream);
  const head = await reader.line();
  return [head.status, JSON.parse((await reader.rest()).toString() || "null")] as const;
}

/// One device tool on its own stream.
async function tool(conn: Connection, op: string, args: Record<string, unknown>, workspace = "ws1") {
  const stream = await conn.openBi();
  await line(stream, { op, id: randomBytes(4).toString("hex"), context: { workspace, user_email: "owner@x", agent: "salix" }, args });
  await stream.finish();
  return new Reader(stream).line();
}

test("a station in Comma: enrolled, online, a member admitted, a viewer read-only, the gateway's tools as access allows", async (t) => {
  const mesh = loadMesh();
  const bindClient = () => mesh.bind({ secretKey: randomBytes(32), alpns: [Buffer.from("client/1")], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const [gateway, stranger, client, viewerDevice] = await Promise.all([bindClient(), bindClient(), bindClient(), bindClient()]);

  // Comma, naming the gateway.
  const comma = new FakeControlPlane({ provider: "comma", gateways: [gateway.id()] });
  const origin = await comma.start();
  const data = mkdtempSync(join(tmpdir(), "comma-e2e-"));
  const said = console.log;
  console.log = () => {};
  await enroll(data, origin, "tok", "comma").finally(() => (console.log = said));
  const key = loadKey(data);
  const state = new Cloud(data);
  const up = Effect.runSync(SubscriptionRef.make(true));
  const plane = makeControlPlane({ state, changes: Stream.never, key, up });
  const presence = Effect.runFork(plane.presence);
  await until(() => state.peersCurrent && (state.state!.gateway_keys ?? []).includes(gateway.id()));

  // The station's own parts: its store, a hub with scripted runtimes, the admin API, the device tools.
  const config = new ConfigFile(data);
  config.check = checkConfig;
  const hubSettings = hubConfig({ profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }] }, data);
  const store = Store.open(join(data, "stillfail.db"), join(data, "archive"));
  const claude = new FakeDriver("claude");
  const hub = new Hub({ config: () => hubSettings, store, chats: () => undefined, drivers: [claude, new FakeDriver("codex")], mcpUrl: "http://127.0.0.1:1/mcp", internal: new InternalChat(), runners: () => [] });
  const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
  hub.setJobs(jobs);
  const readers = new Readers(data, 1);
  readers.processes = () => hub.processes();
  const admin = new Admin(readers, { store, agents: { hub, jobs, config } as any });
  const station = await mesh.bind({ secretKey: key.seed, alpns: [ALPN, TOOLS_ALPN], relayUrls: [], discovery: false, bindAddr: "127.0.0.1:0" });
  const work = mkdtempSync(join(tmpdir(), "comma-work-"));
  const device = new DeviceTools({ home: work, protect: () => [data], sessions: adminSessions(() => admin, () => store, () => ["claude"], () => "ws1", gateway.id()) });
  const members = { cloud: state, admin, up: () => true, shares: {} as any, accepted: plane.credential };
  const gateways = { cloud: state, tools: device, access: () => accessOf(config.raw()), enabled: () => plane.spec().tools };
  void (async () => {
    for (;;) {
      const conn = await station.accept();
      if (!conn) return;
      void (conn.alpn().equals(TOOLS_ALPN) ? serveTools(gateways, conn) : serve(members, conn)).catch(() => {});
    }
  })();
  t.after(async () => {
    device.close();
    await Effect.runPromise(Fiber.interrupt(presence));
    await Promise.all([station, gateway, stranger, client, viewerDevice].map((e) => e.close()));
    await hub.shutdown();
    await jobs.shutdown();
    readers.close();
    store.close();
    state.close();
    await comma.close();
    rmSync(data, { recursive: true, force: true });
    rmSync(work, { recursive: true, force: true });
  });
  assert.equal(station.id(), key.id);
  const addr = { id: station.id(), ips: [`127.0.0.1:${station.sockets()[0]!.split(":").at(-1)}`] };

  // A member's credential, as Comma signs it for this device.
  const now = Math.floor(Date.now() / 1000);
  const credential = (device: string, role: string) =>
    comma.grant.credential({ typ: "comma-member+jwt" }, { iss: "comma", sub: `usr_${role}`, email: `${role}@x`, name: role, ws: "ws1", role, device, sid: `s_${role}`, iat: now, exp: now + 3600 });
  const owner = await client.connect(addr, ALPN);
  assert.deepEqual(await member(owner, credential(client.id(), "owner")), { ok: true, station: "studio", expires_at: now + 3600 });
  assert.deepEqual(await ask(owner, "GET", "/admin/api/tools/access"), [200, { access: "off", levels: ["off", "read", "full"], read_ops: ["fs.read", "fs.list", "fs.stat", "runtime.probe", "process.list", "process.tail", "session.status"], about: ABOUT }]);

  // still.fail cloud's credential is no member's here.
  const other = await stranger.connect(addr, ALPN);
  const refused = await member(other, comma.grant.credential({ typ: "stillfail-member+jwt" }, { iss: "stillfail-cloud", ws: "ws1", device: stranger.id(), exp: now + 3600 }));
  assert.equal(refused.error, "not a member's credential");

  // A viewer reads, and changes nothing.
  const viewer = await viewerDevice.connect(addr, ALPN);
  assert.equal((await member(viewer, credential(viewerDevice.id(), "viewer"))).ok, true);
  assert.equal((await ask(viewer, "GET", "/admin/api/tools/access"))[0], 200);
  assert.deepEqual(await ask(viewer, "POST", "/admin/api/sessions", { runtime: "claude" }), [403, { error: "read-only members cannot change this station" }]);
  assert.deepEqual(await ask(viewer, "PUT", "/admin/api/tools/access", { access: "full" }), [403, { error: "read-only members cannot change this station" }]);
  // Nor through a preview's socket, whose page may send anything.
  const socket = await viewerDevice.connect(addr, ALPN).then(async (c) => (await member(c, credential(viewerDevice.id(), "viewer")), c));
  const ws = await socket.openBi();
  await line(ws, { method: "GET", path: "/admin/api/preview/5180/ws", headers: {}, socket: true });
  const wsHead = await new Reader(ws).line();
  assert.equal(wsHead.status, 403);

  // The gateway: off until an owner turns it on.
  const tools = await gateway.connect(addr, TOOLS_ALPN);
  assert.deepEqual(await tool(tools, "fs.stat", { path: work }), { ok: false, error: { code: "forbidden", message: "device tools are turned off on this station" } });
  assert.equal((await ask(owner, "PUT", "/admin/api/tools/access", { access: "read" }))[0], 200);
  const stat = await tool(tools, "fs.stat", { path: work });
  assert.equal(stat.ok, true);
  assert.equal(stat.result.type, "dir");
  assert.deepEqual(await tool(tools, "exec", { command: "echo hi" }), { ok: false, error: { code: "forbidden", message: "exec needs full access; this station allows read" } });
  // Never the station's own data, nor for another workspace.
  assert.equal((await tool(tools, "fs.read", { path: join(data, "mesh", "secret.key") })).error.code, "forbidden");
  assert.deepEqual(await tool(tools, "fs.stat", { path: work }, "ws2"), { ok: false, error: { code: "forbidden", message: "the request is for another workspace than this station's" } });

  // An owner gives it full access: exec runs.
  assert.equal((await ask(owner, "PUT", "/admin/api/tools/access", { access: "full" }))[0], 200);
  // A large write: its content rides in the request's line (up to 12 MiB), well past the admin API's 16 KiB heads.
  const big = Buffer.alloc(5 * 1024 * 1024, 7);
  assert.deepEqual(await tool(tools, "fs.write", { path: join(work, "big.bin"), content_base64: big.toString("base64") }), { ok: true, result: { size: big.length } });
  assert.ok(readFileSync(join(work, "big.bin")).equals(big));
  const ran = await tool(tools, "exec", { command: "echo hi" });
  assert.deepEqual(ran, { ok: true, result: { exit_code: 0, stdout: "hi\n", stderr: "", truncated: false } });

  // A chat started for its requester, as the pages start one: its session and thread, the prompt said in it.
  const started = await tool(tools, "session.start", { prompt: "look at the build", title: "build", requester_email: "owner@x" });
  assert.equal(started.ok, true, JSON.stringify(started));
  const thread = Number(started.result.thread);
  await until(() => claude.sessions.length === 1 && claude.last().prompts.length === 1);
  assert.match(claude.last().prompts[0]!, /look at the build/);
  assert.equal(store.getThread(thread)!.createdBy, "owner@x");
  assert.equal(store.threadSessions(thread)[0]!.session, started.result.session);
  assert.deepEqual(await tool(tools, "session.status", { thread: String(thread) }), { ok: true, result: { state: "running" } });
  // Said to again by the requester: their message in the same chat.
  assert.deepEqual(await tool(tools, "session.say", { thread: String(thread), text: "and the tests", requester_email: "owner@x" }), { ok: true, result: {} });
  await settle();
  assert.ok(store.listThreads("owner@x", null, thread)[0]!.lastMessage!.text === "and the tests");

  // Another iroh id is no gateway.
  const intruder = await stranger.connect(addr, TOOLS_ALPN);
  await assert.rejects(tool(intruder, "fs.stat", { path: work }));

  // Comma takes the gateway back: its next request is refused.
  comma.gateways = [];
  comma.push(station.id());
  await until(() => (state.state!.gateway_keys ?? []).length === 0);
  assert.deepEqual(await tool(tools, "fs.stat", { path: work }), { ok: false, error: { code: "forbidden", message: "not a gateway of this station's control plane" } });
});
