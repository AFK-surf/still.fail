// Turning ember's records into words people read.
import type { BotState, ProcessState, RuntimeKind, SessionSummary, TurnSummary } from "./api.ts";

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
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s} 秒`;
  const m = Math.floor(s / 60);
  return m < 60 ? `${m} 分 ${s % 60} 秒` : `${Math.floor(m / 60)} 小时 ${m % 60} 分`;
}

export function connectionText(state: BotState): string {
  switch (state.state) {
    case "connected": return "已连接";
    case "reconnecting": return "重连中";
    case "starting": return "连接中";
    case "error": return `连接失败：${state.error}`;
    case "no_tokens": return "还没填 Slack token";
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
