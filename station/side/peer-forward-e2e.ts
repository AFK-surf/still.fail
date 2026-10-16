// A port of another station forwarded to this one end to end (docs/station-peers.md "Forwarded ports"), on a dev cloud
// (cloud/test/dev.ts) with two real stations of one workspace over real local iroh: an agent's session on "here" calls
// peer_forward through its MCP door; a web page served on "there" (absolute asset paths, a WebSocket) and raw TCP go
// through the forwarded port; the session archived closes it; "there" stopped is said to be offline. Rough latency
// and throughput are printed. With PLAYWRIGHT_MODULE (playwright-core's index.mjs), Chromium opens the page too.
//
//   node station/side/peer-forward-e2e.ts   (from a worktree with `pnpm run build` done in station/ and
//                                            `pnpm run build:cloud` at the top, the iroh dev relay on :3340; PORT,
//                                            default 8877, and PORT+1..+4 free)
//
// It prints a line per check and a table at the end, and exits 1 if any check failed. Real processes and a real relay:
// a side test (scripts/side.sh), not one of the deterministic ones.
import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { type IncomingMessage, createServer as createHttpServer, request as httpRequest } from "node:http";
import { type AddressInfo, connect, createServer } from "node:net";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import WebSocket, { WebSocketServer } from "ws";
import { loadMesh, type Endpoint } from "../src/mesh/native.ts";
import { ALPN } from "../src/mesh/serve.ts";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8877);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? "/tmp/peer-forward-e2e";

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

// ── the stations ──

