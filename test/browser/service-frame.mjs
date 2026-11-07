// A web service in the app in a browser, end to end: a dev cloud (cloud/test/dev.ts), a station of this checkout (a fake
// claude) in alice's workspace, the app signed in as alice, and a service an agent started (job_start, through the
// station's MCP endpoint), opened by its link on a desktop's page and a phone's. Its page is pressed as a person presses
// it (so the canvas over it must let the press through), scrolled by a wheel and by a finger (Chromium's scrolling must
// find it too), its POST's body and its WebSocket go to the service and back.
// Pictures of each go to SHOTS.
//
//   pnpm run build:cloud && (cd station && pnpm run build) && SHOTS=<dir> node test/browser/service-frame.mjs
//   (the iroh dev relay on :3340; PORT, default 8973, and PORT+1..+5 free; PLAYWRIGHT_MODULE as stories.mjs takes it;
//   build:cloud with STILLFAIL_PREVIEW_ORIGIN=http://127.0.0.1:<PORT+3>, whose app apps/mbui/scripts/web-app.sh made)
//
// Real processes and a browser: a side script, not one of the deterministic tests.
import { execFileSync, spawn } from "node:child_process";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8973);
const SERVICE_PORT = PORT + 20;
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
// Short: a runner's socket path under it must fit in sun_path.
const WORK = process.env.WORK ?? "/tmp/service-frame";
const SHOTS = process.env.SHOTS ?? join(ROOT, "service-frame-shots");
const playwright = await import(process.env.PLAYWRIGHT_MODULE || "playwright-core");
const native = (what) => execFileSync(process.execPath, [join(ROOT, "scripts/native.ts"), "file", what], { encoding: "utf8" }).trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (what, label, tries = 300) => {
  for (let i = 0; i < tries; i++) {
    const v = await Promise.resolve().then(what).catch(() => null);
    if (v) return v;
    await sleep(200);
  }
  throw new Error(`gave up waiting: ${label}`);
};

// The service: a page whose button POSTs and says the answer, and whose WebSocket echoes.
const SERVICE = `
import { createServer } from "node:http";
import { createRequire } from "node:module";
const { WebSocketServer } = createRequire(${JSON.stringify(join(ROOT, "station/package.json"))})("ws");
const server = createServer((req, res) => {
  if (req.method === "POST") {
    let body = "";
    req.on("data", (d) => (body += d));
    req.on("end", () => res.end("posted " + body));
    return;
  }
  res.setHeader("content-type", "text/html; charset=utf-8");
  res.end(\`<!doctype html><title>Service</title><body style="font:20px system-ui;background:#e8f4ea;margin:0;padding:24px">
    <h1>the service's page</h1>
    <button id=go style="font-size:20px;padding:12px 24px">press</button>
    <p id=post>not pressed</p><p id=sock>no socket</p>
    <div style="height:3000px"></div>
    <script>
      const ws = new WebSocket("ws://" + location.host + "/echo");
      ws.onopen = () => ws.send("hello");
      ws.onmessage = (e) => { document.getElementById("sock").textContent = "socket said " + e.data; };
      document.getElementById("go").onclick = async () => {
        const r = await fetch("/api", { method: "POST", body: "pressed" });
        document.getElementById("post").textContent = await r.text();
      };
    </script>\`);
});
new WebSocketServer({ server }).on("connection", (ws) => ws.on("message", (m) => ws.send(String(m))));
server.listen(Number(process.env.PORT), "127.0.0.1");
`;

let cloud = null;
let station = null;
let browser = null;
let shown = null;
const stop = () => {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {}
  try {
    if (cloud) process.kill(-cloud.pid, "SIGTERM");
  } catch {}
};

