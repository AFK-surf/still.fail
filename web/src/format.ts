// Turning ember's records into words people read.
import type { AccessKind, BotState, ProcessState, ProfileCheck, RuntimeKind, SessionSummary, TurnSummary } from "./api.ts";
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

export function presence(state: BotState): Presence {
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

export function connectionText(state: BotState): string {
  switch (state.state) {
    case "connected": return "在线";
    case "reconnecting": return "重连中";
    case "starting": return "连接中";
    case "error": return "连接失败";
    case "no_tokens": return "未连接 Slack";
    case "disabled": return "已停用";
  }
}

export interface SlackMessage {
  user: string;
  ts: string;
  text: string;
}

/** Splits a prompt ember built into the Slack messages it carried and ember's own words around them. */
export function parsePrompt(text: string): { messages: SlackMessage[]; note: string } {
  const messages: SlackMessage[] = [];
  const note = text.replace(/<slack user="([^"]*)"(?: bot)? ts="([^"]*)">\n?([\s\S]*?)\n?<\/slack>/g, (_, user: string, ts: string, body: string) => {
    messages.push({ user, ts, text: body });
    return "";
  }).trim();
  return { messages, note };
}
