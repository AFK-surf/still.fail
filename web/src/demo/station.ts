// The made-up station behind the demo's chats, and its workspace in still.fail cloud: what the settings, the station's
// page, the accounts and the phone's workspace pages read, so that every page the visitor can open shows something.
// station.json holds the station's views, shaped as a real station's (every value made up), its times counted from
// 0: they are moved to now here.
import data from "./station.json";
import { CHEN, LIN, stamp, STATION, ZHOU, type Runs } from "./fixtures.ts";
import type { ArchiveDay, ArchiveView, Connect, ConnectsView, DriveEntry, DriveFolder, DriveKind, Person } from "../core/shapes.ts";
import { scale } from "../../../client/core-ts/src/views/scale.ts";
import { resourcesView } from "../../../client/core-ts/src/views/resources.ts";

const TIME = /^(at|checkedAt|resetsAt|startedAt|createdAt|endedAt|lastActiveAt|updatedAt)$/;

/** A copy with every time moved from 0 to now. */
function now<T>(value: T): T {
  const at = Date.now();
  const move = (v: unknown, key = ""): unknown => {
    if (Array.isArray(v)) return v.map((x) => move(x));
    if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, move(x, k)]));
    return typeof v === "number" && TIME.test(key) ? at + v : v;
  };
  return move(value) as T;
}

export const BAN_DETAIL = "Anthropic 拒绝了这个账号（403）This organization has been disabled.";

/** The team's Claude subscription (Max, signed in on the station): refused by Anthropic, as the visitor finds it. */
function subscription(base: Record<string, unknown>) {
  return {
    ...base, machine: false, name: "lin@acme.dev", loginCommand: "",
    quota: { state: "blocked", windows: [], detail: BAN_DETAIL, checkedAt: Date.now() }, checkText: "已停用", checkTone: "red",
  };
}

export const overview = () => {
  const base = now(data.overview);
  return {
    ...base, connects: [slack()], drive: DRIVE,
    // The station's own Claude Code login is the subscription's profile, not offered again.
    // Its Codex login, not a profile yet: offered (the profiles' last section).
    machineLogins: base.machineLogins.filter((l) => l.runtime !== "claude").map((l) => ({ ...l, offered: true })),
    profiles: [subscription(base.profiles[0]!)],
    // As a station sets it out of the box (设置 › 归档).
    archiving: { days: 1, slackDays: 3, reviewed: false, canEdit: true },
  };
};
export const host = () => withMeters(now(data.host));

/** What is left of the machine in the words and figures a station gives its meters (the small boxes in a station's row,
 * the large figures on its page): station.json has their older words only. */
function withMeters<T extends { meters: { short: string; percent: number }[] }>(h: T): T {
  const more: Record<string, { remaining: string; big: string; unit: string; title: string; total: string }> = {
    CPU: { remaining: "空闲 81%", big: "81", unit: "%", title: "CPU 空闲", total: "负载 3.1" },
    内存: { remaining: "剩 36.6 G", big: "36.6", unit: "GB", title: "内存剩", total: "共 64 GB" },
    磁盘: { remaining: "剩 612 G", big: "612", unit: "GB", title: "磁盘剩", total: "共 994 GB" },
  };
  return { ...h, meters: h.meters.map((m) => ({ ...m, left: 100 - m.percent, ...more[m.short] })) };
}

/** How this device reaches the station: straight, quick (the `stationNet` view, its figures). */
export const NET = { path: "直连", via: "direct" as const, rtt: { text: "12 ms", level: "ok" as const }, rttHistory: [11, 12, 14, 12, 11, 12], down: "1.2 KB/s", up: "0.4 KB/s", total: "今天共 ↓ 48 MB · ↑ 3.1 MB" };

/** The station's files (docs/drive.md): every folder from its home, its downloads with what the chats made in them, and
 * the folders pinned. */
