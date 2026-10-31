// A relay entrance added after connecting, through a real station and dev cloud (as in adb-e2e.ts).
// Run from a worktree after `pnpm run build` in station/: the native launcher, runner and mesh are built or fetched by
// scripts/native.ts. Set STILLFAIL_RELAY_BIN to a local iroh-relay binary. It starts only local, disposable services.
import assert from "node:assert/strict";
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer, connect as tcpConnect, type Server, type Socket } from "node:net";
import { join } from "node:path";
import { Effect } from "effect";
import type { Credential } from "../src/cloud.ts";
import { nodeIroh } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import { Mesh } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { readAll } from "../src/station/wire.ts";
import { FakeHost } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { Wakes } from "../src/wake.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const ROOT = join(import.meta.dirname, "..", "..", "..");
const native = (part: string) => process.env[`STILLFAIL_E2E_${part.toUpperCase()}`] || execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", part], { encoding: "utf8" }).trim();
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const same = (a: string | null, b: string) => a !== null && new URL(a).host === new URL(b).host;

async function until<T>(get: () => T | null | false | Promise<T | null | false>, label: string): Promise<T> {
  for (let i = 0; i < 150; i++) {
    const value = await Promise.resolve().then(get).catch(() => null);
    if (value) return value;
    await sleep(200);
  }
  throw new Error(`gave up waiting: ${label}`);
}

// The cloud uses six consecutive ports. Hold them while checking the range, then let the cloud bind them.
async function cloudPort(): Promise<number> {
  if (process.env.PORT) return Number(process.env.PORT);
  for (let i = 0; i < 50; i++) {
    // Below the usual ephemeral range, so the cloud's own outbound sockets are less likely to take one before it binds.
    const port = 20_000 + Math.floor(Math.random() * 10_000);
    const held: Server[] = [];
    let free = true;
    for (let offset = 0; free && offset < 6; offset++) {
      const next = createServer();
      free = await new Promise<boolean>((resolve) => next.once("error", () => resolve(false)).listen(port + offset, "127.0.0.1", () => resolve(true)));
      if (free) held.push(next);
    }
    await Promise.all(held.map((s) => new Promise<void>((resolve) => s.close(() => resolve()))));
    if (free) return port;
  }
  throw new Error("no free ports for the dev cloud");
}

mkdirSync(join(ROOT, "data"), { recursive: true });
const work = mkdtempSync(join(ROOT, "data", "relay-entry-e2e-"));
const app = join(work, "app");
const data = join(work, "station");
const sockets = new Set<Socket>();
let relay: ChildProcess | undefined;
let cloud: ChildProcess | undefined;
let station: ChildProcess | undefined;
let proxy: Server | undefined;
let runner: Runner | undefined;
let mesh: Mesh | undefined;
let passed = false;

