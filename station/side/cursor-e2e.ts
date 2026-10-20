// Cursor as a runtime end to end (docs/cursor.md), on a dev cloud (cloud/test/dev.ts), a real station and the owner's
// real core, against the real Cursor: a chat on a Cursor profile answers through the station's tools (its instructions
// and the stillfail MCP server reached), a message sent while a command runs goes into the turn by the SDK's steer (the
// command not run again), each turn's usage is kept, and the station started again takes the session up (the agent
// remembers).
//
//   CURSOR_E2E_AUTH=<a Cursor profile's cursor/auth.json> CURSOR_E2E_SDK=<a directory with node_modules/@cursor/sdk>
//   node station/side/cursor-e2e.ts      (from a worktree with `pnpm run build` done in station/, the iroh dev relay
//                                         on :3340; PORT, default 8897, and PORT+1..+4 free)
//
// It spends the Cursor account's requests (a few turns on composer-2.5). It prints a line per check and a table at the
// end, and exits 1 if any check failed. Real processes, a real relay and Cursor: a side test, not one of the
// deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
// The core, as the desktop app runs it: imported by its path at run time (see lock-e2e.ts).
const CORE = "../../client/core-ts/src/hosts/node.ts";
const { start } = (await import(CORE)) as {
  start: (dir: string, origin: string, listener: (client: number, json: string) => void) => { connect(): number; receive(client: number, json: string): void; close(): Promise<void> };
};

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8897);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/cursor-e2e";
const AUTH_KEY = "cursor-e2e-auth-key-0123456789abcdef0123456789abcdef";
const AUTH = process.env.CURSOR_E2E_AUTH ?? "";
const SDK = process.env.CURSOR_E2E_SDK ?? "";
const MODEL = process.env.CURSOR_E2E_MODEL ?? "composer-2.5";

