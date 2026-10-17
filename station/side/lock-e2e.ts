// The workspace lock end to end (docs/workspace-lock.md), on a dev cloud (cloud/test/dev.ts) and real stations: what a
// compromised cloud does — mint a credential for a device of its own, put a station of its own in the roster, swap the
// grant key, move a station to another workspace — refused by the stations that pinned the lock, and still done to
// one that did not. The owner's device is a real core (desktop's Node host); the new device's and station's paths too.
//
//   node station/side/lock-e2e.ts          (from a worktree with `pnpm run build` done in station/, the iroh dev relay
//                                            on :3340; PORT, default 8877, and PORT+1..+4 free)
//
// It prints a line per check and a table at the end, and exits 1 if any check failed. Real processes and a real relay:
// a side test (scripts/side.sh), not one of the deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { StationKey } from "../src/cloud/key.ts";
import { Cloud } from "../src/cloud/state.ts";
import { loadMesh, type Connection, type Endpoint } from "../src/mesh/native.ts";
import { PEER_ALPN, peerCall } from "../src/mesh/peer.ts";
import { ALPN } from "../src/mesh/serve.ts";
// The core, as the desktop app runs it: imported by its path at run time, so the station's typecheck does not take in
// the core's sources (they are checked under the core's own settings).
const CORE = "../../client/core-ts/src/hosts/node.ts";
const { start } = (await import(CORE)) as { start: (dir: string, origin: string, listener: (client: number, json: string) => void) => { connect(): number; receive(client: number, json: string): void; close(): Promise<void> } };

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8877);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/lock-e2e";
const AUTH_KEY = "lock-e2e-auth-key-0123456789abcdef0123456789abcdef";

