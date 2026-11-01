// What React draws again for a few everyday things done on a chat's page of the cloud web app, and what that costs:
// for each, the components that rendered (how many times, and why: their own state or a store they read changed, a
// context, or their parent drawing again; and of those last, how many were given the same props, or props different
// only in functions made anew), and the time React spent rendering and the main thread spent busy, with the CPU slowed
// four times (--slow).
//
// Desktop: the side panel (an agent's execution history) opened and closed, the sidebar closed and opened (its
// shortcut), another chat opened from the sidebar and back, a message coming in, a history entry coming in (the panel
// open), and typing in the composer. Phone (--phone): a message coming in, a history entry coming in (its page open),
// typing, and to the chats' list and back.
//
// It needs a build made to be measured, `STILLFAIL_PROFILE=1 vp build --config web/vite.config.ts --mode cloud`
// (into dist/profile/cloud-web: React's profiling build, names not minified), and a dev cloud on studio with a station
// and chats on it (docs: the dev cloud in cloud/test/dev.ts), and two commands that make something come in: --say (a
// message in --chat) and --step (an entry in its agent's history).
//
//   node test/perf/renders.mjs --url <dev cloud> --dist dist/profile --chat <page path> --other <page path> \
//     --say "sh say.sh" --step "sh step.sh" --out main.json
//   node test/perf/renders.mjs --compare main.json branch.json
//
// Options: --user <dev account> (alice), --account <file> (where its sign-in is kept between runs), --runs <n> (3; medians), --slow <n> (4, the CPU's slowdown; 1 for none),
// --phone, --only <op,…>, --top <n> (components listed per thing done, 12), --headless.
import { execSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { chromium, playwright, proxy } from "./rig.mjs";

const { values: opt } = parseArgs({
  options: {
    url: { type: "string", default: "http://127.0.0.1:8787" },
    user: { type: "string", default: "alice" },
    account: { type: "string" },
    dist: { type: "string" },
    chat: { type: "string" },
    other: { type: "string" },
    title: { type: "string" },
    say: { type: "string" },
    step: { type: "string" },
    runs: { type: "string", default: "3" },
    slow: { type: "string", default: "4" },
    phone: { type: "boolean", default: false },
    only: { type: "string" },
    top: { type: "string", default: "12" },
    out: { type: "string" },
    headless: { type: "boolean", default: false },
    compare: { type: "boolean", default: false },
  },
  allowPositionals: true,
});

if (opt.compare) {
  const [a, b] = process.argv.slice(2).filter((x) => x.endsWith(".json")).map((f) => JSON.parse(readFileSync(f, "utf8"))).map((r) => ({ ...r, summary: summarize(r) }));
  if (!a || !b) throw new Error("--compare needs two result files");
  compare(a, b);
  process.exit(0);
}

if (!opt.dist || !opt.chat) throw new Error("--dist and --chat are needed");
if (opt.phone && !opt.title) throw new Error("--phone needs --title, words of the chat's title (its row is tapped)");
const root = join(opt.dist, "cloud-web");
if (!existsSync(join(root, "web.html"))) throw new Error(`no ${root}/web.html: build with STILLFAIL_PROFILE=1`);
const cloud = new URL(opt.url);
const server = await proxy(root, cloud);
const origin = `http://127.0.0.1:${server.address().port}`;
const runs = Number(opt.runs);
const slow = Number(opt.slow);
const top = Number(opt.top);

// ——— in the page: every commit React makes, what in it rendered and why ———

function hook() {
  // React's fiber tags (ReactWorkTags.js) of what is a component of someone's: functions, classes, forwardRef's and
  // memo's (a memo with a compare, 14, is a wrapper whose child is the function: that child is counted).
  const COMPONENT = new Set([0, 1, 11, 15]);
  const PERFORMED_WORK = 1;
  const nameOf = (f) => {
    const t = f.type;
    if (f.tag === 11) return t?.displayName || t?.render?.displayName || t?.render?.name || "ForwardRef";
    return t?.displayName || t?.name || "Anonymous";
  };
  // Why a component drew with its parent not drawing: a context it reads changed, else its own hooks' state (a store's
  // snapshot, useSyncExternalStore's, or its own useState/useReducer).
  const ownReason = (next, prev) => {
    for (let a = next.dependencies?.firstContext, b = prev.dependencies?.firstContext; a; a = a.next, b = b?.next) {
      if (!b || a.memoizedValue !== b.memoizedValue) return "context";
    }
    if (next.tag === 1) return "state";
    let i = 0;
    for (let a = next.memoizedState, b = prev.memoizedState; a && b; a = a.next, b = b.next, i++) {
      if (a.memoizedState !== b.memoizedState && a.queue) return a.queue.getSnapshot ? `store#${i}` : `state#${i}`;
    }
    return "state";
  };
  // Of a component drawn with its parent: were its props the same (memo would have skipped it), different only in
  // functions, only in children (elements made anew), or in what they say.
  const propsDiff = (next, prev) => {
    const a = next.memoizedProps ?? {}, b = prev.memoizedProps ?? {};
    if (a === b) return "same";
    const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
    let fn = false, children = false;
    for (const k of keys) {
      if (Object.is(a[k], b[k])) continue;
      if (k === "children") children = true;
      else if (typeof a[k] === "function" && typeof b[k] === "function") fn = true;
      else return "data";
    }
    return children ? "children" : fn ? "fn" : "same";
  };
  const rc = (window.__renders = {
    on: false, commits: 0, ms: 0, at: [], by: {}, last: 0,
    start() { Object.assign(rc, { on: true, commits: 0, ms: 0, at: [], by: {} }); },
    stop() { rc.on = false; return { commits: rc.commits, ms: Math.round(rc.ms * 10) / 10, by: rc.by }; },
  });
  // `why` of a component drawn by itself names the hook whose state changed (store#3: its fourth hook, a store's).
  const count = (name, why) => {
    const row = (rc.by[name] ??= { renders: 0 });
    if (why !== "mount") row.renders++;
    const [kind, hook] = why.split("#");
    row[kind] = (row[kind] ?? 0) + 1;
    if (hook !== undefined) (row.hooks ??= {})[why] = (row.hooks[why] ?? 0) + 1;
  };
  // Compares the tree just committed with the one before it, as React's DevTools do: a subtree whose child list is the
  // one it had was not visited at all.
  const walk = (next, prev, parentDrew) => {
    let drew = parentDrew;
    if (COMPONENT.has(next.tag)) {
      if (!prev) { count(nameOf(next), "mount"); drew = true; }
      else if ((next.flags & PERFORMED_WORK) !== 0) {
        count(nameOf(next), parentDrew ? propsDiff(next, prev) : ownReason(next, prev));
        drew = true;
      } else drew = false;
    }
    if (prev && next.child === prev.child) return;
    for (let c = next.child; c; c = c.sibling) walk(c, prev ? c.alternate : null, drew);
  };
  const renderers = new Map();
  window.__REACT_DEVTOOLS_GLOBAL_HOOK__ = {
    supportsFiber: true, isDisabled: false, renderers,
    inject(internals) { const id = renderers.size + 1; renderers.set(id, internals); return id; },
    checkDCE() {}, onScheduleFiberRoot() {}, onCommitFiberUnmount() {}, onPostCommitFiberRoot() {},
    onCommitFiberRoot(_id, root) {
      rc.last = performance.now();
      if (!rc.on) return;
      rc.commits++;
      rc.at.push(rc.last);
      // The profiling build times the render that made this commit: the root's actualDuration.
      rc.ms += root.current.actualDuration ?? 0;
      const current = root.current;
      walk(current, current.alternate, false);
    },
  };
}

// ——— the browser ———

const pw = await playwright();
const browser = await pw.chromium.launch({ headless: opt.headless, executablePath: chromium(), args: ["--disable-renderer-backgrounding", "--disable-background-timer-throttling"] });
const view = opt.phone
  ? { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, locale: "zh-CN" }
  : { viewport: { width: 1512, height: 900 }, deviceScaleFactor: 2, locale: "zh-CN" };
let account;

async function fresh() {
  const context = await browser.newContext(view);
  await context.addInitScript(hook);
  // Asked once, and kept in --account's file when given: the dev cloud lets few sign-ins through.
  if (account === undefined && opt.account && existsSync(opt.account)) account = JSON.parse(readFileSync(opt.account, "utf8"));
  if (account === undefined) {
    const r = await fetch(`${origin}/__dev/account?user=${encodeURIComponent(opt.user)}`);
    if (!r.ok) throw new Error(`${origin}/__dev/account answered ${r.status}`);
    account = await r.json();
    if (opt.account) writeFileSync(opt.account, JSON.stringify(account));
  }
  await context.addInitScript((a) => {
    if (!localStorage.getItem("stillfail.accounts")) localStorage.setItem("stillfail.accounts", JSON.stringify([a]));
  }, account);
  const page = await context.newPage();
  page.on("pageerror", (e) => console.error("page error:", e.message));
  const cdp = await context.newCDPSession(page);
  return { context, page, cdp };
}

/** Until React has committed nothing for `quiet` ms (at least `least` ms after it began, `most` at the most). */
async function settle(page, { quiet = 700, least = 300, most = 8000 } = {}) {
  const t0 = Date.now();
  await page.waitForTimeout(least);
  while (Date.now() - t0 < most) {
    const idle = await page.evaluate(() => performance.now() - window.__renders.last);
    if (idle >= quiet) return;
    await page.waitForTimeout(100);
  }
}

/**
 * Does `act` with the CPU slowed and React's commits counted, until the page settles: what rendered, React's render
 * time, and the main thread's busy time (its tasks, from a trace).
 */
async function measure(page, cdp, act, settleOpts) {
  await settle(page);
  const events = [];
  const collect = (e) => events.push(...e.value);
  cdp.on("Tracing.dataCollected", collect);
  await cdp.send("Tracing.start", { categories: "disabled-by-default-devtools.timeline,devtools.timeline", transferMode: "ReportEvents" });
  if (slow > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: slow });
  await page.evaluate(() => window.__renders.start());
  await act();
  await settle(page, settleOpts);
  const renders = await page.evaluate(() => window.__renders.stop());
  if (slow > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: 1 });
  const done = new Promise((resolve) => cdp.once("Tracing.tracingComplete", resolve));
  await cdp.send("Tracing.end");
  await done;
  cdp.off("Tracing.dataCollected", collect);
  // The renderer's main thread: its tasks, the longest of them.
  const main = events.find((e) => e.name === "thread_name" && e.args?.name === "CrRendererMain");
  const tasks = events.filter((e) => main && e.pid === main.pid && e.tid === main.tid && e.name === "RunTask" && e.ph === "X" && e.dur);
  const busy = tasks.reduce((n, e) => n + e.dur, 0) / 1000;
  const longest = tasks.reduce((n, e) => Math.max(n, e.dur), 0) / 1000;
  return { ...renders, busy: Math.round(busy), longest: Math.round(longest) };
}

