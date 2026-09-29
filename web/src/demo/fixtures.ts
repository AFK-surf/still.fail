// The official site's demo (site/index.html): a made-up team's ember, as the core would give it to the page. Each
// chat is kept as it stands (its messages, its execution history, whether its agent is at work); main.tsx turns them
// into the topics the app reads, and story.ts plays what happens in them.
import type {
  ChatAgent, ChatItem, ChatMessage, ChatView, ChatsView, ModelOption, Outgoing, Profile, HistoryGroup, HistoryItem, HistoryStep, HistoryView, Live,
  Maker, Person, RowAgent, RuntimeKind, Session, Stamp,
} from "../core/shapes.ts";

const MINUTE = 60_000;

/** A moment in words, as the core puts it (Stamp): how long ago, or how long until. */
export function stamp(at: number): Stamp {
  const words = (ms: number) => {
    const minutes = Math.round(ms / MINUTE);
    return minutes < 60 ? `${minutes} 分钟` : minutes < 48 * 60 ? `${Math.round(minutes / 60)} 小时` : `${Math.round(minutes / 1440)} 天`;
  };
  const past = at <= Date.now();
  const since = Date.now() - at;
  const ago = since < MINUTE ? "刚刚" : since < 48 * 60 * MINUTE ? `${words(since)}前` : since < 72 * 60 * MINUTE ? "昨天" : `${words(since)}前`;
  const until = at - Date.now() < MINUTE ? "1 分钟内" : `${words(at - Date.now())}后`;
  const date = new Date(at);
  const pad = (n: number) => String(n).padStart(2, "0");
  return { at, ago, full: `${date.getMonth() + 1}/${date.getDate()} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`, until, past };
}
export const ago = (minutes: number) => Date.now() - minutes * MINUTE;

const ANTHROPIC: Maker = { id: "anthropic", name: "Anthropic" };
const OPENAI: Maker = { id: "openai", name: "OpenAI" };

export interface Model {
  runtime: RuntimeKind;
  model: string;
  name: string;
  effort: string;
  maker: Maker;
}
const OPUS: Model = { runtime: "claude", model: "claude-opus-5-5", name: "Opus 5.5", effort: "medium", maker: ANTHROPIC };
const SONNET: Model = { runtime: "claude", model: "claude-sonnet-5-5", name: "Sonnet 5.5", effort: "medium", maker: ANTHROPIC };
const GPT: Model = { runtime: "codex", model: "gpt-5.5", name: "GPT-5.5", effort: "high", maker: OPENAI };

// Their pictures, drawn in the style of ember's buddy (its outline, its warm colours, its cheeks) by GPT-6 Astra.
const pictures = import.meta.glob<string>("./people/*.svg", { eager: true, query: "?url", import: "default" });

function person(id: string, name: string): Person {
  const picture = pictures[`./people/${id}.svg`];
  return { id: `${id}@acme.dev`, name, email: `${id}@acme.dev`, via: "cloud", shown: { name, display: name, mine: false, ...(picture ? { picture } : {}) } };
}
export const LIN = person("lin", "林晓");
export const CHEN = person("chen", "陈默");
export const ZHOU = person("zhou", "周宁");
/** The visitor, as the station names who wrote to it. */
export const VISITOR: Person = { id: "local", name: "你", via: "local", shown: { name: "你", display: "你", mine: true } };

/** A chat as it stands. */
export interface DemoChat {
  key: string;
  thread: number;
  title: string;
  model: Model;
  people: Person[];
  messages: ChatMessage[];
  /** What the visitor sent that the "station" has not taken yet: the chat shows it on its way, as the core does. */
  outbox: Outgoing[];
  items: HistoryItem[];
  /** Its agent at work: what it does now, and since when. */
  running: { activity: string; since: number } | null;
  blocked: boolean;
  /** Its last turn failed: its account refused by the provider (a visitor's message on the site, which no one serves). */
  failed: boolean;
  unread: boolean;
  originText?: string;
}

export type Who = Person | "agent" | "me" | "ember";

