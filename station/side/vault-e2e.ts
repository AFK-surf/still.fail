// The vault end to end (docs/vault.md), on a dev cloud (cloud/test/dev.ts), a real station and the owner's real core
// (desktop's Node host, with a sealer in memory): the owner turns the lock on, sets up the vault and keeps a token in
// it, open to agents through the proxy for one host; an agent (the fake claude's own MCP token, as a real agent calls
// the station's tools) asks for it, the owner's core approves, and the command run with the grant reaches an HTTPS host
// with the token in its Authorization header, while the agent sees only the placeholder and, in the environment's
// mode, the value hidden. A refusal and a spent grant are refused.
//
//   node station/side/vault-e2e.ts         (from a worktree with `pnpm run build` done in station/, the iroh dev relay
//                                            on :3340; PORT, default 8887, and PORT+1..+4 free; curl on PATH)
//
// It prints a line per check and a table at the end, and exits 1 if any check failed. Real processes and a real relay:
// a side test (scripts/side.sh), not one of the deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:https";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { makeCa, makeLeaf, pem } from "../src/vault/x509.ts";
// The core, as the desktop app runs it: imported by its path at run time (see lock-e2e.ts).
const CORE = "../../client/core-ts/src/hosts/node.ts";
type Sealer = { get(key: string, user: boolean, reason: string): Promise<Uint8Array | null>; set(key: string, value: Uint8Array, user: boolean): Promise<void>; delete(key: string): Promise<void> };
const { start } = (await import(CORE)) as {
  start: (dir: string, origin: string, listener: (client: number, json: string) => void, channel?: string, options?: { sealer?: Sealer }) => { connect(): number; receive(client: number, json: string): void; close(): Promise<void> };
};

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8887);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/vault-e2e";
const AUTH_KEY = "vault-e2e-auth-key-0123456789abcdef0123456789abcdef";
const TOKEN = `ghp_e2e${randomBytes(16).toString("hex")}`;

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

// ── the HTTPS host the token is for: answers with the sha256 of the Authorization it got ──

const hostCa = makeCa(Date.now(), "vault-e2e host ca");
const hostCaFile = join(WORK, "host-ca.pem");
const sha = (s: string) => createHash("sha256").update(s).digest("hex");
async function startHost(): Promise<number> {
  const leaf = makeLeaf(hostCa, "vault-e2e host ca", "localhost", Date.now());
  const server = createServer({ key: leaf.key.export({ format: "pem", type: "pkcs8" }), cert: pem(leaf.cert) }, (req, res) => res.end(`authorization-sha256=${sha(req.headers.authorization ?? "")}\n`));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  return (server.address() as { port: number }).port;
}

// ── the station ──