const sh = (command) => execSync(command, { stdio: ["ignore", "ignore", "inherit"] });
const composer = (page) => page.locator("textarea").filter({ visible: true }).last();

/** The things done, each one measured on a page as the one before left it. */
const DESKTOP = [
  ["panelOpen", async (page) => { await page.getByRole("button", { name: "打开侧栏" }).click(); }, { least: 600 }],
  ["panelClose", async (page) => { await page.getByRole("button", { name: "收起侧栏" }).click(); }, { least: 600 }],
  ["sidebarClose", async (page) => { await page.keyboard.press("Meta+Backslash"); }, { least: 600 }],
  ["sidebarOpen", async (page) => { await page.keyboard.press("Meta+Backslash"); }, { least: 600 }],
  ["switchAway", async (page) => { await page.locator(`a[href="${opt.other}"]`).first().click(); }, { least: 600 }],
  ["switchBack", async (page) => { await page.locator(`a[href="${opt.chat}"]`).first().click(); }, { least: 600 }],
  ["message", async () => { if (opt.say) sh(opt.say); }, { least: 1500 }],
  ["historyEntry", async () => { if (opt.step) sh(opt.step); }, { least: 1500 }, async (page) => {
    // Its history open beside the chat, the panel closed again after.
    await page.getByRole("button", { name: "打开侧栏" }).click();
    return async () => { await page.getByRole("button", { name: "收起侧栏" }).click(); };
  }],
  ["typing", async (page) => { await page.keyboard.type("hello still.fail", { delay: 60 }); }, { least: 300 }, async (page) => {
    await composer(page).click();
    return async () => { await composer(page).fill(""); };
  }],
];

