// The drive's protected folders end to end on a Mac (docs/drive.md): a dev cloud (cloud/test/dev.ts), a station of
// this checkout started as launchd starts one (a job in the GUI session running the launcher itself; macOS keeps
// Documents from it), still.fail Helper started by it, and a member's device on iroh using the drive in ~/Documents:
// a folder of its own there (made by this script, removed at the end), pinned, listed, a file read whole and in part,
// one uploaded in parts, renamed, removed. Without the grant the helper's window is up on this Mac; this waits (WAIT
// seconds, default 1800) for a person to allow it there, then goes on.
//
//   node station/side/drive-e2e.ts    (a worktree with `pnpm run build` done in station/ and `pnpm run build:cloud`
//                                      at the top, the iroh dev relay on :3340; PORT, default 8917, and PORT+1..+4
//                                      free; run where the person is logged in: the job goes in their GUI session)
//
// LAUNCHER: the launcher to run (default the prebuilt one); STILLFAIL_HELPER: the helper app to give the station (a
// signed one keeps its grant across builds: verify.md); WORK: where the station goes (default /tmp/drive-e2e). Real
// processes, a person's grant: a side script, not a test.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { type Connection, type Endpoint, loadMesh } from "../src/mesh/native.ts";
import { ALPN, Reader, writeLine } from "../src/mesh/serve.ts";
import { HELPER_APP } from "../src/helper/app.ts";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8917);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/drive-e2e";
const WAIT = Number(process.env.WAIT ?? 1800);
const LABEL = "dev.ember.drive-e2e";
const DOCS = join(homedir(), "Documents");
const FOLDER = `stillfail-drive-e2e-${randomBytes(3).toString("hex")}`;
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
const check = (ok: boolean, what: string) => {
  console.log(`${ok ? "OK" : "FAILED"} ${what}`);
  if (!ok) throw new Error(what);
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
/// One request of the admin API on its own stream: its status, headers and body.
async function ask(conn: Connection, method: string, path: string, query: Record<string, string> = {}, body?: Buffer | unknown): Promise<{ status: number; headers: Record<string, string>; body: Buffer; json: any }> {
  const s = await conn.openBi();
  const q = new URLSearchParams(query).toString();
  await writeLine(s, { method, path: `/admin/api${path}${q ? `?${q}` : ""}`, headers: { "stillfail-lang": "zh" } });
  if (body !== undefined) await s.write(Buffer.isBuffer(body) ? body : Buffer.from(JSON.stringify(body)));
  await s.finish();
  const r = new Reader(s);
  const head = await r.line();
  const rest = await r.rest();
  let json = null;
  try {
    json = JSON.parse(rest.toString());
  } catch {}
  return { status: head.status, headers: head.headers ?? {}, body: rest, json };
}

async function main() {
  stopStation();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(join(app, "node/bin"), { recursive: true });
  const launcher = process.env.LAUNCHER ?? native("launcher");
  const release = join(WORK, "release", HELPER_APP);
  cpSync(process.env.STILLFAIL_HELPER ?? native("helper"), release, { recursive: true, verbatimSymlinks: true });
  // A folder of this run's own in Documents, written by this process (not the station), removed at the end.
  const mine = join(DOCS, FOLDER);
  const big = randomBytes(3 * 1024 * 1024 + 7);
  mkdirSync(mine);
  writeFileSync(join(mine, "hello.txt"), "hello from Documents\n");
  writeFileSync(join(mine, "big.bin"), big);
  try {
    say("dev cloud, a station of this checkout in alice's workspace, run as launchd runs one");
    await startCloud();
    const alice = await account("alice");
    const dev = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
    symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
    symlinkSync(process.execPath, join(app, "node/bin/node"));
    mkdirSync(join(data, "homes/fake"), { recursive: true });
    const env = { HOME: process.env.HOME!, PATH: `${join(ROOT, "station/test/fake")}:/usr/bin:/bin:/usr/sbin:/sbin`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner"), STILLFAIL_HELPER: release };
    const command = (await api(alice, "POST", `/v1/workspaces/${dev}/enrollments`, { name: "drive-e2e" })).command as string;
    execFileSync(launcher, ["enroll", ...command.split(" ").slice(3), "--app", app, "--data", data], { env: { ...process.env, ...env } });
    writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
    writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
    const station = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station as string;
    startStation(launcher, env);
    await until(async () => online(), "station online");

    say("alice's device opens Documents in the drive");
    const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
    await device.online();
    const credential = (await api(alice, "POST", `/v1/workspaces/${dev}/credential`, { device: device.id() })).credential as string;
    let conn = await member(device, station, credential);
    // Opened by a member who reaches every folder (not pinned yet: pinning one looks at it through the helper too).
    const list = () => ask(conn, "GET", "/drive/list", { root: mine, path: "" });
    let listed = await list();
    if (listed.status !== 200) {
      console.log(`REFUSED ${listed.status}: ${listed.json?.error}`);
      console.log(`GRANT-WAITING: the helper's window is up on this Mac; waiting up to ${WAIT} s for Documents to be allowed`);
      const deadline = Date.now() + WAIT * 1000;
      for (;;) {
        if (Date.now() > deadline) throw new Error("not granted in time");
        await sleep(3000);
        if (conn.isClosed()) conn = await member(device, station, credential);
        listed = await list().catch(() => listed);
        if (listed.status === 200) break;
      }
      console.log("GRANTED");
    }
    check(JSON.stringify(listed.json.entries.map((e: any) => e.name)) === JSON.stringify(["big.bin", "hello.txt"]), `listed ${FOLDER}: ${listed.json.entries.map((e: any) => `${e.name} ${e.size}`).join(", ")}`);
    const pinned = await ask(conn, "PUT", "/drive/roots", {}, { roots: [mine] });
    check(pinned.status === 200 && pinned.json?.roots?.[0]?.state === "ok", `pinned, its state: ${pinned.status} ${pinned.json?.roots?.[0]?.state ?? pinned.json?.error}`);
    const hello = await ask(conn, "GET", "/drive/read", { root: mine, path: "hello.txt" });
    check(hello.status === 200 && hello.body.toString() === "hello from Documents\n", `read hello.txt: ${JSON.stringify(hello.body.toString())}`);
    const t0 = performance.now();
    const whole = await ask(conn, "GET", "/drive/read", { root: mine, path: "big.bin", offset: "0", length: String(8 * 1024 * 1024) });
    check(whole.status === 200 && whole.body.equals(big), `read big.bin whole (${whole.body.length} bytes, ${(performance.now() - t0).toFixed(0)} ms)`);
    const part = await ask(conn, "GET", "/drive/read", { root: mine, path: "big.bin", offset: "1000000", length: "4096" });
    check(part.body.equals(big.subarray(1000000, 1000000 + 4096)) && part.headers["stillfail-total"] === String(big.length), "read big.bin in part");
    // Through the helper the other way: an upload in two parts, a folder made, renamed, removed.
    const up = randomBytes(1024 * 1024 + 3);
    const a = await ask(conn, "PUT", "/drive/upload", { root: mine, path: "up.bin", id: "e2e1", offset: "0", total: String(up.length) }, up.subarray(0, 600_000));
    const b = await ask(conn, "PUT", "/drive/upload", { root: mine, path: "up.bin", id: "e2e1", offset: "600000", total: String(up.length) }, up.subarray(600_000));
    check(a.json?.have === 600_000 && b.json?.entry?.size === up.length && readFileSync(join(mine, "up.bin")).equals(up), "uploaded up.bin in two parts");
    const made = await ask(conn, "POST", "/drive/mkdir", {}, { root: mine, path: "made" });
    const moved = await ask(conn, "POST", "/drive/rename", {}, { root: mine, from: "up.bin", to: "made/up.bin" });
    check(made.status === 200 && moved.json?.size === up.length, "a folder made, the upload moved into it");
    const gone = await ask(conn, "POST", "/drive/remove", {}, { root: mine, path: "made" });
    const after = await list();
    check(gone.status === 200 && JSON.stringify(after.json.entries.map((e: any) => e.name)) === JSON.stringify(["big.bin", "hello.txt"]), "removed again");
    const log = readFileSync(join(dir, "station.log"), "utf8");
    console.log(`station log mentions the helper: ${/still\.fail Helper/.test(log)}`);
    conn.close(0, "done");
    await device.close();
    return true;
  } finally {
    rmSync(mine, { recursive: true, force: true });
  }
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