const env = () => ({ ...process.env, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") });
type Station = { name: string; dir: string; data: string; app: string; id: string; proc: ChildProcess | null };
const stations: Station[] = [];
const online = (s: Station) => JSON.parse(readFileSync(join(s.data, "run/presence.json"), "utf8")).online === true;
const enrollArgs = (command: string) => command.split(" ").slice(3);
function stopStation(s: Station) {
  s.proc?.kill();
  try {
    execFileSync("pkill", ["-f", `${s.dir}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}
function stopAll() {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {
    // None left.
  }
}

async function station(alice: Account, ws: string, name: string): Promise<Station> {
  const dir = join(WORK, name);
  const s: Station = { name, dir, data: join(dir, "data"), app: join(dir, "app"), id: "", proc: null };
  mkdirSync(join(s.app, "node/bin"), { recursive: true });
  mkdirSync(join(s.data, "homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(s.app, "station"));
  symlinkSync(process.execPath, join(s.app, "node/bin/node"));
  execFileSync(native("launcher"), ["enroll", ...enrollArgs((await api(alice, "POST", `/v1/workspaces/${ws}/enrollments`, { name })).command), "--app", s.app, "--data", s.data], { env: env() });
  writeFileSync(join(s.data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(s.data, "homes/fake/.credentials.json"), "{}");
  s.id = JSON.parse(readFileSync(join(s.data, "mesh/cloud.json"), "utf8")).station;
  s.proc = spawn(native("launcher"), ["run", "--app", s.app, "--data", s.data], { env: env(), stdio: ["ignore", openSync(join(dir, "station.log"), "a"), openSync(join(dir, "station.log"), "a")] });
  stations.push(s);
  await until(async () => online(s), `${name} online`);
  return s;
}

/// The station's agents' door (its MCP URL), as its log says once it is open.
const doorOf = (s: Station) => until(async () => /agents' door open url=(\S+)/.exec(readFileSync(join(s.dir, "station.log"), "utf8"))?.[1], `${s.name}'s door`);

// ── a member's device: iroh with its own key, the admin API over it ──

const mesh = loadMesh();
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
async function admin(endpoint: Endpoint, station: string, credential: string, method: string, path: string, body?: unknown): Promise<[number, any]> {
  const conn = await endpoint.connect({ id: station, relays: [RELAY] }, ALPN);
  try {
    const first = await conn.openBi();
    await first.write(Buffer.from(JSON.stringify({ credential, protocol: 2 }) + "\n"));
    const hello = JSON.parse((await readLine(first)) ?? "null");
    if (!hello?.ok) throw new Error(`not admitted: ${hello?.error}`);
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
    return [head?.status ?? 0, json];
  } finally {
    conn.close(0, "done");
  }
}

/// A tool of the station's MCP, as the session whose token it is.
async function tool(door: string, token: string, name: string, args: Record<string, unknown>): Promise<{ text: string; error: boolean }> {
  const r = await fetch(door, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name, arguments: args } }) });
  const body = (await r.json()) as any;
  return { text: body.result?.content?.[0]?.text ?? JSON.stringify(body), error: body.result?.isError === true || body.error !== undefined };
}

// ── what the other station serves ──

const PAGE = `<!doctype html><link rel="stylesheet" href="/assets/style.css"><script type="module" src="/assets/app.js"></script><p id="out">loading</p>`;
const APP = `const ws = new WebSocket(\`ws://\${location.host}/hmr\`); ws.onmessage = (e) => { document.getElementById("out").textContent = "ws: " + e.data; }; ws.onopen = () => ws.send("ping");`;
function webService() {
  const server = createHttpServer((req, res) => {
    if (req.url === "/") return res.writeHead(200, { "content-type": "text/html" }).end(PAGE);
    if (req.url === "/assets/app.js") return res.writeHead(200, { "content-type": "text/javascript" }).end(APP);
    if (req.url === "/assets/style.css") return res.writeHead(200, { "content-type": "text/css" }).end("p{color:green}");
    if (req.url === "/app") return res.writeHead(302, { location: "/login" }).end();
    if (req.url === "/login") return res.end(`login (Host ${req.headers.host})`);
    if (req.url === "/tiny") return res.end("ok");
    res.writeHead(404).end();
  });
  new WebSocketServer({ server }).on("connection", (ws) => ws.on("message", (data, binary) => ws.send(binary ? data : `pong ${data}`, { binary })));
  return server;
}
/// Raw TCP: what is asked ("down <bytes>\n" sends that many; anything else is counted and the count said at its end).
function tcpService() {
  const chunk = Buffer.alloc(1024 * 1024, 7);
  return createServer({ allowHalfOpen: true }, (socket) => {
    socket.on("error", () => {});
    let first: Buffer | null = Buffer.alloc(0);
    let counted = 0;
    socket.on("data", async (c: Buffer) => {
      if (first !== null) {
        first = Buffer.concat([first, c]);
        const nl = first.indexOf(10);
        if (nl < 0) return;
        const ask = /^down (\d+)$/.exec(first.subarray(0, nl).toString());
        const rest = first.subarray(nl + 1);
        first = null;
        if (ask) {
          let left = Number(ask[1]);
          while (left > 0) {
            const part = left >= chunk.length ? chunk : chunk.subarray(0, left);
            left -= part.length;
            if (!socket.write(part)) await new Promise((r) => socket.once("drain", r));
          }
          return void socket.end();
        }
        counted += rest.length;
        return;
      }
      counted += c.length;
    });
    socket.on("end", () => socket.end(`${counted}\n`));
  });
}

const listen = async (s: { listen: (...a: any[]) => unknown; address: () => unknown }) => {
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", r));
  return (s.address() as AddressInfo).port;
};
const pct = (xs: number[], p: number) => [...xs].sort((a, b) => a - b)[Math.min(xs.length - 1, Math.floor((xs.length * p) / 100))]!.toFixed(2);

/// A GET on a connection of its own: ms to the whole answer.
function getFresh(port: number, path: string): Promise<number> {
  const t = performance.now();
  return new Promise((resolve, reject) => {
    httpRequest({ host: "127.0.0.1", port, path, agent: false }, (res: IncomingMessage) => {
      res.resume();
      res.on("end", () => resolve(performance.now() - t));
    })
      .on("error", reject)
      .end();
  });
}

/// A raw TCP exchange through `port`: MB/s down (asking for `bytes`) and up (sending `bytes`).
async function throughput(port: number, bytes: number): Promise<{ down: number; up: number }> {
  const down = await new Promise<number>((resolve, reject) => {
    const t = performance.now();
    let got = 0;
    const s = connect({ host: "127.0.0.1", port }, () => s.write(`down ${bytes}\n`));
    s.on("data", (c) => (got += c.length));
    s.on("end", () => (got === bytes ? resolve(bytes / 1e6 / ((performance.now() - t) / 1000)) : reject(new Error(`got ${got} of ${bytes}`))));
    s.on("error", reject);
  });
  const up = await new Promise<number>((resolve, reject) => {
    const t = performance.now();
    const s = connect({ host: "127.0.0.1", port, allowHalfOpen: true });
    let said = "";
    s.on("data", (c) => (said += c));
    s.on("end", () => (Number(said.trim()) === bytes ? resolve(bytes / 1e6 / ((performance.now() - t) / 1000)) : reject(new Error(`counted ${said.trim()} of ${bytes}`))));
    s.on("error", reject);
    s.on("connect", async () => {
      s.write("up\n");
      const chunk = Buffer.alloc(1024 * 1024, 9);
      for (let left = bytes; left > 0; left -= chunk.length) if (!s.write(left >= chunk.length ? chunk : chunk.subarray(0, left))) await new Promise((r) => s.once("drain", r));
      s.end();
    });
  });
  return { down, up };
}

async function main() {
  stopAll();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(WORK, { recursive: true });
  say("dev cloud; two stations in alice's workspace Dev");
  await startCloud();
  const alice = await account("alice");
  const dev = (await api(alice, "GET", "/v1/me")).workspaces.find((w: any) => w.name === "Dev").id as string;
  const here = await station(alice, dev, "here");
  const there = await station(alice, dev, "there");
  check("both online", `here ${here.id.slice(0, 8)}, there ${there.id.slice(0, 8)}`, online(here) && online(there));

  say("a session on here; services on there's machine");
  const device = await mesh.bind({ secretKey: randomBytes(32), alpns: [ALPN], relayUrls: [RELAY], discovery: false });
  await device.online();
  const credential = (await api(alice, "POST", `/v1/workspaces/${dev}/credential`, { device: device.id() })).credential as string;
  const [made, session] = await admin(device, here.id, credential, "POST", "/sessions", { runtime: "claude", title: "forwarding" });
  const db = new DatabaseSync(join(here.data, "stillfail.db"), { readOnly: true });
  const token = (db.prepare("SELECT token FROM sessions WHERE key = ?").get(session?.key) as { token: string } | undefined)?.token ?? "";
  db.close();
  const door = await doorOf(here);
  check("session made", `POST /sessions ${made}, key ${session?.key}, token ${token ? "read" : "none"}, door ${door}`, made === 200 && token !== "");
  const web = webService();
  const webPort = await listen(web);
  const tcp = tcpService();
  const tcpPort = await listen(tcp);

  say("peer_forward through here's MCP");
  const listedEmpty = await tool(door, token, "peer_forward", {});
  const opened = await tool(door, token, "peer_forward", { station: "there", port: webPort });
  console.log(opened.text);
  const forward = opened.error ? null : JSON.parse(opened.text);
  const local = forward ? Number(forward.local.split(":")[1]) : 0;
  check("opened", `empty list: "${listedEmpty.text}"; opened: ${opened.error ? `error ${opened.text}` : `${forward.local} → there:${webPort}${forward.note ? ` (${forward.note})` : ""}`}`, !opened.error && listedEmpty.text === "No forwarded ports.");

  const page = await (await fetch(`http://127.0.0.1:${local}/`)).text();
  const assets = [...page.matchAll(/(?:src|href)="(\/assets\/[^"]+)"/g)].map((m) => m[1]!);
  const fetched = await Promise.all(assets.map(async (a) => [a, (await fetch(`http://127.0.0.1:${local}${a}`)).status] as const));
  const login = await fetch(`http://127.0.0.1:${local}/app`);
  check("a page with absolute asset paths, a redirect", `page ${page.length} B; ${fetched.map(([a, s]) => `${a} ${s}`).join(", ")}; /app → ${login.url.replace(`http://127.0.0.1:${local}`, "")}: "${await login.text()}"`, page === PAGE && fetched.length === 2 && fetched.every(([, s]) => s === 200) && login.url.endsWith("/login"));

  const ws = new WebSocket(`ws://127.0.0.1:${local}/hmr`, { origin: `http://127.0.0.1:${local}` });
  await new Promise((r, j) => (ws.once("open", r), ws.once("error", j)));
  const rtts: number[] = [];
  for (let i = 0; i < 200; i++) {
    const t = performance.now();
    const back = new Promise<string>((r) => ws.once("message", (d) => r(String(d))));
    ws.send(`p${i}`);
    if ((await back) !== `pong p${i}`) throw new Error("WebSocket answered wrong");
    rtts.push(performance.now() - t);
  }
  ws.close();
  check("a WebSocket (as HMR's)", `200 echoes, p50 ${pct(rtts, 50)} ms, p90 ${pct(rtts, 90)} ms`, rtts.length === 200);

  if (process.env.PLAYWRIGHT_MODULE) {
    const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
    const browser = await chromium.launch();
    try {
      const p = await browser.newPage();
      await p.goto(`http://127.0.0.1:${local}/`);
      await p.waitForFunction(() => document.getElementById("out")?.textContent?.startsWith("ws:"), null, { timeout: 15000 });
      const out = await p.textContent("#out");
      const color = await p.evaluate(() => getComputedStyle(document.getElementById("out")!).color);
      check("Chromium opens it", `#out "${out}", style ${color}`, out === "ws: pong ping" && color === "rgb(0, 128, 0)");
    } finally {
      await browser.close();
    }
  }

  // Latency: a GET on a kept connection, and on a new one each time (a new stream there, a new connection to the
  // service); direct for comparison.
  const kept: number[] = [];
  const direct: number[] = [];
  for (let i = 0; i < 300; i++) {
    let t = performance.now();
    await (await fetch(`http://127.0.0.1:${local}/tiny`)).text();
    kept.push(performance.now() - t);
    t = performance.now();
    await (await fetch(`http://127.0.0.1:${webPort}/tiny`)).text();
    direct.push(performance.now() - t);
  }
  const fresh: number[] = [];
  for (let i = 0; i < 100; i++) fresh.push(await getFresh(local, "/tiny"));
  check("latency", `GET on a kept connection p50 ${pct(kept, 50)} / p90 ${pct(kept, 90)} ms (direct ${pct(direct, 50)} / ${pct(direct, 90)}); on a new connection each p50 ${pct(fresh, 50)} / p90 ${pct(fresh, 90)} ms`, true);

  const raw = await tool(door, token, "peer_forward", { station: there.id, port: tcpPort });
  const rawLocal = Number(JSON.parse(raw.text).local.split(":")[1]);
  const mb = 100 * 1024 * 1024;
  const through = await throughput(rawLocal, mb);
  const straight = await throughput(tcpPort, mb);
  check("raw TCP, 100 MiB each way", `through the forward down ${through.down.toFixed(0)} MB/s, up ${through.up.toFixed(0)} MB/s (direct ${straight.down.toFixed(0)} / ${straight.up.toFixed(0)})`, through.down > 0 && through.up > 0);

  const listed = await tool(door, token, "peer_forward", {});
  console.log(listed.text);
  const list = JSON.parse(listed.text);
  check("listed", `${list.map((f: any) => `${f.local} → ${f.station}:${f.port} ${f.station_state}, served ${f.served}`).join("; ")}`, list.length === 2 && list.every((f: any) => f.station_state === "online"));

  say("closed by the tool; the session archived closes the rest");
  const closed = await tool(door, token, "peer_forward", { close: rawLocal });
  const [archived] = await admin(device, here.id, credential, "POST", `/sessions/${encodeURIComponent(session.key)}/archive`);
  const refused = await new Promise<boolean>((resolve) => {
    const s = connect({ host: "127.0.0.1", port: local });
    s.once("connect", () => (s.destroy(), resolve(false)));
    s.once("error", () => resolve(true));
  });
  check("closed", `close: "${closed.text}"; archive ${archived}; ${local} then ${refused ? "refuses connections" : "still listens"}`, !closed.error && archived === 200 && refused);

  say("there stopped: offline");
  const [made2, session2] = await admin(device, here.id, credential, "POST", "/sessions", { runtime: "claude", title: "offline" });
  const db2 = new DatabaseSync(join(here.data, "stillfail.db"), { readOnly: true });
  const token2 = (db2.prepare("SELECT token FROM sessions WHERE key = ?").get(session2?.key) as { token: string }).token;
  db2.close();
  const again = JSON.parse((await tool(door, token2, "peer_forward", { station: "there", port: webPort })).text);
  const againLocal = Number(again.local.split(":")[1]);
  stopStation(there);
  web.closeAllConnections();
  const t = performance.now();
  const cut = await new Promise<string>((resolve) => {
    const s = connect({ host: "127.0.0.1", port: againLocal });
    s.on("error", (e) => resolve(`reset (${(e as NodeJS.ErrnoException).code})`));
    s.on("close", () => resolve("closed"));
    s.on("connect", () => s.write("GET / HTTP/1.1\r\nhost: x\r\n\r\n"));
  });
  const firstMs = performance.now() - t;
  const t2 = performance.now();
  await new Promise<void>((resolve) => {
    const s = connect({ host: "127.0.0.1", port: againLocal });
    s.on("error", () => resolve());
    s.on("close", () => resolve());
  });
  const secondMs = performance.now() - t2;
  const offline = await tool(door, token2, "peer_forward", {});
  console.log(offline.text);
  check("offline", `made ${made2}; first connection ${cut} after ${firstMs.toFixed(0)} ms, next ${secondMs.toFixed(0)} ms; listed: ${JSON.parse(offline.text)[0]?.station_state}`, /^offline/.test(JSON.parse(offline.text)[0]?.station_state ?? ""));

  say("summary");
  console.table(results.map((r) => ({ check: r.check, ok: r.ok ? "PASS" : "FAIL" })));
  web.close();
  tcp.close();
  await device.close();
  return results.every((r) => r.ok);
}

let ok = false;
try {
  ok = await main();
} catch (e) {
  console.error("e2e stopped:", e);
} finally {
  (cloud as ChildProcess | null)?.kill();
  for (const s of stations) stopStation(s);
}
process.exit(ok ? 0 : 1);
