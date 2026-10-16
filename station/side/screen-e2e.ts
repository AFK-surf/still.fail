// The desktop as a screen end to end on a Mac (docs/remote-screens.md): a dev cloud (cloud/test/dev.ts), a station
// of this checkout started as launchd starts one (a job in the GUI session running the launcher itself), still.fail
// Helper started by it, and a member's device on iroh asking for the desktop. A missing grant puts the helper's window
// up on this Mac; this waits (WAIT seconds, default 1800) for a person to grant it there, then measures a still and a
// moving screen (the pointer driven over the view), and keeps the first decoded frame of each as a PNG.
//
//   node station/side/screen-e2e.ts    (a worktree with `pnpm run build` done in station/ and `pnpm run build:cloud`
//                                       at the top, the iroh dev relay on :3340; PORT, default 8897, and PORT+1..+4
//                                       free; run where the person is logged in: the job goes in their GUI session)
//
// LAUNCHER: the launcher to run (default the prebuilt one); STILLFAIL_HELPER: the helper app to give the station (a
// signed one keeps its grant across builds: verify.md); REBUILT: another build of it, signed the same way, put in its
// place after the measurement, to see the grant kept (the station copies it in and starts it anew); WORK: where all
// of it goes (default /tmp/screen-e2e). Real processes, a person's grant: a side script, not a test.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { type Connection, type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { FrameIn, KIND, frame } from "../src/mesh/screens.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HELPER_APP } from "../src/helper/app.ts";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8897);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/screen-e2e";
const WAIT = Number(process.env.WAIT ?? 1800);
const SECONDS = Number(process.env.SCREEN_SECONDS ?? 5);
const LABEL = "dev.ember.screen-e2e";
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

// ── the cloud ──

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

// ── the station, as launchd runs one ──

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

// ── a member's device ──

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
async function screens(conn: Connection): Promise<any[]> {
  const s = await conn.openBi();
  await writeLine(s, { method: "GET", path: "/admin/api/screens", headers: { "stillfail-lang": "zh" } });
  await s.finish();
  const r = new Reader(s);
  const head = await r.line();
  if (head?.status !== 200) throw new Error(`GET /screens: ${head?.status}`);
  return JSON.parse((await r.rest()).toString()).screens;
}

function annexB(avcC: Buffer): Buffer[] {
  const out: Buffer[] = [];
  let at = 6;
  for (let i = 0, n = avcC[5]! & 31; i < n; i++, at += 2 + avcC.readUInt16BE(at)) out.push(Buffer.from([0, 0, 0, 1]), avcC.subarray(at + 2, at + 2 + avcC.readUInt16BE(at)));
  for (let i = 0, n = avcC[at++]!; i < n; i++, at += 2 + avcC.readUInt16BE(at)) out.push(Buffer.from([0, 0, 0, 1]), avcC.subarray(at + 2, at + 2 + avcC.readUInt16BE(at)));
  return out;
}
function nals(avcc: Buffer): Buffer[] {
  const out: Buffer[] = [];
  for (let at = 0; at + 4 <= avcc.length; at += 4 + avcc.readUInt32BE(at)) out.push(Buffer.from([0, 0, 0, 1]), avcc.subarray(at + 4, at + 4 + avcc.readUInt32BE(at)));
  return out;
}