// The station trusts the test host's CA as a machine would a real host's (Node's extra roots): the proxy checks the
// host's certificate on the way out.
const env = () => ({ ...process.env, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner"), FAKE_DUMP: join(WORK, "claude.dump"), NODE_EXTRA_CA_CERTS: hostCaFile });
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

// ── the owner's core, its secure storage in memory (what the app's Keystore or keychain does, asking no one) ──

function core(name: string) {
  const dir = join(WORK, `core-${name}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  const sealed = new Map<string, { value: Uint8Array; user: boolean }>();
  const asked: string[] = [];
  const sealer: Sealer = {
    get: async (key, user, reason) => {
      const kept = sealed.get(key);
      if (kept && kept.user !== user) throw new Error("kept with the other user");
      if (user) asked.push(reason);
      return kept?.value ?? null;
    },
    set: async (key, value, user) => void sealed.set(key, { value, user }),
    delete: async (key) => void sealed.delete(key),
  };
  const waiting = new Map<number, (m: any) => void>();
  const c = start(dir, ORIGIN, (_client, json) => {
    const m = JSON.parse(json);
    if (typeof m.id === "number" && ("ok" in m || "error" in m)) waiting.get(m.id)?.(m), waiting.delete(m.id);
  }, undefined, { sealer });
  const ui = c.connect();
  let next = 1;
  const call = (name: string, params: unknown) =>
    new Promise<any>((resolve, reject) => {
      const id = next++;
      waiting.set(id, (m) => ("ok" in m ? resolve(m.ok) : reject(Object.assign(new Error(m.error?.message ?? JSON.stringify(m.error)), { code: m.error?.code }))));
      c.receive(ui, JSON.stringify({ kind: "call", id, call: name, params }));
    });
  c.receive(ui, JSON.stringify({ kind: "call", id: 0, call: "client.device", params: { app: "desktop", build: "e2e", userAgent: "Mac OS X", locale: "zh-CN" } }));
  return { call, asked, close: () => c.close() };
}

// ── an agent: the station's MCP endpoint with the session's token, as the fake claude was given them ──

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
  writeFileSync(hostCaFile, pem(hostCa.cert));
  const hostPort = await startHost();

  say("dev cloud, a station, the owner's desktop core turns the lock on");
  await startCloud();
  const alice = await account("alice");
  const ws = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const enrollArgs = (command: string) => command.split(" ").slice(3);
  const A = makeStation("vault-a", enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name: "vault-a" })).command));
  run(A);
  await until(async () => JSON.parse(readFileSync(join(A.data, "run/presence.json"), "utf8")).online === true, "station online");
  const owner = core("owner");
  await owner.call("migrate", { accounts: [alice] });
  await until(async () => (await owner.call("lock.state", { workspace: ws })).me.device, "owner core up");
  await until(async () => owner.call("lock.open", { workspace: ws }).catch((e) => (console.log("  open:", e.message), null)), "lock.open", 30);
  await until(async () => JSON.parse(readFileSync(join(A.data, "mesh/lock.json"), "utf8")).entries.length > 0, "station pinned");

  say("the vault: set up, a vault of alice's on the station, a token open to agents for localhost only");
  const setup = await until(async () => owner.call("vault.setup", { workspace: ws }).catch((e) => (console.log("  setup:", e.code, e.message), null)), "vault.setup", 50);
  const made = await owner.call("vault.create", { workspace: ws, name: "个人", station: A.id });
  const vaultId = made.id ?? made.vault ?? made;
  const put = await owner.call("vault.putItem", {
    workspace: ws, vault: vaultId,
    plain: { kind: "token", name: "Test host", fields: { value: TOKEN }, domains: [], notes: "" },
    listing: { name: "Test host", kind: "token", modes: ["proxy", "env"], hosts: ["localhost"], env: "GH_TOKEN" },
  });
  check("set up: 24 recovery words, a vault, an item", `words ${String(setup.words ?? "").split(" ").length}; vault ${JSON.stringify(vaultId).slice(0, 40)}; item ${put.id}`, String(setup.words ?? "").split(" ").length === 24 && typeof put.id === "string");
  const db = new DatabaseSync(join(A.data, "stillfail.db"), { readOnly: true });
  const stored = (db.prepare("SELECT body FROM vault_items").all() as { body: string }[]).map((r) => r.body).join("\n");
  check("the station holds ciphertext only", `vault_items rows ${stored.split("\n").length}; the token in them: ${stored.includes(TOKEN) ? "yes" : "no"}`, stored !== "" && !stored.includes(TOKEN));

  say("a chat on the station, its agent's tools");
  const chat = await owner.call("chat.create", { station: `${ws}/${A.id}`, runtime: "claude", model: "claude-opus-4-1" });
  const session = String(chat.key);
  await owner.call("chat.send", { station: `${ws}/${A.id}`, session, text: "say:hello" });
  await until(async () => readFileSync(join(WORK, "claude.dump"), "utf8").includes("STILLFAIL_MCP_TOKEN"), "the agent started");
  const tool = agent();
  const listed = await tool("secret_list", {});
  check("secret_list: the item by name, never its value", listed.text.replace(/\s+/g, " ").slice(0, 160), listed.text.includes("Test host") && !listed.text.includes(TOKEN));

  say("the agent asks; the owner's core approves it once; the command reaches the host with the token");
  const command = `curl -sS --fail https://localhost:${hostPort}/ -H "Authorization: Bearer $GH_TOKEN"`;
  const asking = tool("secret_use", { item: "Test host", reason: "e2e: call the test host", command });
  const request = await until(async () => (await owner.call("vault.state", { workspace: ws })).requests?.[0], "the request reaches the owner");
  await owner.call("vault.approve", { workspace: ws, request: request.id, scope: "once" });
  const granted = await asking;
  check("secret_use: asked, approved in the app, granted", `${granted.text.slice(0, 120)}…; the core asked the person: ${JSON.stringify(owner.asked.slice(-1))}`, /Granted/.test(granted.text) && owner.asked.length > 0);
  const ran = await tool("secret_run", { grant: request.id, command });
  const want = sha(`Bearer ${TOKEN}`);
  check("by proxy: the host got the token; the agent saw neither it nor more than the placeholder", ran.text.trim().replace(/\n/g, " | "), ran.text.includes(`authorization-sha256=${want}`) && !ran.text.includes(TOKEN));
  const again = await tool("secret_run", { grant: request.id, command });
  check("a grant for one use, used: refused", again.text, again.error && /one use/.test(again.text));
  const direct = execFileSync("curl", ["-sS", "--cacert", hostCaFile, `https://localhost:${hostPort}/`, "-H", "Authorization: Bearer stillfail-secret:" + request.id], { encoding: "utf8" });
  check("the placeholder alone (not through the proxy) is no token", direct.trim(), !direct.includes(want));

  say("by environment: the value hidden in what the agent sees");
  const asking2 = tool("secret_use", { item: "Test host", reason: "e2e: env", mode: "env", command: "printf %s $GH_TOKEN" });
  const request2 = await until(async () => (await owner.call("vault.state", { workspace: ws })).requests?.[0], "the second request");
  await owner.call("vault.approve", { workspace: ws, request: request2.id, scope: "once" });
  await asking2;
  const shown = await tool("secret_run", { grant: request2.id, command: 'printf "%s\\n" "$GH_TOKEN"; printf "%s" "$GH_TOKEN" | base64' });
  check("by env: the value and its base64 come back hidden", shown.text.replace(/\n/g, " | "), !shown.text.includes(TOKEN) && (shown.text.match(/\[已隐藏\]/g) ?? []).length === 2);

  say("refused: the agent is told, and gets nothing");
  const asking3 = tool("secret_use", { item: "Test host", reason: "e2e: refused", command });
  const request3 = await until(async () => (await owner.call("vault.state", { workspace: ws })).requests?.[0], "the third request");
  await owner.call("vault.deny", { workspace: ws, request: request3.id });
  const refused = await asking3;
  const after = await tool("secret_run", { grant: request3.id, command });
  check("a refusal: told so; its id is no grant", `${refused.text.slice(0, 80)}; secret_run: ${after.text.slice(0, 80)}`, /refused/.test(refused.text) && after.error);

  const audit = db.prepare("SELECT kind, detail FROM vault_audit ORDER BY rowid").all() as { kind: string; detail: string }[];
  check("what was done, recorded without the value", audit.map((a) => a.kind).join(", "), audit.some((a) => a.kind === "granted") && audit.some((a) => a.kind === "denied") && audit.some((a) => a.kind === "use") && !JSON.stringify(audit).includes(TOKEN));
  db.close();

  say("summary");
  console.table(results.map((r) => ({ check: r.check, ok: r.ok ? "PASS" : "FAIL" })));
  owner.close();
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