const DRIVE = { anywhere: true, home: "/Users/lin", roots: [
  { path: "/Users/lin/Downloads", name: "下载", state: "ok" as const },
  { path: "/Users/lin/code/acme", name: "acme", state: "ok" as const },
  { path: "/Users/lin/Desktop", name: "桌面", state: "ok" as const },
] };
type Made = [name: string, kind: DriveKind, size: number, minutes: number];
const FOLDERS: Record<string, Made[]> = {
  "/Users/lin": [["code", "folder", 0, 30], ["Desktop", "folder", 0, 300], ["Documents", "folder", 0, 2_000], ["Downloads", "folder", 0, 40], ["Movies", "folder", 0, 9_000], ["Pictures", "folder", 0, 9_000]],
  "/Users/lin/code": [["acme", "folder", 0, 30], ["notes", "folder", 0, 4_000]],
  "/Users/lin/code/acme/web": [["src", "folder", 0, 30], ["public", "folder", 0, 900], ["index.html", "html", 1_536, 900], ["vite.config.ts", "code", 812, 1_400], ["package.json", "code", 2_048, 600]],
  "/Users/lin/code/acme/web/src": [["pages", "folder", 0, 30], ["App.tsx", "code", 4_210, 30], ["main.tsx", "code", 620, 2_000], ["styles.css", "code", 3_100, 300]],
  "/Users/lin/code/notes": [["2026-10.md", "markdown", 12_288, 60], ["ideas.md", "markdown", 4_096, 3_000]],
  "/Users/lin/Downloads": [
    ["设计稿", "folder", 0, 40], ["login-375.png", "image", 319_488, 52], ["发版录屏 1014.mp4", "video", 50_541_773, 175],
    ["orders-慢查询.md", "markdown", 9_216, 240], ["export-1013.csv", "csv", 225_280, 1_500], ["合同-2026Q4.pdf", "pdf", 1_468_006, 1_380],
    ["IMG_2041.HEIC", "image", 3_250_585, 2_900],
  ],
  "/Users/lin/code/acme": [["web", "folder", 0, 30], ["api", "folder", 0, 90], ["README.md", "markdown", 4_096, 600], ["package.json", "code", 2_048, 600]],
  "/Users/lin/Desktop": [["截图 10-14.png", "image", 812_000, 300]],
};
const TYPES: Partial<Record<DriveKind, string>> = { image: "image/png", video: "video/mp4", markdown: "text/markdown", csv: "text/csv", pdf: "application/pdf", code: "application/json" };

/** A folder, as the core shows it (client/core-ts/src/drive.ts): its folders first. */
export function driveFolder(root: string, path: string): DriveFolder {
  const at = Date.now();
  const entries = (FOLDERS[path ? `${root.replace(/\/$/, "")}/${path}` : root] ?? []).map(([name, kind, size, minutes]): DriveEntry => {
    const mtime = at - minutes * 60_000;
    const d = new Date(mtime);
    const today = new Date(at).toDateString() === d.toDateString();
    return {
      name, dir: kind === "folder", size, mtime, type: TYPES[kind] ?? "", kind,
      sizeText: kind === "folder" ? "" : size >= 1_048_576 ? `${(size / 1_048_576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`,
      timeText: today ? d.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" }) : `${d.getMonth() + 1}/${d.getDate()}`,
    };
  });
  const folders = entries.filter((e) => e.dir).length;
  return { path, entries, folders, files: entries.length - folders, countText: `${folders} 个文件夹 · ${entries.length - folders} 个文件` };
}
export const stationView = () => {
  const base = now(data.station);
  // (as the core says how it is: up, its agents idle, nothing wrong; views.ts stationState, stationProblems)
  return { ...base, station: STATION, stateText: "空闲", stateBusy: false, problems: [], host: withMeters(base.host), way: { path: NET.path, via: NET.via }, overview: overview() };
};
/** What a Claude agent's model control offers and the account it runs on. */
export const runs = (): Runs => ({ choices: stationView().models as Runs["choices"], profile: overview().profiles[0] as unknown as Runs["profile"] });
/** A connect's Slack app, as the station reads it from Slack: here, with no configuration token to read it with. */
export const slackApp = () => ({ state: "no_config_token" });