/// A view of the desktop for SECONDS, each frame acknowledged as it comes: the answer's status and error when refused,
/// else what it measured. `move`: the pointer driven around every 16 ms.
async function view(conn: Connection, label: string, move = false): Promise<{ status: number; error?: string; line?: string }> {
  const stream = await conn.openBi();
  await writeLine(stream, { method: "POST", path: "/admin/api/screens/desktop/view", headers: { "stillfail-lang": "zh" }, screen: { maxWidth: 1920, maxHeight: 1080, codecs: ["h264"], control: move } });
  const heard = new Reader(stream);
  const answer = await heard.line();
  if (answer.status !== 200) return { status: answer.status, error: JSON.parse((await heard.rest()).toString()).error };
  const frames = new FrameIn(stream, heard.carry);
  const kept: Buffer[] = [];
  let count = 0, keys = 0, bytes = 0, width = 0, height = 0, finished = false, n = 0;
  const started = performance.now();
  const mover = move
    ? setInterval(() => {
        if (!finished) stream.write(frame(KIND.input, Buffer.from(JSON.stringify({ t: "pointer", kind: "move", x: 0.5 + 0.3 * Math.sin(n / 10), y: 0.5 + 0.3 * Math.cos(n++ / 10), buttons: 0 })))).catch(() => {});
      }, 16)
    : null;
  const stop = setTimeout(() => {
    if (mover) clearInterval(mover);
    finished = true;
    void stream.finish();
  }, SECONDS * 1000);
  for (let f = await frames.next(); f !== null; f = await frames.next()) {
    if (f.kind === KIND.config) {
      const config = JSON.parse(f.payload.toString());
      ({ width, height } = config);
      kept.push(...annexB(Buffer.from(config.description, "base64")));
    } else if (f.kind === KIND.video) {
      count++;
      keys += f.payload[0]! & 1;
      bytes += f.payload.length - 9;
      kept.push(...nals(f.payload.subarray(9)));
      if (!finished) await stream.write(frame(KIND.ack, f.payload.subarray(1, 9)));
    }
  }
  clearTimeout(stop);
  const seconds = (performance.now() - started) / 1000;
  const file = join(WORK, `${label}.h264`);
  writeFileSync(file, Buffer.concat(kept));
  const png = join(WORK, `${label}.png`);
  const ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].find(existsSync);
  let decoded = "not decoded (no ffmpeg)";
  if (ffmpeg) {
    execFileSync(ffmpeg, ["-loglevel", "error", "-y", "-i", file, "-frames:v", "1", "-update", "1", png]);
    const all = execFileSync(ffmpeg, ["-loglevel", "error", "-i", file, "-f", "null", "-", "-progress", "pipe:1"], { encoding: "utf8" });
    decoded = `${/frame=(\d+)\s*\n(?![\s\S]*frame=)/.exec(all)?.[1]} decoded, first frame ${png}`;
  }
  const line = `${label} ${width}×${height} over ${conn.via()}: ${count} frames in ${seconds.toFixed(1)} s, ${(count / seconds).toFixed(1)} fps, ${((bytes * 8) / seconds / 1e6).toFixed(2)} Mbit/s, ${keys} key; ${decoded}`;
  console.log(`RESULT ${line}`);
  return { status: 200, line };
}

async function main() {
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
  const env = { HOME: process.env.HOME!, PATH: `${join(ROOT, "station/test/fake")}:/usr/bin:/bin:/usr/sbin:/sbin`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner"), STILLFAIL_HELPER: release };
  const command = (await api(alice, "POST", `/v1/workspaces/${dev}/enrollments`, { name: "screen-e2e" })).command as string;
  execFileSync(launcher, ["enroll", ...command.split(" ").slice(3), "--app", app, "--data", data], { env: { ...process.env, ...env } });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
  const station = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station as string;
  startStation(launcher, env);
  await until(async () => online(), "station online");

  say("alice's device asks for the desktop");
  const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
  await device.online();
  const credential = (await api(alice, "POST", `/v1/workspaces/${dev}/credential`, { device: device.id() })).credential as string;
  let conn = await member(device, station, credential);
  console.log(`screens: ${JSON.stringify(await screens(conn))}`);
  // Opening it asks for what is missing (the helper's window on this Mac); measured once all is granted.
  const tried = await view(conn, "display-first");
  if (tried.status !== 200) console.log(`REFUSED ${tried.status}: ${tried.error}`);
  // What the desktop lacks (null: nothing; "unknown" when the list was not read).
  const missing = async () => {
    try {
      return (await screens(conn)).find((s) => s.id === "desktop")?.access ?? null;
    } catch {
      return "unknown";
    }
  };
  if (tried.status !== 200 || (await missing()) !== null) {
    console.log(`GRANT-WAITING: the helper's window is up on this Mac; waiting up to ${WAIT} s for the grants`);
    const deadline = Date.now() + WAIT * 1000;
    for (;;) {
      if (Date.now() > deadline) throw new Error("not granted in time");
      await sleep(3000);
      if (conn.isClosed()) conn = await member(device, station, credential);
      if ((await missing()) === null) break;
    }
    console.log("GRANTED");
  }
  const first = await view(conn, "display-still");
  if (first.status !== 200) throw new Error(`still refused: ${first.error}`);
  const moving = await view(conn, "display-moving", true);
  if (moving.status !== 200) console.log(`REFUSED moving ${moving.status}: ${moving.error}`);
  if (process.env.REBUILT) {
    say("another build of the helper, signed the same way, in its place: is the grant kept?");
    rmSync(release, { recursive: true, force: true });
    cpSync(process.env.REBUILT, release, { recursive: true, verbatimSymlinks: true });
    const again = await view(conn, "display-rebuilt");
    console.log(again.status === 200 ? "REBUILT-KEPT the grant" : `REBUILT-LOST ${again.status}: ${again.error}`);
  }
  console.log(`screens after: ${JSON.stringify(await screens(conn))}`);
  conn.close(0, "done");
  await device.close();
  return true;
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