async function main() {
  stop();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(SHOTS, { recursive: true });

  cloud = spawn("pnpm", ["exec", "tsx", "test/dev.ts"], { cwd: join(ROOT, "cloud"), env: { ...process.env, PORT: String(PORT), RELAY }, stdio: ["ignore", "pipe", "pipe"], detached: true });
  await new Promise((resolve, reject) => {
    let out = "";
    cloud.stdout.on("data", (d) => ((out += d), out.includes("READY still.fail cloud") && resolve()));
    cloud.on("exit", () => reject(new Error(`the dev cloud stopped: ${out.slice(-400)}`)));
  });
  const account = await (await fetch(`${ORIGIN}/__dev/account?user=alice`)).json();
  const api = async (method, path, body) => {
    const r = await fetch(`${ORIGIN}${path}`, { method, headers: { authorization: `Bearer ${account.access}`, "content-type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
    if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${await r.text()}`);
    return r.json();
  };
  const dev = (await api("GET", "/v1/me")).workspaces.find((w) => w.name === "Dev").id;

  const dir = join(WORK, "station");
  const data = join(dir, "data");
  const app = join(dir, "app");
  const env = { ...process.env, HOME: dir, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") };
  mkdirSync(join(app, "node/bin"), { recursive: true });
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  const enroll = (await api("POST", `/v1/workspaces/${dev}/enrollments`, { name: "Studio" })).command.split(" ").slice(3);
  execFileSync(native("launcher"), ["enroll", ...enroll, "--app", app, "--data", data], { env });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
  writeFileSync(join(dir, "service.mjs"), SERVICE);
  const log = openSync(join(dir, "station.log"), "a");
  station = spawn(native("launcher"), ["run", "--app", app, "--data", data], { env, stdio: ["ignore", log, log] });
  await until(() => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true, "station online");
  const stationId = JSON.parse(readFileSync(join(data, "mesh/cloud.json"), "utf8")).station;

  browser = await playwright.chromium.launch({
    ...(process.env.CHROMIUM_EXECUTABLE ? { executablePath: process.env.CHROMIUM_EXECUTABLE, timeout: 0 } : {}),
    args: ["--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessChecks", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
  });
  // Signed in as a browser does: the app's Google button, Google's page answered as picking alice would leave it.
  const context = await browser.newContext({ locale: "zh-CN", viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2 });
  await context.route(/\/v1\/auth\//, async (route) => {
    const answer = await route.fetch({ maxRedirects: 0 });
    const to = answer.headers().location ?? "";
    if (!to.includes("accounts.google.com")) return route.fulfill({ response: answer });
    await route.fulfill({ status: 302, headers: { location: `${ORIGIN}/__dev/google?${new URL(to).search.slice(1)}&user=alice` } });
  });
  const page = await context.newPage();
  shown = page;
  page.on("console", (m) => { if (m.type() === "error") console.log(`page error: ${m.text().slice(0, 300)}`); });

  // A chat, said in by typing into the new chat's composer: the agent's session is what the service's job belongs to.
  await page.goto(`${ORIGIN}/w/${dev}/new`, { timeout: 120_000 });
  const sessions = () => {
    const db = new DatabaseSync(join(data, "stillfail.db"), { readOnly: true });
    try {
      return db.prepare("SELECT key, token FROM sessions ORDER BY created_at").all();
    } finally {
      db.close();
    }
  };
  await until(async () => {
    await page.mouse.click(760, 420);
    await page.keyboard.type("start the service post:ok");
    await page.keyboard.press("Enter");
    await sleep(3000);
    return sessions().length > 0;
  }, "the chat started", 20);
  const session = sessions()[0];
  const door = /agents' door open.*?(http:\/\/[^"\s]+)/.exec(readFileSync(join(dir, "station.log"), "utf8"))?.[1];
  const answer = await (await fetch(door, { method: "POST", headers: { authorization: `Bearer ${session.token}`, "content-type": "application/json", accept: "application/json, text/event-stream" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "job_start", arguments: { command: `node ${join(dir, "service.mjs")}`, name: "the service", port: SERVICE_PORT } } }) })).json();
  const job = JSON.parse(answer.result.content[0].text).id;
  await until(() => fetch(`http://127.0.0.1:${SERVICE_PORT}/`).then((r) => r.ok), "the service up");
  const link = `${ORIGIN}/o/${dev}/${stationId}/${encodeURIComponent(session.key)}?service=${job}`;

  const check = async (p, name) => {
    await p.goto(link, { timeout: 120_000 });
    const frame = await until(() => p.frames().find((f) => f.parentFrame()?.url().includes("/_stillfail/frame")), `${name}: the service's frame`);
    await frame.getByText("the service's page").waitFor({ timeout: 60_000 });
    await until(async () => (await frame.locator("#sock").innerText()) === "socket said hello", `${name}: the socket's echo`);
    // Pressed as a person presses it: at its place on the page, whatever is on top there takes it.
    const box = await frame.locator("#go").boundingBox();
    await p.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await until(async () => (await frame.locator("#post").innerText()) === "posted pressed", `${name}: the press's POST`);
    await p.screenshot({ path: join(SHOTS, `${name}.png`) });
    console.log(`PASS ${name}: the page shown, a press through the canvas, its POST and its socket`);
    // A wheel over the page moves the page, and no more than the page.
    await p.mouse.move(box.x + box.width / 2, box.y + box.height / 2 + 100);
    await p.mouse.wheel(0, 300);
    await until(async () => (await frame.evaluate(() => scrollY)) >= 300, `${name}: the wheel's scroll`, 50);
    await frame.evaluate(() => scrollTo(0, 0));
    console.log(`PASS ${name}: a wheel scrolls the page`);
    return frame;
  };
  await check(page, "desktop");
  // Its bar's reload (the canvas's, over the frame's page): the service's page anew.
  const service = page.frames().find((f) => f.parentFrame()?.url().includes("/_stillfail/frame"));
  await page.mouse.click(1000, 65);
  await until(async () => (await service.locator("#post").innerText()) === "not pressed", "the bar's reload");
  // Drawn at half its size (the host told as a sized page tells it): laid out twice as wide, still pressed where it shows.
  const before = await page.evaluate(() => document.querySelector("iframe").getBoundingClientRect().width);
  const inner = await page.evaluate(() => { const f = document.querySelector("iframe"); globalThis.__mbhost.viewControl(1, 8, 0.5); return f.offsetWidth; });
  const go = await service.locator("#go").boundingBox();
  await page.mouse.click(go.x + go.width / 2, go.y + go.height / 2);
  await until(async () => (await service.locator("#post").innerText()) === "posted pressed", "a press on the page at half its size");
  await page.screenshot({ path: join(SHOTS, "desktop-half.png") });
  console.log(`PASS a page at half its size: ${before} wide shown, ${inner} laid out`);
  await page.evaluate(() => globalThis.__mbhost.viewControl(1, 8, 1));
  await page.setViewportSize({ width: 390, height: 844 });
  await check(page, "phone");
  // A finger on a phone's page scrolls it; beside it, in the app's bar, it is the app's and the page stays.
  const cdp = await context.newCDPSession(page);
  await cdp.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 });
  const swipe = async (x, from, to) => {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y: from }] });
    for (let i = 1; i <= 20; i++) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x, y: from + ((to - from) * i) / 20 }] });
      await sleep(16);
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };
  const phone = await check(page, "phone-touch");
  await swipe(195, 600, 200);
  await until(async () => (await phone.evaluate(() => scrollY)) > 100, "a finger's scroll on the phone's page", 50);
  await page.screenshot({ path: join(SHOTS, "phone-scrolled.png") });
  console.log(`PASS phone: a finger scrolls the page, to ${await phone.evaluate(() => scrollY)}`);
  // The bar's ⋯: a sheet over the page, a finger there the app's (it puts the sheet away); the page stays where it was.
  await swipe(368, 822, 822);
  await until(() => page.evaluate(() => [...document.body.children].some((e) => e.style.zIndex === "2")), "the sheet's box over the page", 50);
  const sheet = await page.evaluate(() => { const r = [...document.body.children].find((e) => e.style.zIndex === "2").getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
  await page.screenshot({ path: join(SHOTS, "phone-sheet.png") });
  // (read now: the finger's fling goes on until the tap on ⋯ comes down, a scrollTo does not stop it)
  const at = await phone.evaluate(() => scrollY);
  await swipe(sheet.x, sheet.y, sheet.y - 40);
  await until(() => page.evaluate(() => ![...document.body.children].some((e) => e.style.zIndex === "2")), "the sheet put away", 50);
  const after = await phone.evaluate(() => scrollY);
  if (after !== at) throw new Error(`a finger on the sheet moved the page: ${at} to ${after}`);
  console.log("PASS phone: a finger on a sheet over the page is the app's");
  return true;
}

let ok = false;
try {
  ok = await main();
} catch (error) {
  console.error(error);
  await shown?.screenshot({ path: join(SHOTS, "failed.png") }).catch(() => {});
  console.error(`at ${shown?.url()}`);
  try {
    console.error(readFileSync(join(WORK, "station", "station.log"), "utf8").split("\n").slice(-30).join("\n"));
  } catch {}
} finally {
  await browser?.close();
  stop();
  rmSync(WORK, { recursive: true, force: true });
}
process.exit(ok ? 0 : 1);
