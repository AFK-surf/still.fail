// A station in security mode joins a workspace also in it, end to end (docs/multi-workspace.md, docs/workspace-lock.md),
// on a dev cloud (cloud/test/dev.ts), a real station and the owner's real core (desktop's Node host): alice locks her
// workspace Dev, whose station pins that lock; she locks Lab too and adds the station to it from her app (station.join):
// the station pins Lab's lock there, is taken into it by her signature, and her device reaches it in Lab; joining an
// unlocked workspace is refused, and nothing of it is taken.
//
//   node station/side/multi-workspace-lock-e2e.ts   (a worktree with `pnpm run build` done in station/ and
//                                                    `pnpm run build:cloud` at the top, the iroh dev relay on :3340;
//                                                    PORT, default 8877, and PORT+1..+4 free)
//
// It prints a line per check and a table at the end, and exits 1 if any check failed. Real processes and a real relay:
// a side test (scripts/side.sh), not one of the deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, openSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const CORE = "../../client/core-ts/src/hosts/node.ts";
const { start } = (await import(CORE)) as { start: (dir: string, origin: string, listener: (client: number, json: string) => void) => { connect(): number; receive(client: number, json: string): void; close(): Promise<void> } };

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8877);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/multi-workspace-lock-e2e";

const results: { check: string; saw: string; ok: boolean }[] = [];
const say = (s: string) => console.log(`\n== ${s}`);
function check(name: string, saw: string, ok: boolean) {
  results.push({ check: name, saw, ok });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}\n     ${saw}`);
}
const native = (what: string) => execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", what], { encoding: "utf8" }).trim();
process.env.STILLFAIL_MESH_NATIVE ??= native("mesh");
const until = async <T>(what: () => Promise<T | null | undefined | false>, label: string, tries = 300): Promise<T> => {
  for (let i = 0; i < tries; i++) {
    const v = await what().catch(() => null);
    if (v) return v;
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error(`gave up waiting: ${label}`);
};

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
async function api(who: Account, method: string, path: string, body?: unknown): Promise<any> {
  const r = await fetch(`${ORIGIN}${path}`, { method, headers: { authorization: `Bearer ${who.access}`, "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

const env = () => ({ ...process.env, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") });
const dir = join(WORK, "station");
const data = join(dir, "data");
const app = join(dir, "app");
const state = () => JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8"));
const online = () => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true;
const enrollArgs = (command: string) => command.split(" ").slice(3);
/// The lock this station pinned in a workspace it joined (none: null).
const joinedLock = (ws: string): any[] | null => {
  const path = join(data, "mesh/locks", `${ws}.json`);
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")).entries : null;
};
function stopStation() {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}

function core(name: string) {
  const at = join(WORK, `core-${name}`);
  rmSync(at, { recursive: true, force: true });
  mkdirSync(at, { recursive: true });
  const waiting = new Map<number, (m: any) => void>();
  const c = start(at, ORIGIN, (_client, json) => {
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

async function main() {
  stopStation();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(WORK, { recursive: true });
  say("dev cloud; alice's station in Dev; workspaces Lab and Open");
  await startCloud();
  const alice = await account("alice");
  const dev = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const lab = (await api(alice, "POST", "/v1/workspaces", { name: "Lab" })).id as string;
  const open = (await api(alice, "POST", "/v1/workspaces", { name: "Open" })).id as string;
  mkdirSync(join(app, "node/bin"), { recursive: true });
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  execFileSync(native("launcher"), ["enroll", ...enrollArgs((await api(alice, "POST", `/v1/workspaces/${dev}/enrollments`, { name: "studio" })).command), "--app", app, "--data", data], { env: env() });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
  const station = state().station as string;
  spawn(native("launcher"), ["run", "--app", app, "--data", data], { env: env(), stdio: ["ignore", openSync(join(dir, "station.log"), "a"), openSync(join(dir, "station.log"), "a")] });
  await until(async () => online(), "station online");

  say("alice locks Dev (the station pins it) and Lab");
  const owner = core("owner");
  await owner.call("migrate", { accounts: [alice] });
  await until(async () => (await owner.call("lock.state", { workspace: dev })).me.device, "owner core up");
  await until(async () => owner.call("lock.open", { workspace: dev }).catch((e) => (console.log("  open Dev:", e.message), null)), "lock Dev", 30);
  await until(async () => JSON.parse(readFileSync(join(data, "mesh/lock.json"), "utf8")).entries.length > 0, "Dev pinned");
  await until(async () => (await owner.call("lock.state", { workspace: lab })).me.device, "Lab's lock state");
  const labOpened = await until(async () => owner.call("lock.open", { workspace: lab }).catch((e) => (console.log("  open Lab:", e.message), null)), "lock Lab", 30);
  check("both in security mode", `Dev pinned on the station; Lab's lock entry ${labOpened?.head?.seq}`, labOpened?.head?.seq === 0);

  say("joining Open (no lock): refused, nothing taken");
  const refused = await owner.call("station.join", { workspace: open, station: `${dev}/${station}` }).then(() => "joined", (e: Error) => e.message);
  await new Promise((r) => setTimeout(r, 1500));
  const openStations = (await api(alice, "GET", `/v1/workspaces/${open}`)).stations.length;
  check("a locked station joins no unlocked workspace", `said: ${refused}; Open's stations: ${openStations}; joined in cloud.json: ${JSON.stringify((state().joined ?? []).map((j: any) => j.workspace_name))}`, refused !== "joined" && /安全模式|security mode/.test(refused) && openStations === 0);

  say("joining Lab (locked): pinned there, taken into its lock, reached in it");
  const joined = await owner.call("station.join", { workspace: lab, station: `${dev}/${station}` }).then((r) => JSON.stringify(r), (e: Error) => `refused: ${e.message}`);
  const entries = await until(async () => {
    const e = joinedLock(lab);
    return e && e.some((x: any) => x.kind === "station" && x.body?.key === station) ? e : null;
  }, "Lab's lock pinned with the station in it", 150).catch(() => joinedLock(lab));
  const inLock = entries?.some((x: any) => x.kind === "station" && x.body?.key === station) ?? false;
  const reached = await until(async () => owner.call("tools.access", { station: `${lab}/${station}` }).then(() => "admitted", () => null), "reached in Lab", 100).catch(async () => owner.call("tools.access", { station: `${lab}/${station}` }).then(() => "admitted", (e: Error) => `refused: ${e.message}`));
  const home = await owner.call("tools.access", { station: `${dev}/${station}` }).then(() => "admitted", (e: Error) => `refused: ${e.message}`);
  check("pinned in Lab, in its lock, reached there and at home", `join: ${joined}; Lab's lock here: ${entries ? `${entries.length} entries` : "none"}, the station in it: ${inLock}; Lab: ${reached}; Dev: ${home}; lock files: ${readdirSync(join(data, "mesh/locks")).join(",")}`, inLock && reached === "admitted" && home === "admitted");

  say("summary");
  console.table(results.map((r) => ({ check: r.check, ok: r.ok ? "PASS" : "FAIL" })));
  await owner.close();
  return results.every((r) => r.ok);
}

let ok = false;
try {
  ok = await main();
} catch (e) {
  console.error("e2e stopped:", e);
} finally {
  (cloud as ChildProcess | null)?.kill();
  stopStation();
}
process.exit(ok ? 0 : 1);