export function message(chat: DemoChat, by: Who, text: string, at = Date.now()): ChatMessage {
  const seq = (chat.messages.at(-1)?.seq ?? 0) + 1;
  const base = { seq, thread: chat.thread, ts: `${at / 1000}`, text, attachments: [], quotes: [], createdAt: at, system: false, waiting: false, time: { createdAt: stamp(at) } };
  const m = chat.model;
  if (by === "agent") return { ...base, authorKind: "agent", author: chat.key, mine: false, declared: "final", by: { name: m.name, agent: chat.key, maker: m.maker, runtime: m.runtime } };
  if (by === "ember") return { ...base, authorKind: "ember", author: "ember", mine: false, system: true, by: { name: "still.fail" } };
  if (by === "me") return { ...base, authorKind: "person", author: "local", authorName: "你", mine: true, by: { name: "你" } };
  return { ...base, authorKind: "person", author: by.id, authorName: by.name, mine: false, by: { name: by.name, ...(by.shown.picture ? { picture: by.shown.picture } : {}) } };
}

export function step(name: string, hint: string, call: object, result?: string, meta = "", failed = false): HistoryStep {
  return { name, hint, meta, failed, call: JSON.stringify(call, null, 2), ...(result === undefined ? {} : { result }) };
}

export function groupOf(steps: HistoryStep[], pending: number): HistoryItem["body"] {
  const content: HistoryGroup = { summary: steps.at(-1)!.hint, title: "", failures: steps.filter((s) => s.failed).length, pending, thinking: [], steps };
  return { kind: "group", content };
}

const placeOf = (chat: DemoChat) => ({ name: chat.title, surface: "ember", session: chat.key });

export function received(chat: DemoChat, from: Person, text: string): HistoryItem["body"] {
  return { kind: "received", content: { messages: [{ key: `m${chat.items.length}`, from: { name: from.name, bound: false }, text, place: placeOf(chat) }] } };
}
export function posted(chat: DemoChat, text: string): HistoryItem["body"] {
  return { kind: "post", content: { text, place: placeOf(chat), block: false, failed: false } };
}
export const said = (text: string): HistoryItem["body"] => ({ kind: "text", content: { subagent: false, text } });
export function outgoing(text: string): Outgoing {
  const at = Date.now();
  return { id: `out-${at}`, text, attachments: [], quotes: [], createdAt: at, state: "sending", time: { createdAt: stamp(at) } };
}
export const marked = (text: string): HistoryItem["body"] => ({ kind: "mark", content: { text } });

export function addItem(chat: DemoChat, body: HistoryItem["body"]): void {
  const n = chat.items.length;
  chat.items = [...chat.items, { key: `e${n}`, entries: [n, n], body }];
}

// ---- The chats, as they start ----

/** A chat the visitor starts (新建对话), on the model they picked. */
export function newChat(thread: number, model?: string): DemoChat {
  const picked = [OPUS, SONNET, GPT].find((m) => m.model === model) ?? OPUS;
  return chatOf(`new-${thread}`, thread, "新对话", picked, []);
}

function chatOf(key: string, thread: number, title: string, model: Model, people: Person[], extra: Partial<DemoChat> = {}): DemoChat {
  return { key: `ember:c-demo-${key}`, thread, title, model, people, messages: [], outbox: [], items: [], running: null, blocked: false, failed: false, unread: false, ...extra };
}

/** A chat's history so far: each (who, what, minutes ago); the agent's posts are recorded in its history too. */
function seed(chat: DemoChat, lines: [Who, string, number][]): DemoChat {
  for (const [by, text, minutes] of lines) {
    chat.messages = [...chat.messages, message(chat, by, text, ago(minutes))];
    if (by === "agent") {
      addItem(chat, posted(chat, text));
      addItem(chat, marked(chat.blocked && chat.messages.length === lines.length ? "等你决定" : "完成"));
    } else if (by !== "me" && by !== "ember") addItem(chat, received(chat, by, text));
  }
  return chat;
}

export const SAFARI_ASK = "那个谁，你把那个啥……那个一下，懂我意思？";
export const DEPS_KEY = "ember:c-demo-deps";
export const SAFARI_KEY = "ember:c-demo-safari";