const PHONE = [
  // From the chats' list (where a phone opens) to the chat, by its row (--title: words of its title).
  ["toChat", async (page) => { await page.getByRole("button").filter({ hasText: opt.title }).first().tap(); }, { least: 900 }],
  ["message", async () => { if (opt.say) sh(opt.say); }, { least: 1500 }],
  ["typing", async (page) => { await page.keyboard.type("hello still.fail", { delay: 60 }); }, { least: 300 }, async (page) => {
    await composer(page).tap();
    return async () => { await composer(page).fill(""); await page.evaluate(() => document.activeElement?.blur()); };
  }],
  // Back to the list, as the browser's back does.
  ["toList", async (page) => { await page.goBack(); }, { least: 900 }],
  // Last: its page is opened afresh (the agent's history, over the chat), the list and the chat gone.
  ["historyEntry", async () => { if (opt.step) sh(opt.step); }, { least: 1500 }, async (page) => {
    await page.goto(`${origin}${opt.chat}/history/${encodeURIComponent(decodeURIComponent(opt.chat.split("/chats/")[1]))}`, { timeout: 60_000 });
    await page.waitForTimeout(4000);
    return null;
  }],
];

const OPS = (opt.phone ? PHONE : DESKTOP).filter(([name]) => !opt.only || opt.only.split(",").includes(name));
const results = { dist: opt.dist, phone: opt.phone, slow, runs, at: new Date().toISOString(), ops: {} };
try {
  for (let i = 0; i < runs; i++) {
    const { context, page, cdp } = await fresh();
    try {
      // The phone opens on the chats' list (it goes to the chat as the first thing done); the desktop on the chat.
      await page.goto(opt.phone ? `${origin}${opt.chat.split("/s/")[0]}` : `${origin}${opt.chat}`, { timeout: 60_000 });
      if (!opt.phone) await page.locator('section[aria-label="对话"] [data-ts]').first().waitFor({ timeout: 60_000 }).catch(() => undefined);
      await page.waitForTimeout(4000);
      for (const [name, act, settleOpts, around] of OPS) {
        const after = around ? await around(page) : null;
        if (around) await page.waitForTimeout(1500);
        const r = await measure(page, cdp, () => act(page), settleOpts);
        (results.ops[name] ??= []).push(r);
        process.stderr.write(`· run ${i + 1} ${name}: ${r.commits} commits, ${Object.values(r.by).reduce((n, x) => n + x.renders, 0)} renders, react ${r.ms}ms, busy ${r.busy}ms\n`);
        if (after) { await after(); await page.waitForTimeout(1500); }
      }
    } finally {
      await context.close();
    }
  }
} finally {
  await browser.close();
  server.close();
}
if (opt.out) writeFileSync(opt.out, JSON.stringify(results, null, 2));
const summary = summarize(results);
print(summary);
if (opt.out) writeFileSync(opt.out, JSON.stringify({ ...results, summary }, null, 2));
process.exit(0);

