// The search end to end (docs/search.md): a dev cloud (cloud/test/dev.ts), a station of this checkout (a fake claude)
// in alice's workspace, and the web app signed in as alice. Two chats are said in; ⌘K finds them by words; one is
// archived, and ⌘K finds it still (only the station has its messages now: the device's list no longer does); the
// phone's search finds the same; an agent's `search` tool (the station's MCP endpoint, as an agent asks it) says what
// it found. Pictures of each go to SHOTS.
//
//   pnpm run build:cloud && (cd station && pnpm run build) && SHOTS=<dir> node test/browser/search-e2e.mjs
//   (the iroh dev relay on :3340; PORT, default 8963, and PORT+1..+5 free; PLAYWRIGHT_MODULE as stories.mjs takes it)
//
// Real processes and a browser: a side script, not one of the deterministic tests.
import { execFileSync, spawn } from "node:child_process";
import { mkdirSync, openSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

const ROOT = join(import.meta.dirname, "..", "..");
const PORT = Number(process.env.PORT ?? 8963);
const ORIGIN = `http://127.0.0.1:${PORT}`;
const RELAY = process.env.RELAY ?? "http://127.0.0.1:3340";
const WORK = process.env.WORK ?? join(process.env.TMPDIR ?? "/tmp", "search-e2e");
const SHOTS = process.env.SHOTS ?? join(ROOT, "search-shots");
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
const results = [];
const check = (name, saw, ok) => {
  results.push({ name, ok });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}\n     ${saw}`);
};

let cloud = null;
let shown = null;
let station = null;
let browser = null;
const stop = () => {
  try {
    execFileSync("pkill", ["-f", `${WORK}/`], { stdio: "ignore" });
  } catch {}
  if (cloud) process.kill(-cloud.pid, "SIGTERM");
};

async function main() {
  stop();
  rmSync(WORK, { recursive: true, force: true });
  mkdirSync(SHOTS, { recursive: true });

  // ── the cloud ──
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

  // ── the station ──
  const dir = join(WORK, "station");
  const data = join(dir, "data");
  const app = join(dir, "app");
  const env = { ...process.env, PATH: `${join(ROOT, "station/test/fake")}:${process.env.PATH}`, STILLFAIL_NO_DISCOVERY: "1", STILLFAIL_MESH_NATIVE: native("mesh"), STILLFAIL_RUNNER: native("runner") };
  mkdirSync(join(app, "node/bin"), { recursive: true });
  mkdirSync(join(data, "homes/fake"), { recursive: true });
  symlinkSync(join(ROOT, "station/dist"), join(app, "station"));
  symlinkSync(process.execPath, join(app, "node/bin/node"));
  const enroll = (await api("POST", `/v1/workspaces/${dev}/enrollments`, { name: "Studio" })).command.split(" ").slice(3);
  execFileSync(native("launcher"), ["enroll", ...enroll, "--app", app, "--data", data], { env });
  writeFileSync(join(data, "config.json"), JSON.stringify({ autoUpdate: false, maxNudges: 0, autoArchiveDays: 0, profiles: [{ id: "fake", runtime: "claude", home: "homes/fake", models: ["claude-opus-4-1"] }] }));
  writeFileSync(join(data, "homes/fake/.credentials.json"), "{}");
  const log = openSync(join(dir, "station.log"), "a");
  station = spawn(native("launcher"), ["run", "--app", app, "--data", data], { env, stdio: ["ignore", log, log] });
  await until(() => JSON.parse(readFileSync(join(data, "run/presence.json"), "utf8")).online === true, "station online");

  // ── the web app, signed in as alice ──
  browser = await playwright.chromium.launch({ args: ["--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessChecks"] });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 }, deviceScaleFactor: 2, locale: "zh-CN" });
  await context.addInitScript((a) => {
    if (!localStorage.getItem("stillfail.accounts")) localStorage.setItem("stillfail.accounts", JSON.stringify([a]));
  }, account);
  const page = await context.newPage();
  shown = page;
  await page.goto(`${ORIGIN}/`, { timeout: 60_000 });
  await page.waitForURL(/\/w\/[^/]+/, { timeout: 60_000 });
  const workspace = /\/w\/([^/]+)/.exec(page.url())[1];

  // Two chats said in: the fake claude posts what follows post:.
  const say = async (text, answer) => {
    await page.goto(`${ORIGIN}/w/${workspace}/new`);
    const box = page.locator("textarea").first();
    await box.waitFor({ timeout: 60_000 });
    await box.click();
    await page.keyboard.insertText(`${text} post:${answer}`);
    await page.keyboard.press("Enter");
    // The agent's post in its chat (the composer empty by then).
    await page.waitForFunction((a) => document.body.innerText.includes(a) && !Array.from(document.querySelectorAll("textarea")).some((t) => t.value.includes(a)), answer, { timeout: 90_000 });
  };
  await say("帮我看看本地分析用什么", "结论：用 DuckDB 直接查 Parquet，不用导数据");
  await say("把预览部署到 studio", "已部署，预览在 5173 端口");
  await page.waitForTimeout(3000);

  const switcher = async (words, shot) => {
    await page.keyboard.press("Escape");
    await page.locator("textarea").first().click();
    await page.keyboard.press("ControlOrMeta+k");
    const field = page.getByPlaceholder("搜索全部内容和操作");
    await field.waitFor();
    await field.fill(words);
    // The device's finds at once, the station's a moment after the words settle.
    await page.waitForTimeout(2500);
    const rows = await page.locator('[role="listbox"]').innerText();
    await page.screenshot({ path: join(SHOTS, `${shot}.png`) });
    return rows;
  };

  const before = await switcher("duckdb", "desktop-duckdb");
  check("⌘K finds a chat and its message by a word", before.replace(/\s+/g, " ").slice(0, 300), /DuckDB/.test(before) && /消息/.test(before));

  // Archived: only its station has its messages now.
  await page.keyboard.press("Escape");
  const row = page.locator("a", { hasText: "帮我看看本地分析" }).first();
  await row.click({ button: "right" });
  await page.getByRole("menuitem", { name: /^归档/ }).first().click();
  const confirm = page.getByRole("button", { name: "归档" });
  if (await confirm.isVisible({ timeout: 1500 }).catch(() => false)) await confirm.click();
  await page.waitForTimeout(3000);
  const archived = await switcher("duckdb", "desktop-duckdb-archived");
  check("an archived chat is found, its message from its station", archived.replace(/\s+/g, " ").slice(0, 300), /已归档/.test(archived) && /DuckDB/.test(archived));
  await page.emulateMedia({ colorScheme: "dark" });
  await switcher("部署", "desktop-deploy-dark");
  await page.emulateMedia({ colorScheme: "light" });

  // The phone's search.
  const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: "zh-CN" });
  await phone.addInitScript((a) => {
    if (!localStorage.getItem("stillfail.accounts")) localStorage.setItem("stillfail.accounts", JSON.stringify([a]));
  }, account);
  const mobile = await phone.newPage();
  await mobile.goto(`${ORIGIN}/w/${workspace}`, { timeout: 60_000 });
  await mobile.getByText("搜索全部内容").first().tap({ timeout: 60_000 });
  await mobile.locator('input[type="search"]').fill("duckdb");
  await mobile.waitForTimeout(2500);
  const found = await mobile.locator("body").innerText();
  await mobile.screenshot({ path: join(SHOTS, "phone-duckdb.png") });
  check("the phone's search finds the archived chat's message", found.replace(/\s+/g, " ").slice(0, 300), /DuckDB/.test(found));

  // An agent's search: the station's MCP endpoint, as a session asks it.
  const db = new DatabaseSync(join(data, "stillfail.db"), { readOnly: true });
  const token = db.prepare("SELECT token FROM sessions ORDER BY created_at LIMIT 1").get().token;
  db.close();
  const door = /agents' door open.*?(http:\/\/[^"\s]+)/.exec(readFileSync(join(dir, "station.log"), "utf8"))?.[1];
  const answer = await (await fetch(door, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json", accept: "application/json, text/event-stream" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "search", arguments: { query: "部署" } } }) })).json();
  const said = answer?.result?.content?.[0]?.text ?? JSON.stringify(answer);
  console.log(said);
  check("an agent's search finds the messages and the chat's link", said.replace(/\s+/g, " ").slice(0, 300), /部署/.test(said) && /\/o\//.test(said));

  console.table(results.map((r) => ({ check: r.name, ok: r.ok ? "PASS" : "FAIL" })));
  return results.every((r) => r.ok);
}

let ok = false;
try {
  ok = await main();
} catch (error) {
  console.error(error);
  await shown?.screenshot({ path: join(SHOTS, "failed.png") }).catch(() => {});
  console.error(`at ${shown?.url()}`);
  try {
    console.error(readFileSync(join(WORK, "station", "station.log"), "utf8").split("\n").slice(-40).join("\n"));
  } catch {}
} finally {
  await browser?.close();
  stop();
  rmSync(WORK, { recursive: true, force: true });
}
process.exit(ok ? 0 : 1);