export function startingChats(): DemoChat[] {
  return [
    chatOf("safari", 7, "把那个弄一下", OPUS, [LIN, CHEN]),
    seed(chatOf("deps", 6, "每周依赖升级", SONNET, [CHEN], { blocked: true, originText: "Slack · Acme · #frontend" }), [
      [CHEN, "这周的依赖升级跑一下", 70],
      ["agent", "其余 23 个包都升好了，测试通过。只剩 React Router 8：它改了 loader 的写法，要动 14 个路由文件。这周要一起升吗？", 58],
    ]),
    seed(chatOf("csv", 5, "订单导出支持 CSV", GPT, [ZHOU], { unread: true }), [
      [ZHOU, "订单列表加一个导出 CSV，筛选条件要带上", 95],
      ["agent", "做好了：导出按当前筛选条件走流式写出，10 万行大约 2.3 秒，已合进 main（`a3f9c21`）。", 26],
    ]),
    seed(chatOf("p99", 4, "排查 API p99 变慢", OPUS, [LIN]), [
      [LIN, "昨天开始 /api/orders 的 p99 从 150ms 涨到快 2 秒了", 60 * 21],
      ["agent", "罪魁是 `orders` 表少了 `(user_id, created_at)` 联合索引：上周的分页改动让查询走了全表扫描。加上索引后 p99 回到 120ms，迁移脚本在 `db/migrations/0042_orders_index.sql`。", 60 * 20],
    ]),
    seed(chatOf("docs", 3, "补一下部署文档", SONNET, [CHEN]), [
      [CHEN, "把 station 的部署步骤写进 docs/deploy.md", 60 * 27],
      ["agent", "写好了，按 macOS 和 Linux 分开，附了 launchd / systemd 的排错办法。", 60 * 26],
      [CHEN, "谢谢，文档看过了", 60 * 26],
    ]),
  ];
}

// ---- What the app reads ----

function rowAgent(chat: DemoChat): RowAgent {
  const m = chat.model;
  const mark = chat.running ? "run" : chat.blocked ? "block" : chat.failed ? "failed" : undefined;
  return {
    key: chat.key, runtime: m.runtime, model: m.model, effort: m.effort, process: chat.running ? "running" : "warm", pending: 0,
    agentText: `${m.name} · ${m.effort}`, maker: m.maker, statusText: chat.running ? "进行中" : chat.blocked ? "等你决定" : chat.failed ? "出错了" : "已完成",
    ...(mark ? { mark, badgeText: mark === "run" ? "工作中" : mark === "block" ? "需要你" : "出错了" } : {}),
  };
}

function session(chat: DemoChat): Session {
  return {
    ...rowAgent(chat), connect: "ember", scope: "all", title: chat.title, modelName: chat.model.name,
    runtimeText: chat.model.runtime === "claude" ? "Claude Code" : "Codex", processText: chat.running ? "运行中" : "待命",
    running: !!chat.running, tone: chat.running ? "accent" : chat.blocked ? "amber" : chat.failed ? "red" : "green", titleText: chat.title,
    efforts: ["low", "medium", "high"], ...(chat.model.runtime === "claude" ? { profile: "machine-claude" } : {}), workspace: `~/.ember/sessions/${chat.key.slice(6)}/workspace`,
  };
}

function lastActive(chat: DemoChat): number {
  return Math.max(chat.messages.at(-1)?.createdAt ?? 0, chat.running?.since ?? 0) || Date.now();
}