/** The Slack app the team talks to its agents through, shaped as the core presents a connect. */
function slack(): Connect {
  return {
    id: "acme-slack", name: "still.fail", team: "Acme", enabled: true, kind: "slack", mode: "multi-session", requireMention: true,
    bind: { runtime: "claude", model: "claude-opus-5-5", effort: "medium", profile: "machine-claude" },
    slack: { appToken: "", botToken: "" },
    connection: { state: "connected", botUserId: "U07EMBER", workspace: { team: "Acme", teamId: "T0ACME", url: "https://acme.slack.com/", botUserId: "U07EMBER", botName: "still.fail" } },
    createdBy: { id: LIN.id, name: LIN.name, shown: LIN.shown }, sessions: 14,
    statusText: "在线", presence: "online", modeText: "多会话", modeShort: "多会话", runtimeText: "Claude Code", runText: "Claude Code · Opus 5.5 · medium", modelName: "Opus 5.5",
    modeWords: {
      multi: { label: "每个 thread 一个会话", description: "在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话" },
      single: { label: "所有 thread 共用一个会话", description: "它看到的所有 thread 都进入同一个会话，适合长期值守的助手" },
      mentionOn: "被 @ 的 thread 中，后续回复无需再 @。", mentionOff: "频道中它可见的每条消息都会进入会话。",
    },
    modeLabel: "每个 thread 一个会话", modeSentence: "在 thread 中 @ 它即开启一个新会话，该 thread 的后续消息都进入此会话", placeText: "Acme",
  };
}

export const connects = (): ConnectsView => ({
  me: { id: "local" }, wait: { reading: false, failing: [], empty: false },
  items: [{ station: STATION, stationName: "Studio", connect: slack(), sessions: [], candidates: [], running: 0, changes: [
    { mode: "multi-session", requireMention: true, changed: false, effects: [], action: "确认更改" },
    { mode: "single-session", requireMention: true, changed: true, effects: ["此后它收到的消息都将进入同一个会话；现有各 thread 的会话不再接收新消息，包括这些 thread 中的回复。记录会保留。", "下一条消息将开始新的单会话；也可在切换后选择已有会话。"], action: "改为单会话" },
    { mode: "single-session", requireMention: false, changed: true, effects: ["此后它收到的消息都将进入同一个会话；现有各 thread 的会话不再接收新消息，包括这些 thread 中的回复。记录会保留。", "下一条消息将开始新的单会话；也可在切换后选择已有会话。", "无需 @：它可见的所有频道和私信中的每条消息都会发送给 agent，用量会明显增加。"], action: "改为单会话" },
  ] }],
});

/**
 * What only a real still.fail instance can do: anything that reaches past the demo (Slack, a model's account, signing in, another
 * machine, still.fail cloud's members). The page offers the real one instead (mount.tsx).
 */
export class NeedsReal extends Error {
  constructor() {
    super("这是演示：这一步要连到真实的服务，请在真实的 still.fail 里做。");
  }
}

/** What the demo's station does itself, changing nothing: a chat's agent woken, stopped, its context compacted or cleared,
 *  or moved to another model. */
const OWN = new Set(["session.warm", "session.stop", "session.evict", "session.compact", "session.clear", "session.settings"]);

/** The station's operations (client/core-ts/src/ops.ts), by name: what is read answers; what would reach out needs a real
 *  ember; what stays in the station answers the overview (what most writes answer with) and changes nothing. */
export function op(name: string): unknown {
  if (name === "memory.get") return data.memory;
  if (name === "machineSessions.list") return now(data.machineSessions);
  // An inline visualization keeps nothing here.
  if (name === "widget.state") return { state: null };
  if (name === "widget.setState") return { ok: true };
  // Where an agent's transcript would be on the demo's machine.
  if (name === "session.transcript") return { path: "/Users/linxiao/.claude/projects/-Users-linxiao-code-shop/7c1e5b2a-4f0d-4c8e-9a61-2b3d5e8f1a90.jsonl" };
  if (OWN.has(name)) return overview();
  throw new NeedsReal();
}

/** The archive, as the core puts it together (client/core-ts/src/views/archive.ts): the station's archived chats by day;
 * with `q`, those that have it; with `limit`, the newest so many. */