try {
  // The proxy is the relay's ordinary address; the other address is a faster entrance to that same relay.
  const reserved = createServer();
  await new Promise<void>((resolve) => reserved.listen(0, "127.0.0.1", resolve));
  const relayPort = (reserved.address() as J).port as number;
  await new Promise<void>((resolve) => reserved.close(() => resolve()));
  const config = join(work, "relay.toml");
  writeFileSync(config, `enable_relay = true\nhttp_bind_addr = "127.0.0.1:${relayPort}"\nenable_metrics = false\nenable_quic_addr_discovery = false\n`);
  assert.ok(process.env.STILLFAIL_RELAY_BIN, "set STILLFAIL_RELAY_BIN to iroh-relay");
  relay = spawn(process.env.STILLFAIL_RELAY_BIN, ["--dev", "--config-path", config], { stdio: "ignore" });
  const entry = `http://127.0.0.1:${relayPort}`;
  await until(() => fetch(entry).then(() => true, () => false), "relay online");
  proxy = createServer((down) => {
    const up = tcpConnect(relayPort, "127.0.0.1");
    sockets.add(down);
    sockets.add(up);
    const pump = (from: Socket, to: Socket) => {
      from.on("data", (chunk) => setTimeout(() => { if (!to.destroyed) to.write(chunk); }, 100));
      from.on("close", () => { sockets.delete(from); to.destroy(); });
      from.on("error", () => to.destroy());
    };
    pump(down, up);
    pump(up, down);
  });
  await new Promise<void>((resolve) => proxy!.listen(0, "127.0.0.1", resolve));
  const direct = `http://127.0.0.1:${(proxy.address() as J).port}`;
  const port = await cloudPort();
  const origin = `http://127.0.0.1:${port}`;
  const cloudLog = openSync(join(work, "cloud.log"), "a");
  cloud = spawn("pnpm", ["exec", "tsx", "test/dev.ts"], { cwd: join(ROOT, "cloud"), detached: process.platform !== "win32", env: { ...process.env, PORT: String(port), RELAY: direct, AXIOM_TOKEN: "" }, stdio: ["ignore", cloudLog, cloudLog] });
  const alice = await until(async () => {
    const r = await fetch(`${origin}/__dev/account?user=alice`);
    return r.ok ? await r.json() as { access: string } : null;
  }, "dev cloud online");
  const api = async (method: string, path: string, body?: unknown): Promise<J> => {
    const r = await fetch(`${origin}${path}`, { method, headers: { authorization: `Bearer ${alice.access}`, "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
    const answer = await r.text();
    if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${answer}`);
    return answer ? JSON.parse(answer) : null;
  };
  const ws = (await api("GET", "/v1/me")).workspaces.find((w: J) => w.name === "Dev").id as string;
  mkdirSync(join(app, "node/bin"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  const meshNative = native("mesh");
  const env = { ...process.env, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: meshNative, STILLFAIL_RUNNER: native("runner") };
  const enrollment = (await api("POST", `/v1/workspaces/${ws}/enrollments`, { name: "relay-entry-test" })).command as string;
  const launcher = native("launcher");
  execFileSync(launcher, ["enroll", ...enrollment.split(" ").slice(3), "--app", app, "--data", data], { env });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [] }));
  const stationId = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station as string;
  const stationLog = openSync(join(work, "station.log"), "a");
  station = spawn(launcher, ["run", "--app", app, "--data", data], { env, stdio: ["ignore", stationLog, stationLog] });
  await until(() => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true, "station online");

  process.env.STILLFAIL_MESH_NATIVE = meshNative;
  const rawIroh = nodeIroh();
  assert.ok(rawIroh, "mesh addon is available");
  const iroh = { bind: (options: Parameters<typeof rawIroh.bind>[0]) => rawIroh.bind({ ...options, lookup: false, relayOnly: true }) };
  const host = new FakeHost();
  runner = new Runner();
  mesh = await runner.run(Mesh.make({ host, runner, tracer: new Tracer(host, runner, 1), iroh, wakes: new Wakes() }, [direct]));
  mesh.addAddr({ id: stationId, relays: [direct] });
  const credentials = (device: string) => Effect.promise(async () => {
    const c = await api("POST", `/v1/workspaces/${ws}/credential`, { device });
    return { credential: c.credential, issued_at: c.issued_at ?? 0, expires_at: c.expires_at ?? 0, relay_url: c.relay_url ?? direct } as Credential;
  });
  const link = await runner.run(mesh.link(stationId, credentials));
  const request = async () => {
    const response = await runner!.run(link.request({ method: "GET", path: "/admin/api/overview", headers: [] }, new Uint8Array()));
    await runner!.run(readAll(response.body));
    assert.equal(response.status, 200);
  };
  await request();
  assert.ok(same(link.via(), direct), `first entrance: ${link.via()}`);
  const connected = (readFileSync(join(work, "station.log"), "utf8").match(/client connected/g) ?? []).length;
  assert.equal(connected, 1);
  mesh.retune([direct], [entry], { [entry]: direct });
  await until(() => same(link.via(), entry), "faster entrance selected");
  assert.equal(mesh.current(stationId), link);
  await request();
  assert.equal((readFileSync(join(work, "station.log"), "utf8").match(/client connected/g) ?? []).length, connected);
  console.log("PASS real station keeps its connection and answers through the faster relay entrance");
  passed = true;
} catch (error) {
  console.error(`relay entrance e2e failed; logs: ${work}`, error);
} finally {
  if (mesh && runner) await runner.run(mesh.close());
  runner?.shutdown();
  const ended = (child: ChildProcess | undefined) => child && child.exitCode === null
    ? Promise.race([new Promise<void>((resolve) => child.once("exit", () => resolve())), sleep(5000)])
    : Promise.resolve();
  const stopping = [ended(station), ended(cloud), ended(relay)];
  station?.kill("SIGTERM");
  if (cloud?.pid && process.platform !== "win32") {
    try { process.kill(-cloud.pid, "SIGTERM"); } catch { /* already exited */ }
  } else cloud?.kill("SIGTERM");
  relay?.kill("SIGTERM");
  for (const socket of sockets) socket.destroy();
  proxy?.close();
  await Promise.all(stopping);
  for (const child of [station, cloud, relay]) {
    if (child && child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
  }
}
if (passed) rmSync(work, { recursive: true, force: true });
process.exit(passed ? 0 : 1);