function chatItem(chat: DemoChat): ChatItem {
  const last = chat.messages.at(-1);
  const at = lastActive(chat);
  const agent = rowAgent(chat);
  const preview = chat.running ? `${chat.running.activity}…` : last?.text.replace(/`/g, "") ?? "";
  const byAgent = chat.running || last?.authorKind === "agent" || last?.authorKind === "ember";
  return {
    id: chat.key, session: chat.key, thread: chat.thread, title: chat.title, agents: [agent], unread: chat.unread, mine: true,
    lastActiveAt: at, station: "local", stationName: "", ...(agent.mark ? { state: agent.mark } : {}),
    ...(chat.originText ? { originText: chat.originText } : {}),
    last: {
      seq: last?.seq ?? 0, authorKind: byAgent ? "agent" : "person", author: byAgent ? chat.key : last?.author ?? "", text: preview, preview,
      createdAt: at,
      by: byAgent
        ? { kind: "agent", name: chat.model.name, mine: false, model: chat.model.model, runtime: chat.model.runtime, label: chat.model.name, maker: chat.model.maker, ...(agent.mark ? { state: agent.mark } : {}) }
        : { kind: "person", name: last?.authorName ?? "", mine: !!last?.mine, label: last?.authorName ?? "", ...(last?.by.picture ? { picture: last.by.picture } : {}) },
      time: { createdAt: stamp(at) },
    },
    time: { lastActiveAt: stamp(at) },
  };
}

export function chatsView(chats: DemoChat[]): ChatsView {
  const items = chats.map(chatItem).sort((a, b) => b.lastActiveAt - a.lastActiveAt);
  const startOfDay = new Date().setHours(0, 0, 0, 0);
  const today = items.filter((item) => item.lastActiveAt >= Math.min(startOfDay, ago(12 * 60)));
  const earlier = items.filter((item) => !today.includes(item));
  return {
    me: { id: "local" }, stations: [{ id: "local", station: "local", name: "", state: "online" }], loading: false,
    days: [{ daysAgo: 0, at: Date.now(), label: "今天", items: today }, ...(earlier.length ? [{ daysAgo: 1, at: ago(24 * 60), label: "昨天", items: earlier }] : [])],
  };
}

/** What an agent's model control offers, and the account it runs on: the station's (station.ts). */
export interface Runs { choices: ModelOption[]; profile: Profile }

export function chatView(chat: DemoChat, runs?: Runs): ChatView {
  const created = chat.messages[0]?.createdAt ?? Date.now();
  const last = chat.messages.at(-1)?.seq ?? 0;
  const agent: ChatAgent = {
    session: session(chat), status: chat.running ? "running" : chat.blocked ? "block" : chat.failed ? "failed" : "final",
    ...(chat.running ? { badge: "run" as const, since: chat.running.since } : chat.blocked ? { badge: "block" as const } : chat.failed ? { badge: "failed" as const } : {}),
    ...(runs && chat.model.runtime === "claude" ? {
      profile: runs.profile, choices: runs.choices,
      account: { id: runs.profile.id, name: runs.profile.name, current: true, kind: runs.profile.access.kind, runtime: "claude" as const, ...(runs.profile.quota ? { quota: runs.profile.quota } : {}) },
      profiles: [{ id: runs.profile.id, name: runs.profile.name, current: true, kind: runs.profile.access.kind, runtime: "claude" as const }],
    } : { profiles: [], choices: [] }),
    attention: chat.failed ? [{ kind: "account", text: "账号被停用" }] : [], turns: [], threads: [], jobs: [],
  };
  // A chat the visitor started is theirs.
  const creator = chat.people[0] ?? { id: "local", name: "你", via: "local", shown: { name: "你", display: "你", mine: true } };
  return {
    me: { id: "local" }, title: chat.title, people: chat.people, agents: [agent], messages: chat.messages,
    more: false, outbox: chat.outbox, link: { state: "online" }, offline: false,
    thread: {
      id: chat.thread, surface: "ember", channel: "EMBER", threadTs: `${created / 1000}`, createdAt: created, createdBy: creator.id,
      creator: { id: creator.id, name: creator.name, via: "cloud", shown: creator.shown },
      sessions: [{ connect: "ember", session: chat.key, thread: chat.thread, joinedAt: created }],
      last, read: last, unread: 0, people: chat.people.map(({ shown: _, ...p }) => p), time: { createdAt: stamp(created) },
    },
  };
}

export function liveView(chat: DemoChat): Live {
  return { loaded: true, timeline: [], steps: [], ...(chat.running ? { activity: { now: { key: chat.running.activity, text: chat.running.activity } } } : {}) };
}

export function historyView(chat: DemoChat): HistoryView {
  return {
    items: chat.items, live: [], edge: "已到 Session 开始处", empty: chat.items.length === 0, loaded: true,
    ...(chat.running ? { phase: { phase: "working", text: "执行工具中", since: chat.running.since } } : {}),
  };
}