const results: { check: string; locked: string; unlocked: string; ok: boolean }[] = [];
const say = (s: string) => console.log(`\n== ${s}`);
function check(name: string, locked: string, unlocked: string, ok: boolean) {
  results.push({ check: name, locked, unlocked, ok });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}\n     locked: ${locked}\n     unlocked: ${unlocked}`);
}
const native = (what: string) => execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", what], { encoding: "utf8" }).trim();
// The mesh addon for this process too: the raw devices' endpoints, and the core's (hosts/node-iroh.ts).
process.env.STILLFAIL_MESH_NATIVE ??= native("mesh");
const until = async <T>(what: () => Promise<T | null | undefined | false>, label: string, tries = 300): Promise<T> => {
  for (let i = 0; i < tries; i++) {
    const v = await what().catch(() => null);
    if (v) return v;
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`gave up waiting: ${label}`);
};

/// Alice's cores share her account's 120 requests a minute (cloud/src/account.ts LIMITS), and over it a request is
/// turned away as signed out: a step that asks much starts in a minute of its own.
const nextMinute = () => new Promise((r) => setTimeout(r, (61 - new Date().getSeconds()) * 1000));

// ── the cloud ──

let cloud: ChildProcess | null = null;
async function startCloud() {
  for (let attempt = 0; attempt < 20; attempt++) {
    const p = spawn("pnpm", ["exec", "tsx", "test/dev.ts"], { cwd: join(ROOT, "cloud"), env: { ...process.env, PORT: String(PORT), RELAY, PERSIST: join(WORK, "cloud"), AUTH_KEY }, stdio: ["ignore", "pipe", "pipe"] });
    const up = await new Promise<boolean>((resolve) => {
      let out = "";
      p.stdout!.on("data", (d) => ((out += d), out.includes("READY still.fail cloud") && resolve(true)));
      p.on("exit", () => resolve(false));
    });
    if (up) return (cloud = p);
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("the dev cloud did not start");
}
async function stopCloud() {
  if (!cloud) return;
  const p = cloud;
  cloud = null;
  await new Promise((r) => (p.on("exit", r), p.kill()));
}

type Account = { sub: string; email: string; access: string; refresh: string; accessExpires: number };
const account = async (user: string): Promise<Account> => (await fetch(`${ORIGIN}/__dev/account?user=${user}`)).json() as Promise<Account>;
async function api(who: Account, method: string, path: string, body?: unknown): Promise<any> {
  const r = await fetch(`${ORIGIN}${path}`, { method, headers: { authorization: `Bearer ${who.access}`, "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

// ── stations ──

const env = () => ({ ...process.env, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") });
type Station = { name: string; data: string; id: string; proc: ChildProcess | null; enrolled: string };
function makeStation(name: string, enroll: string[]): Station {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, "app/node/bin"), { recursive: true });
  mkdirSync(join(dir, "data/homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(dir, "app/station"));
  symlinkSync(process.execPath, join(dir, "app/node/bin/node"));
  const out = execFileSync(native("launcher"), ["enroll", ...enroll, "--app", join(dir, "app"), "--data", join(dir, "data")], { env: env(), encoding: "utf8" });
  writeFileSync(join(dir, "data/config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(dir, "data/homes/fake/.credentials.json"), "{}");
  const id = JSON.parse(readFileSync(join(dir, "data/mesh/cloud.json"), "utf8")).station as string;
  return { name, data: join(dir, "data"), id, proc: null, enrolled: out };
}
function run(s: Station) {
  const log = openSync(join(s.data, "../station.log"), "a");
  s.proc = spawn(native("launcher"), ["run", "--app", join(s.data, "../app"), "--data", s.data], { env: env(), stdio: ["ignore", log, log] });
}
const stationState = (s: Station) => JSON.parse(readFileSync(join(s.data, "mesh/cloud.json"), "utf8"));
const status = (s: Station) => execFileSync(native("launcher"), ["status", "--app", join(s.data, "../app"), "--data", s.data], { env: env(), encoding: "utf8" });
const enrollArgs = (command: string) => command.split(" ").slice(3);

// ── a raw device (the attacker's, or a station of its own): iroh with its own key ──

const mesh = loadMesh();
async function endpointOf(seed: Buffer, alpn: Buffer): Promise<Endpoint> {
  const e = await mesh.bind({ secretKey: seed, alpns: [alpn], relayUrls: [RELAY], discovery: false });
  await e.online();
  return e;
}
/// Connects as a member's device with `credential`: the station's answer to the hello, and with it admitted, its
/// answer to GET /admin/api/overview (what any member may read; a member may also run things).
async function asDevice(endpoint: Endpoint, station: string, credential: string): Promise<{ hello: any; overview: number | null }> {
  // A connection that the relay lost on the way is tried again (a refusal is an answer, not a loss).
  for (let attempt = 1; ; attempt++) {
    try {
      return await asDeviceOnce(endpoint, station, credential);
    } catch (e) {
      if (attempt >= 3 || !/connection lost|closed/i.test(String((e as Error).message))) throw e;
    }
  }
}
async function asDeviceOnce(endpoint: Endpoint, station: string, credential: string): Promise<{ hello: any; overview: number | null }> {
  const conn: Connection = await endpoint.connect({ id: station, relays: [RELAY] }, ALPN);
  try {
    const first = await conn.openBi();
    await first.write(Buffer.from(JSON.stringify({ credential, protocol: 2 }) + "\n"));
    const hello = JSON.parse((await readLine(first)) ?? "null");
    if (!hello?.ok) return { hello, overview: null };
    const req = await conn.openBi();
    await req.write(Buffer.from(JSON.stringify({ method: "GET", path: "/admin/api/overview", headers: {} }) + "\n"));
    await req.finish();
    const head = JSON.parse((await readLine(req)) ?? "null");
    return { hello, overview: head?.status ?? null };
  } finally {
    conn.close(0, "done");
  }
}
async function readLine(stream: { read(): Promise<Buffer | null> }): Promise<string | null> {
  let carry = Buffer.alloc(0);
  for (;;) {
    const at = carry.indexOf(10);
    if (at >= 0) return carry.subarray(0, at).toString();
    const more = await stream.read();
    if (!more) return carry.length ? carry.toString() : null;
    carry = Buffer.concat([carry, more]);
  }
}
const credentialFor = async (who: Account, ws: string, device: string) => (await api(who, "POST", `/v1/workspaces/${ws}/credential`, { device })).credential as string;
const said = (r: { hello: any; overview: number | null }) => (r.hello?.ok ? `admitted as ${r.hello.station}, GET overview ${r.overview}` : `refused: ${r.hello?.code ?? ""} ${r.hello?.error ?? JSON.stringify(r.hello)}`.trim());

// ── a core: the owner's desktop app, or a new device ──

function core(name: string) {
  const dir = join(WORK, `core-${name}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const waiting = new Map<number, (m: any) => void>();
  const c = start(dir, ORIGIN, (_client, json) => {
    const m = JSON.parse(json);
    if (typeof m.id === "number" && ("ok" in m || "error" in m)) waiting.get(m.id)?.(m), waiting.delete(m.id);
  });
  const ui = c.connect();
  let next = 1;
  const call = (name: string, params: unknown) =>
    new Promise<any>((resolve, reject) => {
      const id = next++;
      waiting.set(id, (m) => ("ok" in m ? resolve(m.ok) : reject(Object.assign(new Error(m.error?.message ?? JSON.stringify(m.error)), { code: m.error?.code }))));
      c.receive(ui, JSON.stringify({ kind: "call", id, call: name, params }));
    });
  c.receive(ui, JSON.stringify({ kind: "call", id: 0, call: "client.device", params: { app: "desktop", build: "e2e", userAgent: "Mac OS X", locale: "zh-CN" } }));
  return { call, close: () => c.close() };
}

