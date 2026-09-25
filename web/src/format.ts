// Turning ember's records into words people read.
import type { AccessKind, ConnectMode, ConnectState, ConnectView, SessionDetail, ProcessState, ProfileCheck, RuntimeKind, SessionSummary, TurnSummary } from "./api.ts";
import type { Presence, Tone } from "./ui.tsx";

export type Status = "running" | "queued" | "final" | "block" | "failed" | "aborted" | "unexpected" | "idle";

export const STATUS_LABEL: Record<Status, string> = {
  running: "进行中",
  queued: "排队中",
  final: "已完成",
  block: "等你回复",
  failed: "失败",
  aborted: "已停止",
  unexpected: "意外停止",
  idle: "未开始",
};

export const PROCESS_LABEL: Record<ProcessState, string> = { running: "运行中", warm: "保温中", cold: "已释放" };

export const MODE: Record<ConnectMode, { label: string; description: string }> = {
  "multi-session": { label: "每个 thread 一个会话", description: "在 thread 里 @ 它就开一个新会话，thread 里的后续消息都进这个会话。" },
  "single-session": { label: "所有 thread 共用一个会话", description: "它看到的所有 thread 进同一个会话，适合一个长期值守的助手。" },
};

export function modeText(mode: ConnectMode, requireMention: boolean): string {
  return mode === "multi-session" ? "多会话" : requireMention ? "单会话 · @ 唤醒" : "单会话 · 全部消息";
}

export const RUNTIME_LABEL: Record<RuntimeKind, string> = { claude: "Claude Code", codex: "Codex" };

export const ACCESS: Record<AccessKind, { label: string; description: string }> = {
  "subscription": { label: "订阅账号", description: "在服务器上登录 Claude 或 ChatGPT 订阅，用订阅额度运行。" },
  "opencode-go": { label: "OpenCode Go", description: "用 OpenCode Go 套餐的 key，模型由 OpenCode Go 提供。" },
  "anthropic-api": { label: "Anthropic API", description: "用 Anthropic API key，按量计费。" },
  "env": { label: "自定义环境变量", description: "手动填写运行时需要的环境变量。" },
};

export const ACCESS_KINDS: Record<RuntimeKind, AccessKind[]> = {
  claude: ["subscription", "opencode-go", "anthropic-api", "env"],
  codex: ["subscription", "opencode-go", "env"],
};

export const KEYED = new Set<AccessKind>(["opencode-go", "anthropic-api"]);

export function checkTone(check: ProfileCheck | null): { tone: Tone; label: string } {
  if (!check) return { tone: "neutral", label: "未检查" };
  return { ok: { tone: "green", label: "可用" }, login: { tone: "amber", label: "需要登录" }, failed: { tone: "red", label: "不可用" }, unknown: { tone: "neutral", label: "无法检查" } }[check.state] as { tone: Tone; label: string };
}

export function presence(state: ConnectState): Presence {
  switch (state.state) {
    case "connected": return "online";
    case "reconnecting": case "starting": return "busy";
    case "error": return "error";
    default: return "offline";
  }
}

export function compactNumber(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(1).replace(/\.0$/, "")}K`;
  return String(n);
}

/** Groups by calendar day, like Zork's chat list: 今天, 昨天, 星期三, 9月20日. */
export function dayLabel(ms: number, now = Date.now()): string {
  const day = (t: number) => Math.floor((t - new Date(t).getTimezoneOffset() * 60_000) / 86_400_000);
  const diff = day(now) - day(ms);
  if (diff === 0) return "今天";
  if (diff === 1) return "昨天";
  const date = new Date(ms);
  if (diff < 7) return ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][date.getDay()]!;
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

export function turnResult(turn: TurnSummary | null): Status {
  if (!turn) return "idle";
  if (turn.declared === "final") return "final";
  if (turn.declared === "block") return "block";
  if (turn.outcome === "failed") return "failed";
  if (turn.outcome === "aborted") return "aborted";
  if (turn.outcome === null) return turn.endedAt === null ? "running" : "unexpected";
  return "unexpected"; // completed without saying final or block
}

export function sessionStatus(s: SessionSummary): Status {
  if (s.process === "running") return "running";
  if (s.pending > 0) return "queued";
  const result = turnResult(s.lastTurn);
  return result === "running" ? "unexpected" : result; // a turn left open by a crash
}

/** Slack mentions and spacing removed, for use as a title. */
export function cleanText(text: string | null): string {
  return (text ?? "").replace(/<@[A-Z0-9]+>/g, "").replace(/\s+/g, " ").trim();
}

export function relativeTime(ms: number, now = Date.now()): string {
  const seconds = Math.round((now - ms) / 1000);
  if (seconds < 45) return "刚刚";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} 小时前`;
  const date = new Date(ms);
  const time = date.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
  if (hours < 48) return `昨天 ${time}`;
  return `${date.getMonth() + 1}月${date.getDate()}日 ${time}`;
}

