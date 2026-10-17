// A phone's adb lent to a real station end to end (docs/adb-share.md): a dev cloud (cloud/test/dev.ts), a real station
// with the fake adb (station/test/fake/adb.mjs) on its PATH, and this core's mesh and Adb over real iroh, its adbd an
// echo server. The phone offers, the station `adb connect`s through a tunnel, then pairs a few times a while: each
// pairing is a tunnel of its own, opened as the mesh's ways come and go.
//
//   node client/core-ts/side/adb-e2e.ts   (from a worktree with `pnpm run build` done in station/ and
//                                          `pnpm run build:cloud` at the top, the iroh dev relay on :3340; PORT,
//                                          default 8877, and PORT+1..+4 free; ROUNDS pairings, default 8)
//
// Prints a line per check and exits 1 if any failed. Real processes and a real relay: a side run, not CI's.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { Effect } from "effect";
import { Adb } from "../src/adb.ts";
import type { Credential } from "../src/cloud.ts";
import { nodeTcp } from "../src/hosts/node.ts";
import { nodeIroh } from "../src/hosts/node-iroh.ts";
import { holdLanguage } from "../src/i18n.ts";
import { Mesh } from "../src/mesh.ts";
import { Runner } from "../src/runtime.ts";
import { Store } from "../src/store.ts";
import { FakeHost } from "../src/testing.ts";
import { Tracer } from "../src/trace.ts";
import { Wakes } from "../src/wake.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const ROOT = join(import.meta.dirname, "..", "..", "..");
const PORT = Number(process.env.PORT ?? 8877);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/adb-e2e";
const ROUNDS = Number(process.env.ROUNDS ?? 8);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const t0 = Date.now();
const at = () => `${((Date.now() - t0) / 1000).toFixed(1)}s`;