// ── the run ──

/// This run's stations (and those a run before left), by their data directories.
function stopStations() {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}

async function main() {
  stopStations();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(WORK, { recursive: true });
  say("dev cloud, three stations");
  await startCloud();
  const alice = await account("alice");
  const bob = await account("bob");
  const ws = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const enrollment = async (name: string) => enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name })).command);
  const A = makeStation("locked-a", await enrollment("locked-a"));
  const C = makeStation("locked-c", await enrollment("locked-c"));
  const B = makeStation("unlocked-b", await enrollment("unlocked-b"));
  for (const s of [A, B, C]) run(s);
  const online = (s: Station) => JSON.parse(readFileSync(join(s.data, "run/presence.json"), "utf8")).online === true;
  for (const s of [A, B, C]) await until(async () => online(s), `${s.name} online`);

  say("the owner's desktop app turns the lock on, leaving unlocked-b and a laptop of alice's (connected to locked-a) out");
  const owner = core("owner");
  // Each core signed in on its own: a session's refresh token is one device's (one core refreshing it signs out the
  // others, and this script's own calls).
  await owner.call("migrate", { accounts: [await account("alice")] });
  await until(async () => (await owner.call("lock.state", { workspace: ws })).me.device, "owner core up");
  const laptop = core("laptop");
  await laptop.call("migrate", { accounts: [await account("alice")] });
  const laptopId = await until(async () => (await laptop.call("lock.state", { workspace: ws })).me.device, "laptop core up");
  const laptopIn = await laptop.call("tools.access", { station: `${ws}/${A.id}` }).then(() => "admitted", (e) => `refused: ${e.message}`);
  // The draft as the owner's page has it, unlocked-b and the laptop unticked.
  await until(async () => (await owner.call("lock.state", { workspace: ws })) && true, "state");
  await owner.call("lock.toggle", { workspace: ws, id: B.id });
  await owner.call("lock.toggle", { workspace: ws, id: laptopId });
  const opened = await until(async () => owner.call("lock.open", { workspace: ws }).catch((e) => (console.log("  open:", e.message), null)), "lock.open", 30);
  console.log(`  opened: entry ${opened.head.seq}, ${opened.members} members, ${opened.devices} devices, stations ${opened.stations.map((x: any) => x.name).join(", ")}`);
  for (const s of [A, C]) await until(async () => JSON.parse(readFileSync(join(s.data, "mesh/lock.json"), "utf8")).entries.length > 0, `${s.name} pinned`);
  const lockLine = (st: Station) => status(st).split("\n").find((l) => /安全模式：|Security mode:/.test(l)) ?? "(no lock line)";
  check("lock pinned on the stations it names", `${A.name}: ${lockLine(A)}; ${C.name}: ${lockLine(C)}`, `${B.name}: ${lockLine(B)}`, /安全模式：已开启|Security mode: on/.test(lockLine(A)) && /安全模式：已开启|Security mode: on/.test(lockLine(C)) && !/安全模式：已开启|Security mode: on/.test(lockLine(B)));
  // The owner's own device still gets in (its claim is in its hello).
  const ownerIn = await owner.call("tools.access", { station: `${ws}/${A.id}` }).then(() => "admitted", (e) => `refused: ${e.message}`);
  check("the owner's own device", `${A.name}: ${ownerIn}`, "-", ownerIn === "admitted");
  // The laptop, left out while connected, asks to be trusted as it reads the lock: nothing it does, no restart.
  const laptopAsked = await until(async () => (await owner.call("lock.state", { workspace: ws })).requests.some((r: any) => r.device === laptopId), "the laptop asked by itself", 100).then(() => true, () => false);
  const laptopWaits = (await laptop.call("lock.state", { workspace: ws })).me.waiting === true;
  check("a device left out while connected asks by itself", `laptop: before ${laptopIn}; listed for the owner ${laptopAsked}, waiting ${laptopWaits}`, "-", laptopIn === "admitted" && laptopAsked && laptopWaits);
  // Turned down: it says so and asks again by hand. Turned down again, so the phone below is the one put up.
  if (laptopAsked) await owner.call("lock.deny", { workspace: ws, device: laptopId });
  const deniedSays = await until(async () => ((await laptop.call("lock.state", { workspace: ws })).me.asked === false ? "not asked" : null), "the laptop sees it turned down", 50).catch(() => "still asked");
  await laptop.call("lock.request", { workspace: ws });
  const askedAgain = await until(async () => (await owner.call("lock.state", { workspace: ws })).requests.some((r: any) => r.device === laptopId), "the laptop asked again", 50).then(() => true, () => false);
  const laptopSays = (await laptop.call("lock.state", { workspace: ws })).me;
  check("turned down, it asks again by hand", `laptop: after deny ${deniedSays}; asked again ${askedAgain}, asked ${laptopSays.asked}, waiting ${laptopSays.waiting}`, "-", deniedSays === "not asked" && askedAgain && laptopSays.asked === true && laptopSays.waiting === true);
  await owner.call("lock.deny", { workspace: ws, device: laptopId });
  await until(async () => (await laptop.call("lock.state", { workspace: ws })).me.asked === false, "the laptop sees it turned down again", 50).catch(() => false);

  say("a new device of alice's: waits, asks, the owner compares its code and confirms it");
  await nextMinute();
  const phone = core("phone");
  await phone.call("migrate", { accounts: [await account("alice")] });
  await until(async () => (await phone.call("lock.state", { workspace: ws })).me.device, "phone core up");
  const waits = await phone.call("tools.access", { station: `${ws}/${A.id}` }).then(() => "admitted", (e) => `${e.code}: ${e.message}`);
  const asked = await phone.call("lock.request", { workspace: ws });
  const listed = await until(async () => (await owner.call("lock.state", { workspace: ws })).requests.find((r: any) => r.device === asked.device), "request listed");
  // Put up by itself on the owner's signing device, once.
  const prompted = (await owner.call("lock.state", { workspace: ws })).prompt?.device === asked.device;
  await owner.call("lock.shown", { workspace: ws, device: asked.device });
  const promptedAgain = (await owner.call("lock.state", { workspace: ws })).prompt?.device === asked.device;
  const wrong = await owner.call("lock.confirm", { workspace: ws, device: asked.device, code: "AAA-AAA" }).then(() => "confirmed", (e) => `refused: ${e.message}`);
  await owner.call("lock.confirm", { workspace: ws, device: asked.device, code: listed.code });
  const after = await until(async () => phone.call("tools.access", { station: `${ws}/${A.id}` }).then(() => "admitted", () => null), "phone admitted", 50);
  // The lock moved on (the phone's entry): the laptop, turned down, does not ask by itself again.
  await until(async () => (await laptop.call("lock.state", { workspace: ws })).members.some((m: any) => m.devices.some((d: any) => d.id === asked.device)), "the laptop read the phone's entry", 50).catch(() => false);
  let laptopBack = false;
  for (let i = 0; i < 15 && !laptopBack; i++) {
    laptopBack = (await owner.call("lock.state", { workspace: ws })).requests.some((r: any) => r.device === laptopId);
    await new Promise((r) => setTimeout(r, 200));
  }
  const laptopAfter = (await laptop.call("lock.state", { workspace: ws })).me;
  check("turned down, it does not ask by itself when the lock moves on", `laptop: listed again ${laptopBack}; asked ${laptopAfter.asked}, waiting ${laptopAfter.waiting}`, "-", !laptopBack && laptopAfter.asked === false && laptopAfter.waiting === true);
  laptop.close();
  check("a new device: refused, asks, confirmed by its code", `${A.name}: before ${waits}; code on the phone ${asked.code}, listed for the owner ${listed?.code}, put up ${prompted ? "once" : "never"}${promptedAgain ? " and again" : ""}; a wrong code ${wrong}; after ${after}`, "-", waits.startsWith("lock_unconfirmed") && asked.code === listed?.code && prompted && !promptedAgain && wrong.startsWith("refused") && after === "admitted");

  say("a new station joins with the lock's hash and is confirmed by the code it printed");
  await nextMinute();
  const made = await owner.call("workspace.enroll", { account: alice.sub, workspace: ws, name: "joined-d" });
  const D = makeStation("joined-d", enrollArgs(made.command));
  run(D);
  await until(async () => online(D), "joined-d online");
  await until(async () => JSON.parse(readFileSync(join(D.data, "mesh/lock.json"), "utf8")).entries.length > 0, "joined-d pinned");
  const printed = /(?:安全码为|security code) ([A-Z0-9]{3}-[A-Z0-9]{3})/.exec(D.enrolled)?.[1] ?? "";
  await owner.call("lock.addStation", { workspace: ws, station: D.id, code: printed });
  await until(async () => stationState(A).peers.some((p: any) => p.id === D.id) && stationState(D).peers.some((p: any) => p.id === A.id), "joined-d in the rosters");
  check("a station enrolled with the lock, confirmed by its code", `command ends ${made.command.split(" ").slice(-2).join(" ").slice(0, 24)}…; printed ${printed}; ${D.name}: ${lockLine(D)}; in ${A.name}'s roster`, "-", made.command.includes("--lock") && printed !== "");

  say("1. the cloud mints a credential for a device of its own (as the owner)");
  const intruderDevice = await endpointOf(randomBytes(32), ALPN);
  const cred = await credentialFor(alice, ws, intruderDevice.id());
  const onA = await asDevice(intruderDevice, A.id, cred);
  const onB = await asDevice(intruderDevice, B.id, cred);
  check("a device the cloud made up, credential as the owner", `${A.name}: ${said(onA)}`, `${B.name}: ${said(onB)}`, !onA.hello?.ok && onA.hello?.code === "lock_unconfirmed" && onB.hello?.ok && onB.overview === 200);

  say("2. the cloud puts a station of its own in the roster");
  const evilSeed = randomBytes(32);
  const evilKey = new StationKey(evilSeed);
  const t = (await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "intruder" })).token as string;
  await fetch(`${ORIGIN}/v1/stations/enroll`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ token: t, station: evilKey.id, signature: evilKey.sign(`stillfail-station-enroll-v1:${ORIGIN}:${t}:${evilKey.id}`), version: "9" }) });
  for (const s of [A, B]) await until(async () => (await api(alice, "GET", `/v1/workspaces/${ws}`)).stations.some((x: any) => x.id === evilKey.id) && true, "intruder in the roster");
  // Each station's roster as it keeps it, once the cloud's new one came.
  await until(async () => stationState(B).peers.some((p: any) => p.id === evilKey.id), "unlocked-b heard the roster");
  const evilEndpoint = await endpointOf(evilSeed, PEER_ALPN);
  // Its own cloud.json, read as a station reads one (Cloud's own memberships).
  const evilCloud = Object.assign(Object.create(Cloud.prototype), { state: { workspace: ws, workspace_name: "", name: "", station: evilKey.id, peers: [{ id: A.id }, { id: B.id }], revocations: [] }, lock: null, peersCurrent: true, relays: () => [RELAY] });
  const asPeer = peerCall(evilEndpoint, evilCloud);
  const ask = (id: string) => asPeer(id, ws, { method: "task.prepare", session: "s", key: "k", spec: { command: "id" } }).then((r) => `answered ${JSON.stringify(r)}`, (e) => `refused: ${e.message}`);
  const peerA = await ask(A.id);
  const peerB = await ask(B.id);
  check("a station of the cloud's own, calling task.prepare (runs a command)", `${A.name}: roster ${stationState(A).peers.map((p: any) => p.id.slice(0, 6)).join(",")}; ${peerA}`, `${B.name}: roster has it; ${peerB}`, peerA.startsWith("refused") && peerB.startsWith("answered") && !stationState(A).peers.some((p: any) => p.id === evilKey.id));

  say("3. the cloud moves the stations into a workspace of bob's");
  const evilWs = (await api(bob, "POST", "/v1/workspaces", { name: "Evil" })).id as string;
  const move = async (s: Station) => {
    const token = (await api(bob, "POST", `/v1/workspaces/${evilWs}/enrollments`, { name: s.name })).token as string;
    await fetch(`${ORIGIN}/__dev/move?station=${s.id}&token=${token}`);
  };
  await move(A);
  await move(B);
  await until(async () => stationState(B).workspace === evilWs, "unlocked-b moved");
  const bobDevice = await endpointOf(randomBytes(32), ALPN);
  const bobCred = await credentialFor(bob, evilWs, bobDevice.id());
  const mA = await asDevice(bobDevice, A.id, bobCred);
  const mB = await asDevice(bobDevice, B.id, bobCred);
  check("moved, then bob (the new workspace's owner) connects", `${A.name}: workspace ${stationState(A).workspace === ws ? "still Dev" : stationState(A).workspace}; ${said(mA)}`, `${B.name}: workspace ${stationState(B).workspace === evilWs ? "now Evil" : "?"}; ${said(mB)}`, stationState(A).workspace === ws && !mA.hello?.ok && mB.hello?.ok === true);

  say("4. the cloud swaps its grant key (a restart of the dev cloud makes a new one)");
  await nextMinute();
  const before = stationState(A).grant_keys.keys[0].x;
  await stopCloud();
  await startCloud();
  await until(async () => stationState(B).grant_keys.keys[0].x !== before && stationState(A).grant_keys.keys[0].x !== before, "the stations heard the new key");
  const swapped = await credentialFor(alice, ws, intruderDevice.id());
  const kA = await asDevice(intruderDevice, A.id, swapped);
  // unlocked-b is bob's now: bob's credential, from the new key.
  const kB = await asDevice(bobDevice, B.id, await credentialFor(bob, evilWs, bobDevice.id()));
  check("a credential signed with the cloud's new key", `${A.name}: ${said(kA)}`, `${B.name}: ${said(kB)}`, !kA.hello?.ok && /credential/.test(kA.hello?.error ?? "") && kB.hello?.ok === true);

  say("5. unlocked-b, updated, is taken in by the owner afterwards");
  // Back in Dev first (the move above was the cloud's doing): the owner enrolls it again on its machine.
  const back = enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "unlocked-b" })).command);
  execFileSync(native("launcher"), ["enroll", ...back, "--app", join(B.data, "../app"), "--data", B.data], { env: env() });
  await until(async () => stationState(B).workspace === ws && online(B), "unlocked-b back in Dev");
  const joined = await owner.call("lock.joinStation", { workspace: ws, station: B.id }).then(() => "joined", (e: Error) => `refused: ${e.message}`);
  await until(async () => /安全模式：已开启|Security mode: on/.test(lockLine(B)), "unlocked-b pinned", 60).catch(() => null);
  check("an existing station taken in later", `${B.name}: ${joined}; ${lockLine(B)}`, "-", joined === "joined" && /安全模式：已开启|Security mode: on/.test(lockLine(B)));

  say("summary");
  console.table(results.map((r) => ({ check: r.check, ok: r.ok ? "PASS" : "FAIL" })));
  owner.close();
  phone.close();
  await Promise.all([intruderDevice.close(), evilEndpoint.close(), bobDevice.close()]);
  return results.every((r) => r.ok);
}

let ok = false;
try {
  ok = await main();
} catch (e) {
  console.error("e2e stopped:", e);
} finally {
  await stopCloud();
  stopStations();
}
process.exit(ok ? 0 : 1);
