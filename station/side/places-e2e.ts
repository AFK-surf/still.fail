// A directory in a folder macOS protects, named to a station launchd runs (src/ops/places.ts; docs/drive.md
// "Directories and files the station is given"), end to end on a Mac: a dev cloud (cloud/test/dev.ts), a station of
// this checkout started as launchd starts one (a job in the GUI session running the launcher itself; macOS keeps
// Desktop and the rest from it), still.fail Helper started by it, and a member's device on iroh. A Codex session of
// "the machine's" (a rollout under the station's CODEX_HOME) ran in ~/Desktop/<a folder of this run's>, a name only:
// nothing is made there. The member continues it in a chat (POST /machine-sessions); while the station looks at that
// directory, the member's other requests (GET /host, every 100 ms) must each answer within a second. Without the
// helper's grant for that folder the continuing is refused naming it, the helper's window comes up for it (the
// overview's `permissions.asking`), and asking again does not show it again. The helper is stopped first, so the
// station starts it again while it looks. Nobody is asked to click: the window goes
// as the station stops (the helper with it). Which folder: FOLDER (desktop, documents, downloads; default the first the
// helper has no grant for, else it stops: a grant there leaves nothing to see).
//
//   node station/side/places-e2e.ts   (a worktree with `pnpm run build` in station/ and `pnpm run build:cloud` at the
//                                     top, the iroh dev relay on :3340; PORT, default 8937, and PORT+1..+4 free; run
//                                     where the person is logged in: the job goes in their GUI session)
//
// STILLFAIL_HELPER: the helper app to give the station (a signed one keeps its grants: verify.md); WORK: where it all
// goes (default /tmp/places-e2e). Real processes and macOS's grants: a side script.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { type Connection, type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HELPER_APP } from "../src/helper/app.ts";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8937);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/places-e2e";
const LABEL = "dev.ember.places-e2e";
const native = (what: string) => execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", what], { encoding: "utf8" }).trim();
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const say = (s: string) => console.log(`\n== ${s}`);
const until = async <T>(what: () => Promise<T | null | undefined | false>, label: string, tries = 300): Promise<T> => {
  for (let i = 0; i < tries; i++) {
    const v = await what().catch(() => null);
    if (v) return v;
    await sleep(200);
  }
  throw new Error(`gave up waiting: ${label}`);
};
let failed = 0;
const check = (ok: boolean, what: string) => {
  console.log(`${ok ? "PASS" : "FAIL"} ${what}`);
  if (!ok) failed++;
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

const dir = join(WORK, "station");
const data = join(dir, "data");
const app = join(dir, "app");
const uid = () => execFileSync("id", ["-u"], { encoding: "utf8" }).trim();
const online = () => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true;
function stopStation() {
  try {
    execFileSync("launchctl", ["bootout", `gui/${uid()}/${LABEL}`], { stdio: "ignore" });
  } catch {}
  try {
    execFileSync("pkill", ["-9", "-f", `${WORK}/`], { stdio: "ignore" });
  } catch {}
}
const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
function startStation(launcher: string, env: Record<string, string>) {
  const plist = join(dir, `${LABEL}.plist`);
  writeFileSync(
    plist,
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${LABEL}</string>
<key>ProgramArguments</key><array>${[launcher, "run", "--app", app, "--data", data].map((a) => `<string>${escape(a)}</string>`).join("")}</array>
<key>EnvironmentVariables</key><dict>${Object.entries(env).map(([k, v]) => `<key>${k}</key><string>${escape(v)}</string>`).join("")}</dict>
<key>StandardOutPath</key><string>${escape(join(dir, "station.log"))}</string>
<key>StandardErrorPath</key><string>${escape(join(dir, "station.log"))}</string>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
`,
  );
  execFileSync("launchctl", ["bootstrap", `gui/${uid()}`, plist]);
}

process.env.STILLFAIL_MESH_NATIVE ??= native("mesh");
const mesh = loadMesh();
async function readLine(stream: { read(): Promise<Buffer | null> }): Promise<any> {
  let got = Buffer.alloc(0);
  for (;;) {
    const at = got.indexOf(10);
    if (at >= 0) return JSON.parse(got.subarray(0, at).toString());
    const more = await stream.read();
    if (!more) return null;
    got = Buffer.concat([got, more]);
  }
}
async function member(device: Endpoint, station: string, credential: string): Promise<Connection> {
  const conn = await device.connect({ id: station, relays: [RELAY] }, ALPN);
  const first = await conn.openBi();
  await first.write(Buffer.from(JSON.stringify({ credential, protocol: 2 }) + "\n"));
  const hello = await readLine(first);
  if (!hello?.ok) throw new Error(`not admitted: ${JSON.stringify(hello)}`);
  return conn;
}
async function ask(conn: Connection, method: string, path: string, body?: unknown): Promise<{ status: number; answer: any }> {
  const s = await conn.openBi();
  await writeLine(s, { method, path: `/admin/api${path}`, headers: { "stillfail-lang": "zh" } });
  if (body !== undefined) await s.write(Buffer.from(JSON.stringify(body)));
  await s.finish();
  const r = new Reader(s);
  const head = await r.line();
  const text = (await r.rest()).toString();
  let answer: any = text;
  try {
    answer = text ? JSON.parse(text) : null;
  } catch {}
  return { status: head?.status, answer };
}

/// `slow` asked over and over until `done` settles: each answer's time, the longest first.
async function meanwhile(conn: Connection, done: Promise<unknown>): Promise<number[]> {
  let over = false;
  void done.finally(() => (over = true));
  const times: number[] = [];
  while (!over) {
    const at = performance.now();
    const r = await Promise.race([ask(conn, "GET", "/host"), sleep(5000).then(() => null)]);
    times.push(r === null ? Infinity : performance.now() - at);
    await sleep(100);
  }
  return times.sort((a, b) => b - a);
}

/// A Codex rollout under `codex` (CODEX_HOME) that ran in `cwd`.
function rollout(codex: string, id: string, cwd: string) {
  const at = join(codex, "sessions", "2026", "10", "18");
  mkdirSync(at, { recursive: true });
  const lines = [
    { type: "session_meta", payload: { id, cwd } },
    { type: "response_item", timestamp: "2026-10-18T00:00:01.000Z", payload: { type: "message", role: "user", content: [{ type: "input_text", text: "tidy the project" }] } },
    { type: "turn_context", payload: { model: "gpt-5.5" } },
    { type: "response_item", timestamp: "2026-10-18T00:00:03.000Z", payload: { type: "message", role: "assistant", content: [{ type: "output_text", text: "Done." }] } },
  ];
  writeFileSync(join(at, `rollout-2026-10-18T00-00-00-${id}.jsonl`), lines.map((l) => `${JSON.stringify(l)}\n`).join(""));
}

const NAMES = { desktop: "Desktop", documents: "Documents", downloads: "Downloads" } as const;

async function main(): Promise<boolean> {
  stopStation();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(join(app, "node/bin"), { recursive: true });
  const launcher = process.env.LAUNCHER ?? native("launcher");
  const release = join(WORK, "release", HELPER_APP);
  cpSync(process.env.STILLFAIL_HELPER ?? native("helper"), release, { recursive: true, verbatimSymlinks: true });
  say("dev cloud, a station of this checkout in alice's workspace, run by launchd");
  await startCloud();
  const alice = await account("alice");
  const dev = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  const codex = join(WORK, "codex");
  // The person's own home: the folders macOS protects are the real ones.
  const env = { HOME: homedir(), CODEX_HOME: codex, PATH: `${join(ROOT, "station/test/fake")}:${join(process.execPath, "..")}:/usr/bin:/bin:/usr/sbin:/sbin`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner"), STILLFAIL_HELPER: release };
  const command = (await api(alice, "POST", `/v1/workspaces/${dev}/enrollments`, { name: "places-e2e" })).command as string;
  execFileSync(launcher, ["enroll", ...command.split(" ").slice(3), "--app", app, "--data", data], { env: { ...process.env, ...env } });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "codex", home: "homes/fake", models: ["gpt-5.5"] }] }));
  const station = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station as string;
  startStation(launcher, env);
  await until(async () => online(), "station online");

  const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
  await device.online();
  const credential = (await api(alice, "POST", `/v1/workspaces/${dev}/credential`, { device: device.id() })).credential as string;
  const conn = await member(device, station, credential);
  const permissions = await until(async () => (await ask(conn, "GET", "/overview")).answer?.permissions, "permissions in the overview", 150);
  console.log(`PERMISSIONS ${JSON.stringify(permissions.grants)}`);
  const state = (g: string) => permissions.grants.find((x: any) => x.grant === g)?.state;
  const grant = (process.env.FOLDER ?? (["desktop", "documents", "downloads"] as const).find((g) => state(g) !== "granted")) as keyof typeof NAMES | undefined;
  if (grant === undefined || state(grant) === "granted") {
    console.log(`the helper has the grant for ${grant ?? "every folder"}: nothing to see here`);
    return false;
  }
  const cwd = join(homedir(), NAMES[grant], `places-e2e-${randomBytes(3).toString("hex")}`, "project");
  const id = "33333333-aaaa-bbbb-cccc-000000000001";
  rollout(codex, id, cwd);

  // The helper stopped: the station starts it again while it looks, so the look is pending a while.
  try {
    execFileSync("pkill", ["-9", "-f", join(data, "helper", HELPER_APP)], { stdio: "ignore" });
  } catch {}
  await sleep(500);
  say(`continuing a session that ran in ${cwd} (${grant}: ${state(grant)}), still.fail Helper stopped first`);
  const started = performance.now();
  const continuing = ask(conn, "POST", "/machine-sessions", { runtime: "codex", id });
  const times = await meanwhile(conn, continuing);
  const answer = await continuing;
  console.log(`ANSWER ${answer.status} after ${Math.round(performance.now() - started)} ms: ${JSON.stringify(answer.answer)}`);
  console.log(`MEANWHILE ${times.length} GET /host, slowest ${times.slice(0, 3).map((t) => Math.round(t)).join(", ")} ms`);
  check(times.length > 0 && times[0]! < 1000, "the station answered every other request within a second meanwhile");
  const error = String(answer.answer?.error ?? "");
  check(answer.status === 400 && error.includes(`「${{ desktop: "桌面", documents: "文稿", downloads: "下载" }[grant]}」`) && error.includes(cwd), "refused, naming the folder and the directory");
  const asking = await until(async () => {
    const p = (await ask(conn, "GET", "/overview")).answer?.permissions;
    return p?.asking?.includes(grant) ? p.asking : null;
  }, "the window said to be up", 50).catch(() => null);
  check(asking !== null, `the helper's window is up for ${grant} (${JSON.stringify(asking)})`);
  const again = await ask(conn, "POST", "/machine-sessions", { runtime: "codex", id });
  console.log(`AGAIN ${again.status}: ${JSON.stringify(again.answer)}`);
  check(again.status === 400 && String(again.answer?.error).includes(cwd), "asked again: refused the same way, the window left as it is");
  // Nothing of this is looked at from here either: this process is the station's launcher's as much as the station is.
  const log = readFileSync(join(dir, "station.log"), "utf8");
  console.log(`station log:\n${log.split("\n").filter((l) => / places: | helper: /.test(l)).join("\n") || "(nothing of places or the helper)"}`);
  conn.close(0, "done");
  await device.close();
  return failed === 0;
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
console.log(ok ? "\nE2E OK" : "\nE2E FAILED");
process.exit(ok ? 0 : 1);