export function archive(q = "", limit = 0): ArchiveView {
  const days: ArchiveDay[] = [];
  const today = new Date().setHours(0, 0, 0, 0);
  for (const chat of now(data.archived).sort((a, b) => b.archived.at - a.archived.at)) {
    const at = new Date(chat.archived.at);
    const ago = Math.round((today - new Date(at).setHours(0, 0, 0, 0)) / 86_400_000);
    const label = ago <= 0 ? "今天" : ago === 1 ? "昨天" : ago < 7 ? `星期${"日一二三四五六"[at.getDay()]}` : `${at.getMonth() + 1}月${at.getDate()}日`;
    const item = {
      station: STATION, id: chat.id, session: chat.session, thread: chat.thread, title: chat.title, last: chat.last?.text ?? "", at: chat.archived.at,
      clock: at.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" }), how: "手动归档", deletable: !chat.archived.alone,
    };
    const last = days.at(-1);
    if (last?.label === label) last.items.push(item); else days.push({ label, items: [item] });
  }
  const needle = q.trim().toLowerCase();
  const found = days.flatMap((d) => d.items.filter((i) => !needle || `${i.title}\n${i.last}`.toLowerCase().includes(needle)).map((i) => [d.label, i] as const));
  const shown = limit > 0 ? found.slice(0, limit) : found;
  const kept: ArchiveDay[] = [];
  for (const [label, item] of shown) {
    const last = kept.at(-1);
    if (last?.label === label) last.items.push(item); else kept.push({ label, items: [item] });
  }
  return { days: kept, errors: [], wait: { reading: false, failing: [], empty: found.length === 0 }, total: found.length, more: shown.length < found.length, ...(found.length === 0 ? { note: needle ? "没有匹配的归档对话" : "暂无已归档的对话" } : {}) };
}

/** The workspace's profiles (the core's `profiles`, client/core-ts/src/views/profiles.ts): the station's one account. */
export function profiles() {
  // The subscription as the station shows it (station.json's, refused by Anthropic: subscription() above).
  const p = overview().profiles[0] as typeof data.overview.profiles[number] & ReturnType<typeof subscription>;
  return {
    loading: false, wait: { reading: false, failing: [], empty: false },
    items: [{
      key: `${STATION}/${p.id}`, group: "claude", groupTitle: "Claude 订阅", station: STATION, stationId: "local", stationName: "Studio",
      profile: p, shared: false, host: "local", hostName: "Studio", hostOnline: true, usable: true, where: "仅在 Studio",
      stations: [], editable: true, canShare: true,
      members: [{ station: STATION, stationId: "local", stationName: "Studio", online: true, profileId: p.id, role: "own", about: "自己登录", usable: true, checkText: p.checkText, checkTone: p.checkTone, usedBy: 1 }],
    }],
  };
}

/** What still.fail uses of the machine (the core's `resources`, client/core-ts/src/views/resources.ts, from what a
 * station's GET /resources says), made up: a test run using most, the app and the station a little. */
export function resources() {
  const now = Date.now();
  const proc = (pid: number, name: string, cpu: number, mb: number, watts: number, wakeups: number) => ({ pid, name, cpu, memory: mb * 1e6, watts, wakeups });
  const group = (key: string, kind: string, session: string | null, processes: ReturnType<typeof proc>[]) => ({
    key, kind, session, processes,
    cpu: processes.reduce((n, p) => n + p.cpu, 0), memory: processes.reduce((n, p) => n + p.memory, 0),
    watts: processes.reduce((n, p) => n + p.watts, 0), wakeups: processes.reduce((n, p) => n + p.wakeups, 0),
  });
  const groups = [
    group("chat:p99", "chat", "p99", [proc(41130, "chrome-headless-shell", 61.2, 412, 2.4, 310), proc(41131, "chrome-headless-shell", 18.4, 96, 0.7, 120), proc(40634, "node", 13.4, 188, 0.5, 44), proc(40856, "claude", 6.9, 241, 0.3, 18)]),
    group("app", "app", null, [proc(39480, "still.fail Helper (Renderer)", 12.8, 500, 0.41, 96), proc(39425, "still.fail Helper (GPU)", 7.9, 109, 0.19, 60), proc(39434, "still.fail Helper", 0.8, 238, 0.02, 3), proc(39394, "still.fail", 0.4, 230, 0.02, 4)]),
    group("chat:csv", "chat", "csv", [proc(40631, "python3", 9.6, 322, 0.4, 12), proc(25080, "codex", 1.1, 88, 0.08, 6)]),
    group("station", "station", null, [proc(37148, "node", 1.6, 310, 0.08, 20), proc(1947, "stillfail-station", 0.2, 42, 0.01, 2)]),
  ];
  const sum = (k: "cpu" | "memory" | "watts" | "wakeups") => groups.reduce((n, g) => n + g[k], 0);
  const total = { cpu: sum("cpu"), memory: sum("memory"), watts: sum("watts"), wakeups: sum("wakeups") };
  // The last ten minutes, a look every 5 s, wandering about now.
  const history = Array.from({ length: 120 }, (_, i) => {
    const f = 0.7 + 0.2 * Math.sin(i / 6) + 0.1 * Math.sin(i * 1.3) + (i > 100 ? 0.15 : 0);
    return { at: now - (119 - i) * 5000, cpu: total.cpu * f, memory: total.memory * (0.9 + 0.1 * Math.sin(i / 20)), watts: total.watts * f, wakeups: total.wakeups * (0.6 + 0.4 * Math.abs(Math.sin(i / 4))) };
  });
  const hour = 3_600_000;
  const hours = Array.from({ length: 24 }, (_, i) => ({ at: Math.floor(now / hour) * hour - (23 - i) * hour, joules: { "chat:p99": 3600 * 1.8, app: 3600 * 0.5, station: 3600 * 0.08 } }));
  const chats = { p99: { thread: 4, title: "排查 API p99 变慢" }, csv: { thread: 5, title: "订单导出支持 CSV" } };
  const value = { at: now, everyMs: 5000, counted: true, total, groups, history, hours, chats, machine: { cores: 10, memory: 32 * 1024 ** 3 } };
  return resourcesView([{ address: STATION, name: "Studio", online: true, value: { ok: value } }], now, () => ({ reading: false, failing: [], empty: false }));
}