const results: { check: string; ok: boolean }[] = [];
function check(name: string, saw: string, ok: boolean) {
  results.push({ check: name, ok });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}\n     ${saw}`);
}
const native = (what: string) => execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", what], { encoding: "utf8" }).trim();
async function until<T>(what: () => Promise<T | null | undefined | false> | T | null | undefined | false, label: string, tries = 300): Promise<T> {
  for (let i = 0; i < tries; i++) {
    const v = await (async () => what())().catch(() => null);
    if (v) return v;
    await sleep(200);
  }
  throw new Error(`gave up waiting: ${label}`);
}

let cloud: ChildProcess | null = null;
async function startCloud() {
  const p = spawn("pnpm", ["exec", "tsx", "test/dev.ts"], { cwd: join(ROOT, "cloud"), env: { ...process.env, PORT: String(PORT), RELAY }, stdio: ["ignore", "pipe", "pipe"] });
  const up = await new Promise<boolean>((resolve) => {
    let out = "";
    p.stdout!.on("data", (d) => ((out += d), out.includes("READY still.fail cloud") && resolve(true)));
    p.on("exit", () => resolve(false));
  });
  if (!up) throw new Error("the dev cloud did not start");
  cloud = p;
}
type Account = { sub: string; email: string; access: string };
const account = async (user: string): Promise<Account> => (await fetch(`${ORIGIN}/__dev/account?user=${user}`)).json() as Promise<Account>;
async function api(who: Account, method: string, path: string, body?: unknown): Promise<J> {
  const r = await fetch(`${ORIGIN}${path}`, { method, headers: { authorization: `Bearer ${who.access}`, "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

const dir = join(WORK, "station");
const data = join(dir, "data");
const app = join(dir, "app");
const fakeAdb = join(WORK, "adb");
// SERVE=1: the cloud and the station only, left up for a phone (an emulator) to offer itself, the station on the real
// adb in PATH (with ANDROID_ADB_SERVER_PORT, a server of its own).
const SERVE = process.env.SERVE === "1";
const stationEnv = () => ({
  ...process.env,
  PATH: SERVE ? process.env.PATH : `${join(ROOT, "station/test/fake")}:${process.env.PATH}`,
  FAKE_ADB_DIR: fakeAdb,
  STILLFAIL_NO_DISCOVERY: "1",
  STILLFAIL_MESH_NATIVE: native("mesh"),
  STILLFAIL_RUNNER: native("runner"),
});
let proc: ChildProcess | null = null;
const online = () => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true;
function stopStation() {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}

/// adbd: says back what it hears.
function adbd(): Promise<number> {
  return new Promise((resolve) => {
    const server = createServer((socket) => socket.pipe(socket));
    server.listen(0, "127.0.0.1", () => resolve((server.address() as J).port));
    server.unref();
  });
}

/// STATION=<id> WS=<workspace>: a station already up (another machine's, on the cloud at PORT): only the phone here.
async function client(): Promise<{ alice: Account; ws: string; stationId: string }> {
  return { alice: await account("alice"), ws: process.env.WS!, stationId: process.env.STATION! };
}

async function main() {
  const { alice, ws, stationId } = process.env.STATION ? await client() : await serve();
  return phone(alice, ws, stationId);
}

async function serve(): Promise<{ alice: Account; ws: string; stationId: string }> {
  stopStation();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(fakeAdb, { recursive: true });
  await startCloud();
  const alice = await account("alice");
  const ws = (await api(alice, "GET", "/v1/me")).workspaces.find((w: J) => w.name === "Dev").id as string;
  mkdirSync(join(app, "node/bin"), { recursive: true });
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  const command = (await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "studio" })).command as string;
  execFileSync(native("launcher"), ["enroll", ...command.split(" ").slice(3), "--app", app, "--data", data], { env: stationEnv() });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [] }));
  const stationId = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station as string;
  proc = spawn(native("launcher"), ["run", "--app", app, "--data", data], { env: stationEnv(), stdio: ["ignore", openSync(join(dir, "station.log"), "a"), openSync(join(dir, "station.log"), "a")] });
  await until(() => online(), "station online");
  console.log(`${at()} station ${stationId.slice(0, 12)} online`);
  if (SERVE) {
    // The workspace's own relay as well: the phone has two ways, steers between them, and so takes the LAN way.
    if (process.env.THEIRS) await api(alice, "PUT", `/v1/workspaces/${ws}/relays`, { relays: [process.env.THEIRS] });
    console.log(`SERVING ws=${ws} station=${stationId} log=${join(dir, "station.log")}`);
    await new Promise(() => {});
  }
  return { alice, ws, stationId };
}

async function phone(alice: Account, ws: string, stationId: string) {
  const host = new FakeHost();
  (host as J).tcp = nodeTcp;
  const runner = new Runner();
  const env = { host, runner, tracer: new Tracer(host, runner, 1), iroh: nodeIroh()!, wakes: new Wakes() };
  const mesh = await runner.run(Mesh.make(env, [RELAY]));
  mesh.addAddr({ id: stationId, relays: [RELAY] });
  const credentials = () => (device: string) =>
    Effect.promise(async () => {
      const c = await api(alice, "POST", `/v1/workspaces/${ws}/credential`, { device });
      return { credential: c.credential, issued_at: c.issued_at ?? 0, expires_at: c.expires_at ?? 0, relay_url: c.relay_url ?? RELAY } as Credential;
    });
  const store = new Store(host, runner);
  // THEIRS: a relay of the workspace's own (the same relay under another URL will do): two ways to choose between, so
  // the mesh steers, and takes the LAN way as a phone on its station's LAN does.
  const theirs = process.env.THEIRS ? [process.env.THEIRS] : [];
  const adb = new Adb({ host, runner, store, mesh: () => Effect.succeed(mesh), credentials, relays: () => theirs });
  const station = `${ws}/${stationId}`;
  const connectPort = await adbd();
  const pairPort = await adbd();
  await runner.run(adb.run({ kind: "share", offer: { station, connect: connectPort, pair: pairPort, device: "Pixel 8", android: "14", package: "fail.still.android", minutes: 60 } }));
  const connected = await until(() => adb.value().adb === "connected" && adb.value(), "the station's adb connected", 150).catch(() => null);
  if (theirs.length > 0) {
    if (process.env.STATION) await api(alice, "PUT", `/v1/workspaces/${ws}/relays`, { relays: theirs });
    const lan = await until(() => mesh.current(station)?.pinned === "lan", "requests on the LAN way", 300).then(() => true, () => false);
    console.log(`${at()} on the LAN way: ${lan}`);
  }
  check("offered and connected through a tunnel", `${at()} ${JSON.stringify(adb.value())}`, connected !== null);

  let paired = 0;
  for (let i = 0; i < ROUNDS; i++) {
    await sleep(10_000);
    const r = await runner.run(Effect.result(adb.run({ kind: "pair", code: "123456" })));
    const ok = r._tag === "Success";
    if (ok) paired++;
    const cur = mesh.current(station);
    console.log(`${at()} pair ${i + 1} on ${cur?.pinned ?? "main"} ${cur?.path()} ${cur?.paths()}: ${ok ? JSON.stringify(r.success) : (r as J).failure.message}`);
  }
  check("each pairing went through its tunnel", `${paired} of ${ROUNDS}`, paired === ROUNDS);
  if (!process.env.STATION) console.log(readFileSync(join(dir, "station.log"), "utf8").split("\n").filter((l) => /adb|client connected/.test(l)).join("\n"));
  await runner.run(adb.run({ kind: "stop" }));
  await runner.run(mesh.close());
  runner.shutdown();
  return results.every((r) => r.ok);
}

let ok = false;
try {
  ok = await main();
} catch (e) {
  console.error("e2e stopped:", e);
} finally {
  (cloud as ChildProcess | null)?.kill();
  if (!process.env.STATION) stopStation();
}
process.exit(ok ? 0 : 1);
