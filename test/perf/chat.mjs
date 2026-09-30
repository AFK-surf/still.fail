// NOT WORKING AS IT STANDS: it was written for a station's own page (http://127.0.0.1:4760/admin/ and its /admin/api),
// and a station serves no page any more (its loopback port only sends old /admin links to still.fail cloud). To use it
// again it has to be pointed (--url) at the cloud web app's pages of a workspace on a dev cloud (/w/<ws>/s/<station>/…,
// signed in, cloud/test/dev.ts), pick its chats from the page or the core rather than /admin/api/chats, and --dist has
// to serve dist/cloud-web at / against that dev cloud instead of <dir>/admin under /admin/. Until then it stops at once.
//
// How a chat page performs on a station's real chats: opening one (a fresh page load, a switch to it from the new
// chat page through the sidebar, the way people do, and a hop to it from another chat once the sidebar's chats are on
// the device: how many frames show no messages between the two), and scrolling it from the latest message to the first and
// back. It reads what a station has; it sends nothing, though opening a chat marks it read as it would for a person.
//
//   node test/perf/chat.mjs                       the local station's page (http://127.0.0.1:4760/admin/), its 3 longest chats
//   node test/perf/chat.mjs --dist <dir>          a build's pages instead (<dir>/admin, from `pnpm build`), against the same station
//   node test/perf/chat.mjs --out main.json       also keep the numbers; --compare main.json branch.json sets two side by side
//   node test/perf/chat.mjs --dist <dir> --serve  only serve the build against the station, to look at or profile by hand
//
// Options: --url <station's admin page>, --chats <n>, --chat <key> (repeatable, archived ones too; switching is only
// measured for chats in the sidebar), --runs <n> (3), --headless (frame times there are software-drawn: not to be trusted).
// Playwright comes from PLAYWRIGHT_MODULE, else playwright-core or playwright; CHROMIUM_EXECUTABLE picks the browser.
import { createServer, request } from "node:http";
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { extname, join, normalize } from "node:path";
import { connect } from "node:net";
import { parseArgs } from "node:util";

const { values: opt } = parseArgs({
  options: {
    url: { type: "string", default: "http://127.0.0.1:4760/admin/" },
    dist: { type: "string" },
    chats: { type: "string", default: "3" },
    chat: { type: "string", multiple: true },
    runs: { type: "string", default: "3" },
    out: { type: "string" },
    headless: { type: "boolean", default: false },
    compare: { type: "boolean", default: false },
    serve: { type: "boolean", default: false },
  },
  allowPositionals: true,
});

// What each measurement reports, in order (medians over the runs).
const COLUMNS = {
  open: ["firstRow", "settled", "dropped", "worst", "long", "blocking", "rows", "nodes", "heapMB"],
  switch: ["firstRow", "settled", "dropped", "worst", "long", "blocking"],
  hop: ["firstRow", "settled", "empty", "emptyMs", "dropped", "long"],
  scroll: ["frames", "dropped", "p95", "worst", "long", "blocking", "replaced", "height", "rows"],
};

if (opt.compare) {
  const [a, b] = process.argv.slice(2).filter((x) => x.endsWith(".json")).map((f) => ({ f, r: JSON.parse(readFileSync(f, "utf8")) }));
  if (!a || !b) throw new Error("--compare needs two result files");
  compare(a, b);
  process.exit(0);
}

const station = new URL(opt.url);
const runs = Number(opt.runs);
// Comparing results kept from before (above) still works; measuring does not (the note at the top).
console.error("test/perf/chat.mjs measures a station's own page, which stations no longer serve: see the note at its top");
process.exit(1);

// A build's pages, served here, with everything else (its API, the core's socket) passed on to the station.
let server;
let base = station;
if (opt.dist) {
  const root = join(opt.dist, "admin");
  if (!existsSync(join(root, "index.html"))) throw new Error(`no ${root}/index.html: --dist is the directory holding admin/`);
  server = await proxy(root);
  base = new URL(`http://127.0.0.1:${server.address().port}/admin/`);
  if (opt.serve) {
    console.log(`${base.href}  (${opt.dist} against ${station.href})`);
    await new Promise(() => {});
  }
}