/** What the agents spent (the core's `usage`, client/core-ts/src/views/usage.ts), made up: the last `days`, each day's
 * cost split by the three people who spent most. */
export function usage(days: number) {
  const today = new Date();
  const people = [LIN, CHEN, ZHOU];
  // Each day's dollars per person, the same pattern however many days (weekends quieter).
  const daily = Array.from({ length: days }, (_, i) => {
    const d = new Date(today.getTime() - (days - 1 - i) * 86_400_000);
    const quiet = d.getDay() === 0 || d.getDay() === 6 ? 0.3 : 1;
    const parts = people.map((_, k) => Math.round((8 + ((i * 7 + k * 5) % 11) * 1.9) * quiet * (3 - k) * 10) / 30);
    const cost = parts.reduce((a, b) => a + b, 0);
    return {
      day: d.toISOString().slice(0, 10), label: `${d.getMonth() + 1}/${d.getDate()}`, today: i === days - 1, cost, costText: money(cost),
      calls: Math.round(cost * 41), callsText: `${Math.round(cost * 41).toLocaleString("en-US")} 次调用`, parts, partsText: parts.map(money),
    };
  });
  const total = daily.reduce((a, d) => a + d.cost, 0);
  const item = (key: string, title: string, share: number, sub?: string, extra: object = {}) => ({
    key, title, ...(sub ? { sub } : {}), cost: total * share, costText: money(total * share), share, shareText: `${Math.round(share * 100)}%`,
    calls: Math.round(total * share * 41), callsText: `${Math.round(total * share * 41).toLocaleString("en-US")} 次`, tokensText: `${(total * share * 0.52).toFixed(1)}M`,
    detail: `${Math.round(total * share * 41).toLocaleString("en-US")} 次 · ${(total * share * 0.52).toFixed(1)}M token`, ...extra,
  });
  return {
    days, loading: false, empty: false, wait: { reading: false, failing: [], empty: false },
    tiles: [
      { label: "折算费用", value: money(total), sub: "按 API 价算" },
      { label: "token", value: `${(total * 0.52).toFixed(1)}M`, sub: `${Math.round(total * 41).toLocaleString("en-US")} 次调用` },
    ],
    series: people.map((p) => ({ key: p.email ?? p.id, name: p.name })),
    daily, max: Math.max(...daily.map((d) => d.cost)), ...scale(Math.max(...daily.map((d) => d.cost))),
    lists: [
      { key: "chats", title: "按对话", items: [
        item("deps", "每周依赖升级", 0.31, "Studio · Sonnet 5.5", { chat: { station: STATION, session: "ember:c-demo-deps" } }),
        item("p99", "排查 API p99 变慢", 0.24, "Studio · Opus 5.5", { chat: { station: STATION, session: "ember:c-demo-p99" } }),
        item("csv", "订单导出支持 CSV", 0.19, "Studio · GPT-5.5", { chat: { station: STATION, session: "ember:c-demo-csv" } }),
        item("safari", "把那个弄一下", 0.15, "Studio · Opus 5.5", { chat: { station: STATION, session: "ember:c-demo-safari" } }),
        item("docs", "补一下部署文档", 0.11, "Studio · Opus 5.5"),
      ] },
      { key: "people", title: "按人", items: people.map((p, k) => item(p.id, p.name, [0.5, 0.33, 0.17][k]!, undefined, { person: p })) },
      { key: "models", title: "按模型", items: [item("opus", "Opus 5.5", 0.5, "Anthropic"), item("sonnet", "Sonnet 5.5", 0.31, "Anthropic"), item("gpt", "GPT-5.5", 0.19, "OpenAI")] },
    ],
    notes: [], basis: "按各家 API 的公开价格折算，订阅实际不按此计费",
  };
}
const money = (dollars: number) => `$${dollars.toFixed(2)}`;

