// How switching workspace performs in the cloud web app: from the click on another workspace in the sidebar foot's
// menu until that workspace's sidebar and its chat last open have shown and the page has stopped changing: when the
// sidebar first lists its chats (`sidebar`), how many frames show a page of nothing (`blank`: no chat messages and no
// composer), and the frames dropped and long on the way. It goes back and forth between the first two workspaces in
// the menu.
//
// It runs against a dev cloud (cloud/test/dev.ts) whose --user has at least two workspaces, each with a station and
// chats; --dist serves a build's web app against it, as test/perf/chat.mjs does (see there).
//
//   node test/perf/workspace.mjs --url http://127.0.0.1:8877 [--dist dist] [--runs 6] [--out a.json]
//   node test/perf/workspace.mjs --compare a.json b.json
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { chromium, playwright, proxy } from "./rig.mjs";

const { values: opt } = parseArgs({
  options: {
    url: { type: "string", default: "http://127.0.0.1:8787" },
    user: { type: "string", default: "alice" },
    dist: { type: "string" },
    runs: { type: "string", default: "6" },
    out: { type: "string" },
    headless: { type: "boolean", default: false },
    compare: { type: "boolean", default: false },
  },
  allowPositionals: true,
});

const COLUMNS = ["sidebar", "settled", "blank", "dropped", "worst", "long", "blocking"];

if (opt.compare) {
  const [a, b] = process.argv.slice(2).filter((x) => x.endsWith(".json")).map((f) => JSON.parse(readFileSync(f, "utf8")));
  const ma = medians(a.runs), mb = medians(b.runs);
  console.log(COLUMNS.map((c) => `${c} ${ma[c]} → ${mb[c]}`).join("  "));
  process.exit(0);
}

const cloud = new URL(opt.url);
let server;
let origin = cloud.origin;
if (opt.dist) {
  const root = join(opt.dist, "cloud-web");
  if (!existsSync(join(root, "web.html"))) throw new Error(`no ${root}/web.html`);
  server = await proxy(root, cloud);
  origin = `http://127.0.0.1:${server.address().port}`;
}