// ——— the numbers ———

/** The app's own components, by name, as web/src declares them: the rest drawn are libraries' (Radix's, the router's). */
function appNames() {
  const src = new URL("../../web/src/", import.meta.url).pathname;
  const names = new Set();
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      if (e.isDirectory()) walk(join(dir, e.name));
      else if (e.name.endsWith(".tsx")) for (const m of readFileSync(join(dir, e.name), "utf8").matchAll(/function ([A-Z]\w*)\s*[(<]/g)) names.add(m[1]);
    }
  };
  walk(src);
  return names;
}
var app; // var: --compare sums up before the module gets here
/** Whether a name (as the bundle has it, a clash's suffix let go: ChatPane$1) is one of the app's components. */
function isApp(n) {
  app ??= appNames();
  return app.has(n.replace(/\$\d+$/, ""));
}

function median(xs) {
  const s = xs.filter((x) => typeof x === "number").sort((a, b) => a - b);
  return s.length ? s[Math.floor((s.length - 1) / 2)] : 0;
}

/** Per thing done: medians over the runs, in all and per component. */
function summarize(r) {
  const out = {};
  for (const [name, list] of Object.entries(r.ops)) {
    const names = new Set(list.flatMap((x) => Object.keys(x.by)));
    const by = {};
    for (const n of names) {
      const row = {};
      for (const k of ["renders", "mount", "store", "state", "context", "same", "fn", "children", "data"]) row[k] = median(list.map((x) => x.by[n]?.[k] ?? 0));
      const hooks = [...new Set(list.flatMap((x) => Object.keys(x.by[n]?.hooks ?? {})))];
      if (hooks.length) row.hooks = hooks.join(" ");
      row.app = isApp(n);
      if (row.renders || row.mount) by[n] = row;
    }
    const total = (k, only = () => true) => median(list.map((x) => Object.entries(x.by).filter(([n]) => only(n)).reduce((s, [, c]) => s + (c[k] ?? 0), 0)));
    out[name] = {
      commits: median(list.map((x) => x.commits)),
      // Every component drawn (the libraries' within them too), and of the app's own.
      renders: total("renders"), appRenders: total("renders", isApp), mounts: total("mount"),
      // The app's components drawn with their parent though given the same props, or props different only in functions made anew.
      needless: median(list.map((x) => Object.entries(x.by).filter(([n]) => isApp(n)).reduce((s, [, c]) => s + (c.same ?? 0) + (c.fn ?? 0), 0))),
      reactMs: median(list.map((x) => x.ms)), busyMs: median(list.map((x) => x.busy)), longestMs: median(list.map((x) => x.longest)),
      by,
    };
  }
  return out;
}

