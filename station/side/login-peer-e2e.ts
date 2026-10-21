// A login on another station end to end (docs/remote-login.md, station 之间), on a dev cloud (cloud/test/dev.ts), two
// real stations and the owner's real core: an agent on station A (the fake claude's own MCP token, as a real agent calls
// the station's tools) logs station B in with `login {station: B, command}`; the command runs on B, the agent is told it
// is B's (the card carries B's key, the link is B's page), it acts only on the logins it started there, and when the
// person's step is done on B, the agent on A is told (a station notice) and its card's id is closed there.
//
//   node station/side/login-peer-e2e.ts    (from a worktree with `pnpm run build` done in station/, the iroh dev relay
//                                             on :3340; PORT, default 8907, and PORT+1..+4 free)
//
// It prints a line per check and a table at the end, and exits 1 if any check failed. Real processes and a real relay:
// a side test, not one of the deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
// The core, as the desktop app runs it: imported by its path at run time (see lock-e2e.ts).
const CORE = "../../client/core-ts/src/hosts/node.ts";
const { start } = (await import(CORE)) as {
  start: (dir: string, origin: string, listener: (client: number, json: string) => void) => { connect(): number; receive(client: number, json: string): void; close(): Promise<void> };
};

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8907);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/login-peer-e2e";
const AUTH_KEY = "login-peer-e2e-auth-key-0123456789abcdef0123456789ab";