const pw = await playwright();
const browser = await pw.chromium.launch({ headless: opt.headless, executablePath: chromium(), args: ["--disable-renderer-backgrounding", "--disable-background-timer-throttling"] });
const context = await browser.newContext({ viewport: { width: 1512, height: 900 }, deviceScaleFactor: 2, locale: "zh-CN" });
await context.addInitScript(instrument);
const r = await fetch(`${origin}/__dev/account?user=${encodeURIComponent(opt.user)}`);
if (!r.ok) throw new Error(`/__dev/account answered ${r.status}`);
const account = await r.json();
await context.addInitScript((a) => {
  if (!localStorage.getItem("stillfail.accounts")) localStorage.setItem("stillfail.accounts", JSON.stringify([a]));
}, account);
const page = await context.newPage();
page.on("pageerror", (e) => console.error("page error:", e.message));
await page.goto(`${origin}/`, { timeout: 60_000 });
await page.waitForURL(/\/w\/[^/]+\/(new|s\/.+\/chats\/)/, { timeout: 60_000 });
await page.waitForTimeout(5000);
/** On a new chat page (a workspace not opened on this browser yet), its sidebar's first chat: what it goes back to. */
async function inChat() {
  const ws = new URL(page.url()).pathname.match(/^\/w\/[^/]+/)[0];
  if (!page.url().endsWith("/new")) return false;
  await page.locator(`nav a[href^="${ws}/s/"][href*="/chats/"]`).first().click();
  await page.waitForURL(/\/chats\//);
  await page.waitForTimeout(3000);
  return true;
}
await inChat();

const runs = [];
try {
  for (let i = 0; i < Number(opt.runs) + 2; i++) {
    const from = new URL(page.url()).pathname.match(/^\/w\/[^/]+/)[0];
    await page.waitForTimeout(1500);
    // The trigger at the sidebar's foot: the workspace's name.
    await page.locator('nav [aria-haspopup="menu"]').last().click();
    // The other workspace: of the menu's rows, the one not in use with a key to it (not 新建/添加账号).
    const item = page.locator('[role="menuitem"]:not([aria-current])').filter({ hasText: /⌃|Alt\+/ }).first();
    await item.waitFor().catch(async (e) => {
      await page.screenshot({ path: "/tmp/wsc-rig/fail.png" });
      console.error(await page.evaluate(() => [...document.querySelectorAll('[aria-haspopup], [role="menuitem"]')].map((e) => e.outerHTML.slice(0, 200)).join("\n")));
      throw e;
    });
    await page.waitForTimeout(300);
    await page.evaluate(() => window.__perf.start());
    await item.click();
    await page.waitForURL((u) => !u.pathname.startsWith(from + "/") && /\/(chats\/|new$)/.test(u.pathname), { timeout: 30_000 });
    const to = new URL(page.url()).pathname.match(/^\/w\/[^/]+/)[0];
    await page.waitForFunction((to) => window.__perf.done(to), to, { timeout: 30_000, polling: 100 });
    const run = await page.evaluate((to) => window.__perf.stop(to), to);
    if (await inChat()) { i--; continue; }
    // The first two each way warm the page's code and the core's views up: not counted.
    if (i >= 2) runs.push({ from, to, ...run });
    process.stderr.write(`· ${from} → ${to}: ${JSON.stringify(run)}\n`);
  }
} finally {
  await browser.close();
  server?.close();
}
const m = medians(runs);
console.log(COLUMNS.map((c) => `${c} ${m[c]}`).join("  "));
if (opt.out) writeFileSync(opt.out, JSON.stringify({ origin, dist: opt.dist ?? null, at: new Date().toISOString(), runs }, null, 2));
process.exit(0);

function medians(rs) {
  return Object.fromEntries(COLUMNS.map((c) => {
    const s = rs.map((x) => x[c]).filter((x) => typeof x === "number").sort((a, b) => a - b);
    return [c, s.length ? s[Math.floor((s.length - 1) / 2)] : null];
  }));
}

/** In the page: each frame, what shows; long animation frames; when the page last changed. */
function instrument() {
  const chatRows = () => document.querySelectorAll('section[aria-label="对话"] [data-ts]').length;
  const sidebarRows = (ws) => document.querySelectorAll(`nav a[href^="${ws}/s/"][href*="/chats/"]`).length;
  const perf = (window.__perf = {
    frames: null, samples: [], loafs: [], changed: 0, clicked: 0,
    start() {
      perf.frames = [performance.now()];
      perf.samples = [];
      perf.loafs = [];
      perf.changed = performance.now();
      const tick = (t) => {
        if (!perf.frames) return;
        perf.frames.push(t);
        const ws = location.pathname.match(/^\/w\/[^/]+/)?.[0] ?? "";
        perf.samples.push({ t, ws, chat: chatRows(), composer: !!document.querySelector("main textarea"), side: sidebarRows(ws) });
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    },
    /** Whether `to` has shown its sidebar and chat and the page has held still for 800ms. */
    done(to) {
      return sidebarRows(to) > 0 && (chatRows() > 0 || !!document.querySelector("main textarea")) && performance.now() - perf.changed > 800;
    },
    stop(to) {
      const f = perf.frames ?? [];
      perf.frames = null;
      const gaps = f.slice(1).map((t, i) => t - f[i]).sort((a, b) => a - b);
      const beat = 1000 / 60;
      const after = perf.samples.filter((s) => s.t >= perf.clicked);
      const first = (ok) => { const s = after.find(ok); return s ? Math.round(s.t - perf.clicked) : null; };
      return {
        sidebar: first((s) => s.ws === to && s.side > 0),
        settled: Math.round(perf.changed - perf.clicked),
        blank: after.filter((s) => s.t <= perf.changed && s.chat === 0 && !s.composer).length,
        dropped: gaps.reduce((n, g) => n + Math.max(0, Math.round(g / beat) - 1), 0),
        worst: Math.round(gaps.at(-1) ?? 0),
        long: gaps.filter((g) => g > 50).length,
        blocking: Math.round(perf.loafs.reduce((n, l) => n + l.blockingDuration, 0)),
        busiest: Object.entries(perf.loafs.flatMap((l) => l.scripts).reduce((by, s) => {
          const what = `${s.invoker || s.invokerType} ${s.sourceFunctionName || ""} ${(s.sourceURL || "").split("/").pop()}`.replace(/\s+/g, " ").trim();
          by[what] = (by[what] ?? 0) + s.duration;
          return by;
        }, {})).sort((x, y) => y[1] - x[1]).slice(0, 4).map(([what, ms]) => `${Math.round(ms)}ms ${what}`),
        loafs: perf.loafs.map((l) => Math.round(l.duration)),
      };
    },
  });
  addEventListener("pointerdown", (e) => { perf.clicked = e.timeStamp; }, true);
  new PerformanceObserver((list) => { if (perf.frames) perf.loafs.push(...list.getEntries()); }).observe({ type: "long-animation-frame" });
  new MutationObserver(() => { perf.changed = performance.now(); }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
}