const chats = await pick();
/** Where a scroll is, for when it never gets there. */
let where = "";
const pw = await playwright();
const browser = await pw.chromium.launch({ headless: opt.headless, executablePath: chromium(), args: ["--disable-renderer-backgrounding", "--disable-background-timer-throttling"] });
const results = { url: base.href, station: station.href, dist: opt.dist ?? null, at: new Date().toISOString(), runs, chats: [] };
try {
  for (const chat of chats) {
    const row = { key: chat.key, title: chat.title, messages: chat.messages, open: [], switch: [], hop: [], scroll: [] };
    for (let i = 0; i < runs; i++) {
      const context = await browser.newContext({ viewport: { width: 1512, height: 900 }, deviceScaleFactor: 2 });
      await context.addInitScript(instrument);
      const page = await context.newPage();
      page.on("pageerror", (e) => console.error("page error:", e.message));
      try {
        // A run that hangs (a chat that never settles, a list that never reaches its top) fails instead of waiting forever.
        let doing = "opening";
        const work = (async () => {
          row.open.push(await open(page, chat));
          doing = "scrolling";
          row.scroll.push(await scroll(page));
          doing = "switching";
          if (chat.listed) row.switch.push(await switchTo(page, chat));
          doing = "hopping";
          if (chat.listed && chat.from) row.hop.push(await hop(page, chat));
        })();
        work.catch(() => {});
        let timer;
        await Promise.race([work, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`run ${i + 1} of ${chat.key} took over 3 minutes ${doing} (${where})`)), 180_000); })]).finally(() => clearTimeout(timer));
        process.stderr.write(`· ${chat.key} run ${i + 1}/${runs}\n`);
      } catch (error) {
        // One run gone wrong (a page that never loaded on a busy machine) is left out, said here and counted.
        process.stderr.write(`· ${chat.key} run ${i + 1}/${runs} failed: ${String(error.message ?? error).split("\n")[0]}\n`);
        row.failed = (row.failed ?? 0) + 1;
      } finally {
        await context.close();
      }
    }
    results.chats.push(row);
    report(row);
  }
} finally {
  await browser.close();
  server?.close();
}
if (opt.out) writeFileSync(opt.out, JSON.stringify(results, null, 2));
// The core's sockets passed on to the station (--dist) stay open: done is done.
process.exit(0);

// ——— the measurements ———

/** A fresh page load of the chat, until its messages stop changing. */
async function open(page, chat) {
  await page.goto(new URL(`chats/${encodeURIComponent(chat.key)}`, base).href, { waitUntil: "domcontentloaded", timeout: 60_000 });
  const t = await settled(page, 0);
  return { ...t, ...(await page.evaluate(() => window.__perf.stop())), ...(await size(page)) };
}