/** 奏 with nothing waiting (the core's `decisions`): the day in numbers, the viewer's chats at work, what was answered today. */
export function decisions(chats: { key: string; thread: number; title: string; running: { activity: string; since: number } | null; blocked: boolean }[]) {
  const where = { station: STATION, stationName: "Studio" };
  const working = chats.filter((c) => c.running || c.blocked).map((c) => ({
    ...where, session: c.key, thread: c.thread, title: c.title, line: c.running ? `在做 · ${c.running.activity}` : "等待：你决定要不要一起升 React Router 8",
    time: { lastActiveAt: stamp(c.running?.since ?? Date.now() - 58 * 60_000) },
  }));
  const at = (minutes: number) => new Date(Date.now() - minutes * 60_000).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
  return {
    items: [], count: 0, loading: false, wait: { reading: false, failing: [], empty: false }, working,
    answered: [
      { ...where, session: "ember:c-demo-csv", thread: 5, title: "订单导出支持 CSV", seq: 3, text: "导出的文件名要带上日期吗？", answer: "选择了「带日期」", clock: at(40) },
      { ...where, session: "ember:c-demo-p99", thread: 4, title: "排查 API p99 变慢", seq: 4, text: "索引迁移现在上线，还是等晚上？", answer: "回复：现在上", clock: at(150) },
    ],
    today: { count: 2, waited: "6 分钟", working: working.length },
  };
}

// ---- still.fail cloud ----

const user = (p: Person) => ({ sub: p.id, email: p.email ?? p.id, name: p.name, picture: p.shown.picture ?? "" });

/** The visitor, signed in as a member of Acme. */
export const ACCOUNT = { sub: "demo-you", email: "you@acme.dev", name: "你", picture: "" };
/** Its workspace: the first part of STATION (fixtures.ts). */
export const WORKSPACE = "demo";

export function workspaces() {
  const at = Date.now();
  return [{
    account: ACCOUNT, invitations: [], relay_url: null, loaded: true,
    workspaces: [{ id: WORKSPACE, name: "Acme", role: "admin", created_at: at - 90 * 86_400_000, stations: 1, members: 4 }],
  }];
}

export function workspace() {
  const at = Date.now();
  const member = (p: ReturnType<typeof user>, role: string, days: number) => ({ ...p, role, added_at: at - days * 86_400_000 });
  return {
    id: WORKSPACE, name: "Acme", role: "admin", created_at: at - 90 * 86_400_000,
    members: [member(user(LIN), "owner", 90), member(ACCOUNT, "admin", 60), member(user(CHEN), "member", 45), member(user(ZHOU), "member", 30)],
    stations: [{ id: "local", name: "Studio", enrolled_at: at - 88 * 86_400_000, enrolled_by: LIN.email, last_seen: null, version: "0.1.1024" }],
    invitations: [], added: [],
  };
}

export function loginSessions() {
  const at = Date.now();
  const session = (id: string, name: string, days: number, current: boolean) => {
    const created = at - days * 86_400_000;
    const expires = created + 30 * 86_400_000;
    return { id, name, created_at: created, expires_at: expires, current, time: { created_at: stamp(created), expires_at: stamp(expires) } };
  };
  return [session("s1", "这台浏览器", 3, true), session("s2", "still.fail（Android）", 12, false)];
}