const results: { check: string; seen: string; ok: boolean }[] = [];
const say = (s: string) => console.log(`\n== ${s}`);
function check(name: string, seen: string, ok: boolean) {
  results.push({ check: name, seen, ok });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}\n     ${seen}`);
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

// ── the stations: the fake claude, and on B a login command that waits for the person's step (a file made) ──

const bin = join(WORK, "bin");
const approved = join(WORK, "approved");
const env = () => ({ ...process.env, PATH: `${bin}:${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner"), FAKE_DUMP: join(WORK, "claude.dump") });
type Station = { name: string; data: string; id: string };
function makeStation(name: string, enroll: string[]): Station {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, "app/node/bin"), { recursive: true });
  mkdirSync(join(dir, "data/homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(dir, "app/station"));
  symlinkSync(process.execPath, join(dir, "app/node/bin/node"));
  execFileSync(native("launcher"), ["enroll", ...enroll, "--app", join(dir, "app"), "--data", join(dir, "data")], { env: env(), encoding: "utf8" });
  writeFileSync(join(dir, "data/config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(dir, "data/homes/fake/.credentials.json"), "{}");
  const id = JSON.parse(readFileSync(join(dir, "data/mesh/cloud.json"), "utf8")).station as string;
  return { name, data: join(dir, "data"), id };
}
function run(s: Station) {
  const log = openSync(join(s.data, "../station.log"), "a");
  spawn(native("launcher"), ["run", "--app", join(s.data, "../app"), "--data", s.data], { env: env(), stdio: ["ignore", log, log] });
}

// ── the owner's core ──

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

// ── an agent: station A's MCP endpoint with the session's token, as the fake claude was given them ──

function agent() {
  const lines = readFileSync(join(WORK, "claude.dump"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
  const last = lines.at(-1);
  const config = JSON.parse(last.argv[last.argv.indexOf("--mcp-config") + 1]);
  const url = Object.values(config.mcpServers as Record<string, { url: string }>)[0]!.url;
  const token = last.env.STILLFAIL_MCP_TOKEN as string;
  let id = 1;
  return async (name: string, args: Record<string, unknown>): Promise<{ text: string; error: boolean }> => {
    const r = await fetch(url, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: id++, method: "tools/call", params: { name, arguments: args } }) });
    const body = (await r.json()) as any;
    if (body.error) return { text: body.error.message, error: true };
    return { text: body.result.content.map((c: any) => c.text).join("\n"), error: body.result.isError === true };
  };
}
const told = () => (existsSync(join(WORK, "claude.dump.stdin")) ? readFileSync(join(WORK, "claude.dump.stdin"), "utf8") : "");

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
  mkdirSync(bin, { recursive: true });
  // A device-code login, as gh says one: a code, its page opened, then waiting for the person.
  writeFileSync(join(bin, "fakelogin"), `#!/bin/sh\necho "! First copy your one-time code: 1A2B-C3D4"\n"$BROWSER" https://github.com/login/device\necho "Waiting for the browser"\nwhile [ ! -f "${approved}" ]; do sleep 0.2; done\necho "Logged in as octocat on $(hostname)"\n`);
  chmodSync(join(bin, "fakelogin"), 0o755);

  say("dev cloud, two stations, the owner's core, a chat on A");
  await startCloud();
  const alice = await account("alice");
  const ws = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const enrollArgs = (command: string) => command.split(" ").slice(3);
  const A = makeStation("login-a", enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "login-a" })).command));
  const B = makeStation("login-b", enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "login-b" })).command));
  run(A);
  run(B);
  for (const s of [A, B]) await until(async () => JSON.parse(readFileSync(join(s.data, "run/presence.json"), "utf8")).online === true, `${s.name} online`);
  const owner = core("owner");
  await owner.call("migrate", { accounts: [alice] });
  const chat = await until(async () => owner.call("chat.create", { station: `${ws}/${A.id}`, runtime: "claude", model: "claude-opus-4-1" }).catch(() => null), "chat.create", 50);
  await owner.call("chat.send", { station: `${ws}/${A.id}`, session: String(chat.key), text: "say:hello" });
  await until(async () => readFileSync(join(WORK, "claude.dump"), "utf8").includes("STILLFAIL_MCP_TOKEN"), "the agent started");
  const tool = agent();

  say("the agent on A logs B in");
  // The roster can take a moment to list B on A.
  const started = await until(async () => {
    const r = await tool("login", { station: "login-b", command: "fakelogin auth login" });
    return r.error && /not known|no station/.test(r.text) ? null : r;
  }, "the login started on B", 100);
  const id = /"id": "([0-9a-z]+)"/.exec(started.text)?.[1] ?? "";
  check("started on B: told it is B's, its card with B's key, the link B's page", started.text.replace(/\s+/g, " ").slice(0, 400),
    !started.error && started.text.includes(`"station": "${B.id}"`) && /on login-b/.test(started.text) && started.text.includes(`/s/${B.id}/login/${id}`) && !started.text.includes("1A2B-C3D4"));
  // Its page opened through B's own stand-in browser (logins/index.ts: <data>/run/logins/<id>.opened), none on A.
  const opened = (s: Station) => existsSync(join(s.data, "run/logins", `${id}.opened`));
  await until(async () => opened(B), "its page opened on B", 50).catch(() => null);
  check("the command runs on B, not on A", `opened on B: ${opened(B)}; on A: ${opened(A)}; A's run/logins: ${existsSync(join(A.data, "run/logins"))}`, opened(B) && !opened(A));
  const looked = await tool("login", { station: "login-b", id });
  check("looked at again by its id on B", looked.text.replace(/\s+/g, " ").slice(0, 200), !looked.error && looked.text.includes(`"id": "${id}"`));
  const elsewhere = await tool("login", { id });
  check("its id is no login of A's", elsewhere.text.slice(0, 120), elsewhere.error && /no login/.test(elsewhere.text));

  say("the person's step done on B: the agent on A told");
  writeFileSync(approved, "");
  const notice = await until(async () => (/The login on login-b you started or posted a card for, fakelogin auth login \(login [0-9a-z]+\), finished/.test(told()) ? told() : null), "A's agent told", 150).catch(() => "");
  check("the agent on A gets the station notice of B's login", notice ? (/The login on login-b[^\n]*/.exec(notice)?.[0] ?? "").slice(0, 200) : "no notice", notice !== "");
  const history = JSON.parse(readFileSync(join(B.data, "logins/history.json"), "utf8"));
  check("B keeps the login it ran, done", JSON.stringify(history[0] ? { state: history[0].state, command: history[0].command } : null), history[0]?.state === "done");

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
  await stopCloud();
  stopStations();
}
process.exit(ok ? 0 : 1);