/** From the new chat page, a click on the chat in the sidebar, until its messages stop changing. */
async function switchTo(page, chat) {
  await page.goto(new URL("new", base).href, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await page.locator("textarea").first().waitFor();
  await page.waitForTimeout(1500);
  const link = page.locator(`a[href$="/chats/${encodeURIComponent(chat.key)}"]`).first();
  await link.waitFor();
  await page.evaluate(() => window.__perf.start());
  await link.click();
  const at = await page.evaluate(() => window.__perf.clicked);
  const t = await settled(page, at);
  return { ...t, ...(await page.evaluate(() => window.__perf.stop())) };
}

/**
 * From another chat, a click on this one in the sidebar, once what the sidebar lists is on the device (read in the
 * background after the page loads). `empty`: frames with no messages on screen between the click and this chat's.
 */
async function hop(page, chat) {
  await page.goto(new URL(`chats/${encodeURIComponent(chat.from)}`, base).href, { waitUntil: "domcontentloaded", timeout: 60_000 });
  await settled(page, 0);
  await page.waitForTimeout(8000);
  const link = page.locator(`a[href$="/chats/${encodeURIComponent(chat.key)}"]`).first();
  await link.waitFor();
  await page.evaluate(() => window.__perf.start());
  await link.click();
  const at = await page.evaluate(() => window.__perf.clicked);
  const t = await settled(page, at);
  const empty = await page.evaluate(() => {
    const s = window.__perf.samples.filter((x) => x.t >= window.__perf.clicked);
    const blank = s.filter((x) => x.rows === 0);
    return { empty: blank.length, emptyMs: blank.length ? Math.round(blank.at(-1).t - blank[0].t + 1000 / 60) : 0 };
  });
  return { ...t, ...empty, ...(await page.evaluate(() => window.__perf.stop())) };
}

/** From the latest message up to the first (loading older pages on the way), and back down, by the wheel. */
async function scroll(page) {
  const box = await page.evaluate(() => {
    const list = window.__perf.list();
    const r = list.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 3 };
  });
  await page.mouse.move(box.x, box.y);
  await page.waitForTimeout(500);
  await page.evaluate(() => window.__perf.start());
  const start = Date.now();
  let steps = 0;
  // Up: until the top holds for a while (no older page came in).
  for (let still = 0; still < 20 && steps < 2000; steps++) {
    await page.mouse.wheel(0, -120);
    await page.waitForTimeout(16);
    const top = await page.evaluate(() => window.__perf.list().scrollTop);
    where = `${top}px from the top, going up`;
    still = top <= 0 ? still + 1 : 0;
  }
  for (let still = 0; still < 20 && steps < 4000; steps++) {
    await page.mouse.wheel(0, 120);
    await page.waitForTimeout(16);
    const left = await page.evaluate(() => { const l = window.__perf.list(); return l.scrollHeight - l.clientHeight - l.scrollTop; });
    where = `${left}px from the bottom, going down`;
    still = left <= 2 ? still + 1 : 0;
  }
  const height = await page.evaluate(() => window.__perf.list().scrollHeight);
  return { steps, height, took: Date.now() - start, ...(await page.evaluate(() => window.__perf.stop())), ...(await size(page)) };
}

/** When the chat's first message showed, and when its list last changed before holding still for 800ms. */
async function settled(page, from) {
  await page.waitForFunction(() => window.__perf.firstRow !== null, null, { timeout: 30000 });
  await page.waitForFunction(() => performance.now() - window.__perf.changed > 800, null, { timeout: 30000, polling: 100 });
  return page.evaluate((from) => ({ firstRow: Math.round(window.__perf.firstRow - from), settled: Math.round(window.__perf.changed - from) }), from);
}

async function size(page) {
  return page.evaluate(() => ({
    rows: document.querySelectorAll('[aria-label="对话"] [data-ts]').length,
    nodes: document.getElementsByTagName("*").length,
    heapMB: Math.round((performance.memory?.usedJSHeapSize ?? 0) / 1e5) / 10,
  }));
}