export function absoluteTime(ms: number): string {
  return new Date(ms).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function duration(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)}ms`;
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s} 秒`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} 分 ${s % 60} 秒` : `${Math.floor(m / 60)} 小时 ${m % 60} 分`;
}

export function connectionText(state: ConnectState): string {
  switch (state.state) {
    case "connected": return "在线";
    case "reconnecting": return "重连中";
    case "starting": return "连接中";
    case "error": return "连接失败";
    case "no_tokens": return "未连接 Slack";
    case "disabled": return "已停用";
  }
}

export interface SourcedMessage {
  user: string;
  ts: string;
  text: string;
  /** CHANNEL/THREAD_TS, when the prompt said. */
  thread: string | null;
}

const unescape = (v: string) => v.replaceAll("&quot;", "\"").replaceAll("&amp;", "&");

/**
 * Splits a prompt ember built into the chat messages it carried and ember's own
 * words around them. Reads the current <message …> form and the older <slack …> one.
 */
export function parsePrompt(text: string): { messages: SourcedMessage[]; note: string } {
  const messages: SourcedMessage[] = [];
  const note = text
    .replace(/<message ([^>]*)>\n?([\s\S]*?)\n?<\/message>/g, (_, attrs: string, body: string) => {
      const attr = (name: string) => new RegExp(`${name}="([^"]*)"`).exec(attrs)?.[1];
      const from = unescape(attr("from") ?? "");
      messages.push({ user: /\(([^()\s]+)\)$/.exec(from)?.[1] ?? from, ts: attr("ts") ?? "", text: body, thread: attr("thread") ?? null });
      return "";
    })
    .replace(/<slack user="([^"]*)"(?: bot)? ts="([^"]*)">\n?([\s\S]*?)\n?<\/slack>/g, (_, user: string, ts: string, body: string) => {
      messages.push({ user, ts, text: body, thread: null });
      return "";
    })
    .replace(/^\(Thread \S+ had messages before you were brought in;.*\)$/gm, "")
    .trim();
  return { messages, note };
}

/** "C0OPS/1727.0001" → its channel and thread. */
export function splitThread(address: string): { channel: string; threadTs: string } | null {
  const m = /^([A-Z0-9]+)\/(\d+\.\d+)$/.exec(address);
  return m ? { channel: m[1]!, threadTs: m[2]! } : null;
}

/** Slack deep link to a thread, when the workspace URL is known. */
export function slackThreadUrl(workspaceUrl: string | null | undefined, channel: string, threadTs: string): string | null {
  return workspaceUrl ? `${workspaceUrl}archives/${channel}/p${threadTs.replace(".", "")}` : null;
}

/** A readable id from a name: "Ember DS" → "ember-ds". */
export function slug(name: string): string {
  return name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32);
}

export function statusTone(status: Status): Tone {
  if (status === "running" || status === "queued") return "accent";
  if (status === "final") return "green";
  if (status === "block") return "blue";
  if (status === "failed" || status === "unexpected") return "red";
  return "neutral";
}

export function botUserIdOf(connect: ConnectView | undefined): string | null {
  const c = connect?.connection;
  return c && (c.state === "connected" || c.state === "reconnecting") ? c.botUserId : null;
}

/** Names a thread for people: its channel (by name when known) and when it began. */
export function threadNamer(detail: SessionDetail) {
  return (channel: string, threadTs: string) => {
    const started = new Date(Number(threadTs) * 1000);
    const when = `${started.getMonth() + 1}月${started.getDate()}日 ${started.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })}`;
    if (channel === "EMBER") {
      const chat = detail.chats.find((c) => c.threadTs === threadTs);
      return { where: chat?.title ? `对话「${chat.title}」` : "管理页对话", when };
    }
    const where = channel.startsWith("D") ? "私信" : `#${detail.channels[channel] ?? channel}`;
    return { where, when };
  };
}


export function modeShort(mode: ConnectMode): string {
  return mode === "multi-session" ? "多会话" : "单会话";
}

/** What a session is called in lists: its given title, else its first message. */
export function sessionTitle(s: { title: string | null; firstText: string | null; scope: string }, connectName: string): string {
  return s.title || cleanText(s.firstText) || (s.scope === "all" ? `${connectName} 的会话` : "（没有消息）");
}