const results: { check: string; seen: string; ok: boolean }[] = [];
const say = (s: string) => console.log(`\n== ${s}`);
function check(name: string, seen: string, ok: boolean) {
  results.push({ check: name, seen, ok });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}\n     ${seen}`);
}
const native = (what: string) => execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", what], { encoding: "utf8" }).trim();
process.env.STILLFAIL_MESH_NATIVE ??= native("mesh");
const until = async <T>(what: () => Promise<T | null | undefined | false>, label: string, tries = 900): Promise<T> => {
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

// ── the station: a Cursor profile signed in (its auth.json), the SDK in the station's prefix (agents/cursor.ts) ──

const env = () => ({ ...process.env, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") });
type Station = { name: string; data: string; id: string };
function makeStation(name: string, enroll: string[]): Station {
  const dir = join(WORK, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(join(dir, "app/node/bin"), { recursive: true });
  mkdirSync(join(dir, "data/homes/cursor/cursor"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(dir, "app/station"));
  symlinkSync(process.execPath, join(dir, "app/node/bin/node"));
  execFileSync(native("launcher"), ["enroll", ...enroll, "--app", join(dir, "app"), "--data", join(dir, "data")], { env: env(), encoding: "utf8" });
  writeFileSync(join(dir, "data/config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "cursor", name: "Cursor", runtime: "cursor", access: { kind: "subscription" }, home: "homes/cursor", models: [MODEL] }] }));
  copyFileSync(AUTH, join(dir, "data/homes/cursor/cursor/auth.json"));
  mkdirSync(join(dir, "data/runtimes/cursor/lib"), { recursive: true });
  symlinkSync(join(SDK, "node_modules"), join(dir, "data/runtimes/cursor/lib/node_modules"));
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

// ── what the session left: the bridge's transcript, the station's record of what the agent posted ──

function transcript(s: Station): any[] {
  const dir = join(s.data, "homes/cursor/cursor/sessions");
  const file = (existsSync(dir) ? readdirSync(dir) : []).find((f) => f.endsWith(".jsonl"));
  if (!file) return [];
  return readFileSync(join(dir, file), "utf8").trim().split("\n").filter(Boolean).map((l) => JSON.parse(l));
}
const ends = (s: Station) => transcript(s).filter((l) => l.type === "end");
function posted(s: Station): string[] {
  const db = new DatabaseSync(join(s.data, "stillfail.db"), { readOnly: true });
  try {
    return (db.prepare("SELECT body FROM entries").all() as { body: string }[]).map((r) => r.body).filter((b) => b.includes('"agent"') || b.includes("chat_post"));
  } catch {
    return [];
  } finally {
    db.close();
  }
}

function stopStations() {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}

async function main() {
  if (!existsSync(AUTH) || !existsSync(join(SDK, "node_modules/@cursor/sdk/package.json"))) throw new Error("CURSOR_E2E_AUTH and CURSOR_E2E_SDK are needed (see the header)");
  stopStations();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(WORK, { recursive: true });

  say("dev cloud, a station with a Cursor profile, the owner's core");
  await startCloud();
  const alice = await account("alice");
  const ws = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const enrollArgs = (command: string) => command.split(" ").slice(3);
  const A = makeStation("cursor-a", enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "cursor-a" })).command));
  run(A);
  await until(async () => JSON.parse(readFileSync(join(A.data, "run/presence.json"), "utf8")).online === true, "station online");
  const owner = core("owner");
  await owner.call("migrate", { accounts: [alice] });
  const station = `${ws}/${A.id}`;

  say("a chat on Cursor answers in the chat, through the station's tools");
  const chat = await until(async () => owner.call("chat.create", { station, runtime: "cursor", model: MODEL }).catch((e) => (console.log("  create:", e.message), null)), "chat.create", 50);
  const session = String(chat.key);
  await owner.call("chat.send", { station, session, text: "Say pong in this chat, and nothing else." });
  await until(async () => ends(A).length >= 1, "the first turn's end");
  const first = transcript(A);
  const posts = first.filter((l) => l.type === "tool" && l.name === "mcp" && l.args?.toolName === "chat_post");
  check("the first turn ended finished", JSON.stringify(ends(A)[0]), ends(A)[0]?.status === "finished");
  check("it answered through the station's chat_post (instructions and MCP reached)", posts.map((p) => JSON.stringify(p.args?.args).slice(0, 120)).join(" | ") || "no chat_post", posts.some((p) => /pong/i.test(JSON.stringify(p.args?.args))));
  check("the post is in the chat", `${posted(A).length} entries from the agent`, posted(A).some((b) => /pong/i.test(b)));
  const usage = first.filter((l) => l.type === "usage");
  check("its usage kept", JSON.stringify(usage[0]?.usage ?? null), (usage[0]?.usage?.inputTokens ?? 0) > 0);

  say("a message while a command runs goes into the turn; the command goes on");
  await owner.call("chat.send", { station, session, text: "Run the shell command `sleep 25; echo done-sleeping` and wait for it to finish. Then post in this chat what it printed, and quote any other message I sent you meanwhile." });
  await until(async () => {
    try {
      return execFileSync("pgrep", ["-f", "sleep 25"], { encoding: "utf8" }).trim() !== "";
    } catch {
      return false;
    }
  }, "the command running");
  await owner.call("chat.send", { station, session, text: "Also say the number 4242." });
  await until(async () => ends(A).length >= 2, "the second turn's end", 1500);
  const second = transcript(A).slice(first.length);
  const sleeps = second.filter((l) => l.type === "tool" && JSON.stringify(l.args ?? {}).includes("sleep 25"));
  const steered = second.filter((l) => l.type === "user" && l.steered === true);
  const said = JSON.stringify(second.filter((l) => l.type === "tool" && l.args?.toolName === "chat_post").map((l) => l.args?.args));
  check("the second message steered into the running turn", steered.map((l) => l.text).join(" | ") || "none", steered.some((l) => l.text.includes("4242")));
  check("the command ran once, not again", `${sleeps.length} sleep call(s)`, sleeps.length === 1);
  check("one turn, both answered: the command's output and the number", said.slice(0, 300), said.includes("done-sleeping") && said.includes("4242") && ends(A).length === 2);

  say("the station started again: the session taken up, the agent remembers");
  stopStations();
  await new Promise((r) => setTimeout(r, 2000));
  run(A);
  await until(async () => JSON.parse(readFileSync(join(A.data, "run/presence.json"), "utf8")).online === true, "station online again");
  const before = transcript(A).length;
  await until(async () => owner.call("chat.send", { station, session, text: "What number did I ask you to say? Post just the number." }).catch(() => null), "sent after the restart", 100);
  await until(async () => ends(A).length >= 3, "the third turn's end");
  const third = transcript(A).slice(before);
  const answer = JSON.stringify(third.filter((l) => l.type === "tool" && l.args?.toolName === "chat_post").map((l) => l.args?.args));
  check("resumed in a new process with its conversation", answer.slice(0, 200), answer.includes("4242") && transcript(A)[0]?.type === "session");

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