/** In the page: frames (rAF), long animation frames, and when the chat's list shows and changes. */
function instrument() {
  const perf = (window.__perf = {
    frames: null, samples: [], loafs: [], firstRow: null, changed: 0, clicked: 0, replaced: 0,
    list() {
      const row = document.querySelector('[aria-label="对话"] [data-ts]');
      for (let el = row; el; el = el.parentElement) if (el.scrollHeight > el.clientHeight && /auto|scroll/.test(getComputedStyle(el).overflowY)) return el;
      throw new Error("no scrolling list");
    },
    start() {
      perf.frames = [performance.now()];
      perf.samples = [];
      perf.loafs = [];
      perf.replaced = 0;
      perf.firstRow = null;
      perf.changed = performance.now();
      // Each frame, how many messages are on screen.
      const tick = (t) => {
        if (!perf.frames) return;
        perf.frames.push(t);
        perf.samples.push({ t, rows: document.querySelectorAll('[aria-label="对话"] [data-ts]').length });
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    },
    stop() {
      const f = perf.frames ?? [];
      perf.frames = null;
      const gaps = f.slice(1).map((t, i) => t - f[i]).sort((a, b) => a - b);
      const beat = 1000 / 60;
      const at = (q) => Math.round(gaps[Math.min(gaps.length - 1, Math.floor(q * gaps.length))] ?? 0);
      return {
        frames: gaps.length,
        dropped: gaps.reduce((n, g) => n + Math.max(0, Math.round(g / beat) - 1), 0),
        p95: at(0.95),
        worst: Math.round(gaps.at(-1) ?? 0),
        long: gaps.filter((g) => g > 50).length,
        blocking: Math.round(perf.loafs.reduce((n, l) => n + l.blockingDuration, 0)),
        // Messages taken out of the list and drawn anew (none should be: older pages come in above what is there).
        replaced: perf.replaced,
        // What the long frames ran, the most time first: where to look.
        busiest: Object.entries(perf.loafs.flatMap((l) => l.scripts).reduce((by, s) => {
          const what = `${s.invoker || s.invokerType} ${s.sourceFunctionName || ""} ${(s.sourceURL || "").split("/").pop()}`.replace(/\s+/g, " ").trim();
          by[what] = (by[what] ?? 0) + s.duration;
          return by;
        }, {})).sort((x, y) => y[1] - x[1]).slice(0, 5).map(([what, ms]) => `${Math.round(ms)}ms ${what}`),
      };
    },
  });
  perf.start();
  addEventListener("pointerdown", (e) => { perf.clicked = e.timeStamp; }, true);
  new PerformanceObserver((list) => { if (perf.frames) perf.loafs.push(...list.getEntries()); }).observe({ type: "long-animation-frame" });
  new MutationObserver((records) => {
    const pane = document.querySelector('[aria-label="对话"]');
    if (!pane || !records.some((r) => pane.contains(r.target))) return;
    perf.changed = performance.now();
    for (const r of records) for (const n of r.removedNodes) if (n.nodeType === 1 && pane.contains(r.target)) perf.replaced += n.matches("[data-ts]") ? 1 : n.querySelectorAll("[data-ts]").length;
    if (perf.firstRow === null && pane.querySelector("[data-ts]")) perf.firstRow = perf.changed;
  }).observe(document, { subtree: true, childList: true, attributes: true, characterData: true });
}

// ——— which chats ———

async function pick() {
  const listed = await (await fetch(new URL("api/chats", station))).json();
  const archived = opt.chat ? await (await fetch(new URL("api/chats?archived=1", station))).json() : [];
  // The chat a hop starts from: the sidebar's first other one.
  const from = (c) => listed.find((x) => x.id !== c.id)?.id ?? null;
  const describe = (c, inSidebar) => ({ key: c.id, title: c.title ?? "", messages: c.last?.seq ?? 0, listed: inSidebar, from: from(c) });
  if (opt.chat) {
    return opt.chat.map((key) => {
      const c = listed.find((x) => x.id === key) ?? archived.find((x) => x.id === key);
      if (!c) throw new Error(`no chat ${key} on ${station.href}`);
      return describe(c, listed.includes(c));
    });
  }
  return listed.map((c) => describe(c, true)).sort((a, b) => b.messages - a.messages).slice(0, Number(opt.chats));
}

// ——— the output ———

function median(xs) {
  const s = xs.filter((x) => typeof x === "number").sort((a, b) => a - b);
  return s.length ? s[Math.floor((s.length - 1) / 2)] : null;
}


function medians(row) {
  return Object.fromEntries(Object.entries(COLUMNS).map(([k, cols]) => [k, row[k]?.length ? Object.fromEntries(cols.map((c) => [c, median(row[k].map((r) => r[c]))])) : null]));
}

function report(row) {
  console.log(`\n${row.title.slice(0, 40) || row.key}  (${row.key}, ${row.messages} messages; medians of ${runs})`);
  for (const [k, m] of Object.entries(medians(row))) {
    if (!m) continue;
    console.log(`  ${k.padEnd(7)} ${Object.entries(m).map(([c, v]) => `${c} ${v}`).join("  ")}`);
    // The busiest of the run that blocked the median time.
    const run = row[k].find((r) => r.blocking === m.blocking);
    if (run?.busiest?.length) console.log(`          busiest: ${run.busiest.slice(0, 3).join(" · ")}`);
  }
}

function compare(a, b) {
  console.log(`A ${a.f}: ${a.r.dist ?? a.r.url}\nB ${b.f}: ${b.r.dist ?? b.r.url}`);
  for (const ra of a.r.chats) {
    const rb = b.r.chats.find((c) => c.key === ra.key);
    if (!rb) continue;
    const ma = medians(ra), mb = medians(rb);
    console.log(`\n${ra.title.slice(0, 40) || ra.key}  (${ra.messages} messages)`);
    for (const k of Object.keys(COLUMNS)) {
      if (!ma[k] || !mb[k]) continue;
      console.log(`  ${k.padEnd(7)} ${COLUMNS[k].map((c) => `${c} ${ma[k][c]} → ${mb[k][c]}`).join("  ")}`);
    }
  }
}

// ——— the browser, and a build's pages ———

async function playwright() {
  for (const name of [process.env.PLAYWRIGHT_MODULE, "playwright-core", "playwright"].filter(Boolean)) {
    try { return await import(name); } catch {}
  }
  throw new Error("no Playwright: `npm i playwright-core` somewhere Node finds it, or set PLAYWRIGHT_MODULE");
}

function chromium() {
  if (process.env.CHROMIUM_EXECUTABLE) return process.env.CHROMIUM_EXECUTABLE;
  const cache = join(homedir(), "Library/Caches/ms-playwright");
  const found = existsSync(cache) && readdirSync(cache).filter((d) => /^chromium-\d+$/.test(d)).sort().at(-1);
  const app = found && join(cache, found, "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
  return app && existsSync(app) ? app : undefined;
}

function proxy(root) {
  const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".wasm": "application/wasm", ".woff2": "font/woff2", ".webmanifest": "application/manifest+json" };
  const pass = (req, res) => {
    const up = request({ host: station.hostname, port: station.port, path: req.url, method: req.method, headers: { ...req.headers, host: station.host } }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
    up.on("error", () => res.destroy());
    req.pipe(up);
  };
  const s = createServer((req, res) => {
    const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
    // The station's API is the station's; a page route is the build's index; a file there is the build's.
    if (!path.startsWith("/admin/") || path.startsWith("/admin/api/")) return pass(req, res);
    const file = normalize(join(root, path.slice("/admin/".length)));
    const hit = file.startsWith(root) && existsSync(file) && statSync(file).isFile() ? file : !extname(path) ? join(root, "index.html") : null;
    if (!hit) return pass(req, res);
    res.writeHead(200, { "content-type": types[extname(hit)] ?? "application/octet-stream" });
    res.end(readFileSync(hit));
  });
  s.on("upgrade", (req, socket, head) => {
    const up = connect(Number(station.port), station.hostname, () => {
      up.write(`${req.method} ${req.url} HTTP/1.1\r\n${Object.entries({ ...req.headers, host: station.host }).map(([k, v]) => `${k}: ${v}`).join("\r\n")}\r\n\r\n`);
      up.write(head);
      up.pipe(socket);
      socket.pipe(up);
    });
    up.on("error", () => socket.destroy());
    socket.on("error", () => up.destroy());
  });
  return new Promise((resolve) => s.listen(0, "127.0.0.1", () => resolve(s)));
}