function print(summary) {
  for (const [name, s] of Object.entries(summary)) {
    console.log(`\n${name}: ${s.commits} commits, ${s.renders} renders (app ${s.appRenders}, of them ${s.needless} needless), ${s.mounts} mounts, react ${s.reactMs}ms, busy ${s.busyMs}ms, longest task ${s.longestMs}ms`);
    const rows = Object.entries(s.by).filter(([, c]) => c.app).sort((a, b) => b[1].renders - a[1].renders).slice(0, top);
    for (const [n, c] of rows) {
      const why = ["store", "state", "context", "same", "fn", "children", "data"].filter((k) => c[k]).map((k) => `${k} ${c[k]}`).join(", ");
      console.log(`  ${String(c.renders).padStart(5)}  ${n.padEnd(28)} ${why}${c.mount ? `  (+${c.mount} mounted)` : ""}`);
    }
    // Who set it going: what drew with its parent not drawing.
    const origins = Object.entries(s.by).filter(([, c]) => c.app && (c.store || c.state || c.context)).map(([n, c]) => `${n} (${["store", "state", "context"].filter((k) => c[k]).map((k) => `${k} ${c[k]}`).join(", ")}${c.hooks ? `: ${c.hooks}` : ""})`);
    if (origins.length) console.log(`  set off by: ${origins.join(" · ")}`);
  }
}

function compare(a, b) {
  console.log(`A ${a.dist} (${a.at})\nB ${b.dist} (${b.at})\n`);
  console.log("op            renders        app renders    needless       commits    react ms       busy ms        longest ms");
  for (const [name, x] of Object.entries(a.summary)) {
    const y = b.summary[name];
    if (!y) continue;
    const cell = (k) => `${x[k]} → ${y[k]}`.padEnd(15);
    console.log(`${name.padEnd(14)}${cell("renders")}${cell("appRenders")}${cell("needless")}${`${x.commits} → ${y.commits}`.padEnd(11)}${cell("reactMs")}${cell("busyMs")}${cell("longestMs")}`);
  }
}
