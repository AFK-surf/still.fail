// One station in two workspaces end to end (docs/multi-workspace.md), on a dev cloud (cloud/test/dev.ts) and a real
// station: alice's station, in her workspace Dev, joins bob's workspace Team B with a token bob made; each workspace's
// members get in with their own credentials and see their own chats only; the station's own settings stay alice's;
// bob taking it out of Team B leaves it in Dev. Devices are raw iroh endpoints speaking the admin API.
//
//   node station/side/multi-workspace-e2e.ts   (from a worktree with `pnpm run build` done in station/ and
//                                               `pnpm run build:cloud` at the top, the iroh dev relay on :3340; PORT,
//                                               default 8877, and PORT+1..+4 free)
//
// It prints a line per check and a table at the end, and exits 1 if any check failed. Real processes and a real relay:
// a side test (scripts/side.sh), not one of the deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { loadMesh, type Endpoint } from "../src/mesh/native.ts";
import { ALPN } from "../src/mesh/serve.ts";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8877);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/multi-workspace-e2e";

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

// ── the station ──

const env = () => ({ ...process.env, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") });
const dir = join(WORK, "station");
const data = join(dir, "data");
const app = join(dir, "app");
let proc: ChildProcess | null = null;
const state = () => JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8"));
const online = () => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true;
const enrollArgs = (command: string) => command.split(" ").slice(3);
function stopStation() {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}

// ── a member's device: iroh with its own key, the admin API over it ──

const mesh = loadMesh();
async function device(): Promise<Endpoint> {
  const e = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
  await e.online();
  return e;
}
async function readLine(stream: { read(): Promise<Buffer | null> }, carry = { rest: Buffer.alloc(0) }): Promise<string | null> {
  for (;;) {
    const at = carry.rest.indexOf(10);
    if (at >= 0) {
      const line = carry.rest.subarray(0, at).toString();
      carry.rest = carry.rest.subarray(at + 1);
      return line;
    }
    const more = await stream.read();
    if (!more) return carry.rest.length ? carry.rest.toString() : null;
    carry.rest = Buffer.concat([carry.rest, more]);
  }
}
/// Connects with `credential` and asks the admin API: the hello, and each request's status and JSON answer.
async function ask(endpoint: Endpoint, station: string, credential: string, requests: [string, string, unknown?][]) {
  const conn = await endpoint.connect({ id: station, relays: [RELAY] }, ALPN);
  try {
    const first = await conn.openBi();
    await first.write(Buffer.from(JSON.stringify({ credential, protocol: 2 }) + "\n"));
    const hello = JSON.parse((await readLine(first)) ?? "null");
    const answers: [number, any][] = [];
    if (hello?.ok) {
      for (const [method, path, body] of requests) {
        const req = await conn.openBi();
        await req.write(Buffer.from(JSON.stringify({ method, path: `/admin/api${path}`, headers: { "content-type": "application/json" } }) + "\n"));
        if (body !== undefined) await req.write(Buffer.from(JSON.stringify(body)));
        await req.finish();
        const carry = { rest: Buffer.alloc(0) };
        const head = JSON.parse((await readLine(req, carry)) ?? "null");
        let rest = carry.rest;
        for (let more = await req.read(); more; more = await req.read()) rest = Buffer.concat([rest, more]);
        let json: any = null;
        try {
          json = JSON.parse(rest.toString());
        } catch {}
        answers.push([head?.status ?? 0, json]);
      }
    }
    return { hello, answers };
  } finally {
    conn.close(0, "done");
  }
}
const credentialFor = async (who: Account, ws: string, d: Endpoint) => (await api(who, "POST", `/v1/workspaces/${ws}/credential`, { device: d.id() })).credential as string;

async function main() {
  stopStation();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(WORK, { recursive: true });
  say("dev cloud; alice's station in Dev; bob's workspace Team B");
  await startCloud();
  const alice = await account("alice");
  const bob = await account("bob");
  const carol = await account("carol");
  const dev = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const teamB = (await api(bob, "POST", "/v1/workspaces", { name: "Team B" })).id as string;
  mkdirSync(join(app, "node/bin"), { recursive: true });
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  execFileSync(native("launcher"), ["enroll", ...enrollArgs((await api(alice, "POST", `/v1/workspaces/${dev}/enrollments`, { name: "studio" })).command), "--app", app, "--data", data], { env: env() });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"], workspaces: [teamB] }] }));
  writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
  const station = state().station as string;
  proc = spawn(native("launcher"), ["run", "--app", app, "--data", data], { env: env(), stdio: ["ignore", openSync(join(dir, "station.log"), "a"), openSync(join(dir, "station.log"), "a")] });
  await until(async () => online(), "station online");

  say("alice joins it to Team B with bob's token, on the machine");
  const token = (await api(bob, "POST", `/v1/workspaces/${teamB}/enrollments`, { name: "alice's studio" })).token as string;
  const joined = execFileSync(process.execPath, [join(app, "station/main.js"), "enroll", ORIGIN, token, "--join", "--data", data], { env: env(), encoding: "utf8" }).trim();
  await until(async () => state().joined?.some((j: any) => j.workspace === teamB), "joined in cloud.json");
  const inDev = (await api(alice, "GET", `/v1/workspaces/${dev}`)).stations.find((s: any) => s.id === station);
  const inB = (await api(bob, "GET", `/v1/workspaces/${teamB}`)).stations.find((s: any) => s.id === station);
  check("in both workspaces, Dev its home", `said: ${joined}; cloud.json home ${state().workspace === dev ? "Dev" : state().workspace}, joined ${state().joined.map((j: any) => j.workspace_name).join(",")}; Dev lists it ${inDev ? `(joined: ${inDev.joined ?? false})` : "no"}; Team B lists it ${inB ? `as "${inB.name}" (joined: ${inB.joined ?? false})` : "no"}`, state().workspace === dev && inDev && !inDev.joined && inB?.joined === true);

  say("each workspace's members get in with their own credential; nobody else");
  const aliceDevice = await device();
  const bobDevice = await device();
  const carolDevice = await device();
  const carolWs = (await api(carol, "POST", "/v1/workspaces", { name: "Carol's" })).id as string;
  const a = await ask(aliceDevice, station, await credentialFor(alice, dev, aliceDevice), [["GET", "/workspaces"], ["POST", "/sessions", { runtime: "claude", title: "alice's chat" }]]);
  const b = await ask(bobDevice, station, await credentialFor(bob, teamB, bobDevice), [["GET", "/workspaces"], ["POST", "/sessions", { runtime: "claude", title: "bob's chat" }], ["POST", "/workspaces/join", { token: "x" }], ["PUT", "/tools/access", { access: "full" }]]);
  const c = await ask(carolDevice, station, await credentialFor(carol, carolWs, carolDevice), []);
  check("admitted by workspace", `alice (Dev): ${a.hello?.ok ? `in as "${a.hello.station}"` : a.hello?.error}; bob (Team B): ${b.hello?.ok ? `in as "${b.hello.station}"` : b.hello?.error}; carol (her own): ${c.hello?.ok ? "in" : `refused: ${c.hello?.error}`}`, a.hello?.ok && b.hello?.ok && !c.hello?.ok);
  const [aw, ac] = a.answers;
  const [bw, bc, bj, bt] = b.answers;
  check("what each sees of the station's workspaces", `alice: ${JSON.stringify(aw?.[1]?.workspaces?.map((w: any) => w.workspaceName))} canJoin ${aw?.[1]?.canJoin}; bob: ${JSON.stringify(bw?.[1]?.workspaces?.map((w: any) => w.workspaceName))} canJoin ${bw?.[1]?.canJoin}`, aw?.[1]?.workspaces?.length === 2 && bw?.[1]?.workspaces?.length === 1 && bw?.[1]?.canJoin === false);
  check("the station's own settings stay with its home workspace", `bob joins it elsewhere: ${bj?.[0]}; bob sets the device tools: ${bt?.[0]}`, bj?.[0] === 403 && bt?.[0] === 403);
  check("chats made in each", `alice: ${ac?.[0]}; bob: ${bc?.[0]} ${bc?.[0] !== 200 ? JSON.stringify(bc?.[1]) : ""}`, ac?.[0] === 200 && bc?.[0] === 200);

  say("each sees their own workspace's chats only");
  const titles = (r: any) => (Array.isArray(r) ? r : (r?.items ?? r?.rows ?? [])).map((x: any) => x.title ?? x.chat?.title ?? x.session?.title).filter(Boolean);
  const aSees = await ask(aliceDevice, station, await credentialFor(alice, dev, aliceDevice), [["GET", "/chats"]]);
  const bSees = await ask(bobDevice, station, await credentialFor(bob, teamB, bobDevice), [["GET", "/chats"], ["GET", `/sessions/${encodeURIComponent(ac?.[1]?.key ?? "x")}`]]);
  const at = titles(aSees.answers[0]?.[1]);
  const bt2 = titles(bSees.answers[0]?.[1]);
  check("chat lists", `alice sees ${JSON.stringify(at)}; bob sees ${JSON.stringify(bt2)}; bob asks for alice's session: ${bSees.answers[1]?.[0]}`, at.includes("alice's chat") && !at.includes("bob's chat") && bt2.includes("bob's chat") && !bt2.includes("alice's chat") && bSees.answers[1]?.[0] === 404);

  say("bob takes the station out of Team B; it stays in Dev");
  await api(bob, "DELETE", `/v1/workspaces/${teamB}/stations/${station}`);
  await until(async () => !state().joined, "Team B gone from cloud.json");
  await new Promise((r) => setTimeout(r, 1000));
  const bAfter = await ask(bobDevice, station, await credentialFor(bob, teamB, bobDevice).catch(() => ""), []).catch((e) => ({ hello: { error: (e as Error).message } }));
  const aAfter = await ask(aliceDevice, station, await credentialFor(alice, dev, aliceDevice), [["GET", "/workspaces"]]);
  check("out of Team B, still in Dev", `online ${online()}; cloud.json joined ${JSON.stringify(state().joined ?? [])}; bob: ${bAfter.hello?.ok ? "in" : `refused: ${bAfter.hello?.error}`}; alice: ${aAfter.hello?.ok ? `in, workspaces ${JSON.stringify(aAfter.answers[0]?.[1]?.workspaces?.map((w: any) => w.workspaceName))}` : aAfter.hello?.error}`, online() && !bAfter.hello?.ok && aAfter.hello?.ok === true && aAfter.answers[0]?.[1]?.workspaces?.length === 1);

  say("summary");
  console.table(results.map((r) => ({ check: r.check, ok: r.ok ? "PASS" : "FAIL" })));
  await Promise.all([aliceDevice.close(), bobDevice.close(), carolDevice.close()]);
  return results.every((r) => r.ok);
}

let ok = false;
try {
  ok = await main();
} catch (e) {
  console.error("e2e stopped:", e);
} finally {
  if (cloud) cloud.kill();
  stopStation();
}
process.exit(ok ? 0 : 1);
