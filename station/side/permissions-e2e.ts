// still.fail Helper's grants end to end on a Mac (docs/remote-screens.md "Grants"): a dev cloud (cloud/test/dev.ts), a
// station of this checkout started as launchd starts one (a job in the GUI session), and a member's device on iroh. It
// reads the overview's `permissions` (the helper's real grants on this Mac), asks for one (GRANT, default the first
// folder not granted, else desktop) with POST /permissions/request, sees the window said to be up, and, where the
// screen can be seen, keeps a frame of the desktop with the window on it (WORK/window.jpg). Nobody is asked to click:
// the window goes as the station stops (the helper with it).
//
//   node station/side/permissions-e2e.ts   (a worktree with `pnpm run build` in station/ and `pnpm run build:cloud` at
//                                          the top, the iroh dev relay on :3340; PORT, default 8917, and PORT+1..+4
//                                          free; run where the person is logged in: the job goes in their GUI session)
//
// STILLFAIL_HELPER: the helper app to give the station (a signed one keeps its grants: verify.md); WORK: where it all
// goes (default /tmp/permissions-e2e); KEEP=1: the cloud and the station kept up after (the window too), until the
// script is stopped, for a client to be looked at against them. Real processes and macOS's grants: a side script.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Connection, type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { FrameIn, KIND, frame } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HELPER_APP } from "../src/helper/app.ts";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8917);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/permissions-e2e";
const LABEL = "dev.ember.permissions-e2e";
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
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
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
/// A request on the member's link: its status and answer.
async function ask(conn: Connection, method: string, path: string, body?: unknown): Promise<{ status: number; answer: any }> {
  const s = await conn.openBi();
  await writeLine(s, { method, path: `/admin/api${path}`, headers: { "stillfail-lang": "zh" } });
  if (body !== undefined) await s.write(Buffer.from(JSON.stringify(body)));
  await s.finish();
  const r = new Reader(s);
  const head = await r.line();
  const text = (await r.rest()).toString();
  return { status: head?.status, answer: text ? JSON.parse(text) : null };
}

/// One JPEG of the desktop (a view that only looks), as the station sends it.
async function picture(conn: Connection): Promise<Buffer | null> {
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "zh" }, screen: { maxWidth: 1920, maxHeight: 1200, codecs: ["jpeg"], control: false } });
  const heard = new Reader(stream);
  const answer = await heard.line();
  if (answer.status !== 200) {
    console.log(`view refused ${answer.status}: ${(await heard.rest()).toString()}`);
    return null;
  }
  const frames = new FrameIn(stream, heard.carry, 64 << 20);
  for (let f = await frames.next(); f !== null; f = await frames.next()) {
    if (f.kind === KIND.video) {
      await stream.write(frame(KIND.ack, f.payload.subarray(1, 9))).catch(() => {});
      void stream.finish();
      return Buffer.from(f.payload.subarray(9));
    }
  }
  return null;
}

async function main(): Promise<boolean> {
  stopStation();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(join(app, "node/bin"), { recursive: true });
  const launcher = process.env.LAUNCHER ?? native("launcher");
  const release = join(WORK, "release", HELPER_APP);
  cpSync(process.env.STILLFAIL_HELPER ?? native("helper"), release, { recursive: true, verbatimSymlinks: true });
  say("dev cloud, a station of this checkout in alice's workspace");
  await startCloud();
  const alice = await account("alice");
  const dev = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  // Its home a folder of its own (the station's node never meets a folder macOS protects); the helper has the person's.
  const home = join(WORK, "home");
  mkdirSync(join(home, "Downloads"), { recursive: true });
  const env = { HOME: home, PATH: `${join(ROOT, "station/test/fake")}:${join(process.execPath, "..")}:/usr/bin:/bin:/usr/sbin:/sbin`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner"), STILLFAIL_HELPER: release };
  const command = (await api(alice, "POST", `/v1/workspaces/${dev}/enrollments`, { name: "permissions-e2e" })).command as string;
  execFileSync(launcher, ["enroll", ...command.split(" ").slice(3), "--app", app, "--data", data], { env: { ...process.env, ...env } });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
  const station = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station as string;
  startStation(launcher, env);
  await until(async () => online(), "station online");

  say("alice's device reads the station's grants");
  const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
  await device.online();
  const credential = (await api(alice, "POST", `/v1/workspaces/${dev}/credential`, { device: device.id() })).credential as string;
  const conn = await member(device, station, credential);
  // The first read has the helper looked at; told once known.
  const permissions = await until(async () => (await ask(conn, "GET", "/overview")).answer?.permissions, "permissions in the overview", 150);
  console.log(`PERMISSIONS ${JSON.stringify(permissions)}`);
  const folder = ["desktop", "documents", "downloads"].find((g) => permissions.grants.find((x: any) => x.grant === g)?.state !== "granted");
  const grant = process.env.GRANT ?? folder ?? "desktop";

  say(`asking for ${grant}`);
  const asked = await ask(conn, "POST", "/permissions/request", { grant });
  console.log(`REQUEST ${asked.status} ${JSON.stringify(asked.answer)}`);
  const again = await ask(conn, "POST", "/permissions/request", { grant });
  console.log(`REQUEST-AGAIN ${again.status} ${JSON.stringify(again.answer)} (up already: not shown twice)`);
  if (asked.status === 200 && asked.answer.window === "up") {
    const after = await until(async () => {
      const p = (await ask(conn, "GET", "/overview")).answer?.permissions;
      return p?.asking?.includes(grant) ? p : null;
    }, "the window said to be up", 100).catch(() => null);
    console.log(after ? `ASKING ${JSON.stringify(after.asking)}` : "ASKING not said");
    if (asked.answer.screen) {
      await sleep(1500);
      const jpeg = await picture(conn);
      if (jpeg) {
        writeFileSync(join(WORK, "window.jpg"), jpeg);
        console.log(`PICTURE ${join(WORK, "window.jpg")}`);
      }
    } else console.log("the screen cannot be seen here: a person would click Allow at the Mac");
  }
  if (process.env.KEEP) {
    console.log(`KEEP cloud ${ORIGIN} workspace ${dev} station ${station}: up until this is stopped`);
    await new Promise((resolve) => process.once("SIGTERM", resolve));
  }
  conn.close(0, "done");
  await device.close();
  return asked.status === 200;
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
