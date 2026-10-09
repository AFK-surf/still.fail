// Words and marks the clients show, decided here once (format.rs): numbers, times and durations in words, day
// headings, a thread's name, an agent's label, a model's maker, a runtime's efforts, a connect's state. Times are the
// viewer's local ones: `offsetMin` is their UTC offset at that moment (Host).
import * as brand from "./brand.ts";
import { current, tr, type Lang } from "./i18n.ts";
import * as model from "./shapes/model.ts";
import * as reasoning from "./shapes/reasoning.ts";
import { get, str } from "./util.ts";

const MINUTE = 60_000;
const DAY = 86_400_000;

/// The words for `key` in the current language (Rust keeps each once a language; here it is just said).
export function said(key: string): string {
  return tr(current(), key);
}

/// Rust's `{:.1}`: one decimal, rounded half to even on the binary value as Rust's formatting does.
export function fixed1(v: number): string {
  return v.toFixed(1);
}

/// Rust's `as i64` of a rounded f64: `f64::round` rounds half away from zero.
export function round(v: number): number {
  return v < 0 ? -Math.round(-v) : Math.round(v);
}

function monthDay(lang: Lang, month: number, day: number): string {
  return tr(lang, `core-logic.format.date.${month}`, { day });
}

/// 950, 1.2K, 3.4M.
export function compactNumber(n: number): string {
  const cut = (v: number, unit: string) => {
    const s = fixed1(v);
    return `${s.endsWith(".0") ? s.slice(0, -2) : s}${unit}`;
  };
  if (n >= 1_000_000) return cut(n / 1_000_000, "M");
  if (n >= 1000) return cut(n / 1000, "K");
  return String(round(n));
}

/// 850ms, 12 秒, 3 分 5 秒, 2 小时 4 分.
export function duration(ms: number): string {
  return durationIn(current(), ms);
}

export function durationIn(lang: Lang, ms: number): string {
  if (ms < 1000) return `${round(ms)}ms`;
  const s = round(ms / 1000);
  if (s < 60) return tr(lang, "core-logic.format.duration.s", { s });
  const m = Math.trunc(s / 60);
  if (m < 60) return tr(lang, "core-logic.format.duration.ms", { m, s: s % 60 });
  return tr(lang, "core-logic.format.duration.hm", { h: Math.trunc(m / 60), m: m % 60 });
}

function remEuclid(a: number, b: number): number {
  return ((a % b) + b) % b;
}

/// A local time's parts: [year, month 1–12, day, weekday 0 = Sunday, hour, minute].
export function local(ms: number, offsetMin: number): [number, number, number, number, number, number] {
  const at = ms + offsetMin * MINUTE;
  const days = Math.floor(at / DAY);
  const inDay = Math.trunc(Math.trunc(at - days * DAY) / 60_000);
  const z = days + 719_468;
  const era = Math.floor(z / 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.trunc((doe - Math.trunc(doe / 1460) + Math.trunc(doe / 36_524) - Math.trunc(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.trunc(yoe / 4) - Math.trunc(yoe / 100));
  const mp = Math.trunc((5 * doy + 2) / 153);
  const d = doy - Math.trunc((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  const y = yoe + era * 400 + (m <= 2 ? 1 : 0);
  const weekday = remEuclid(days + 4, 7);
  return [y, m, d, weekday, Math.trunc(inDay / 60), inDay % 60];
}

export function localDay(ms: number, offsetMin: number): number {
  return Math.floor((ms + offsetMin * MINUTE) / DAY);
}

const two = (n: number) => String(n).padStart(2, "0");

/// 14:05, local.
export function clock(ms: number, offsetMin: number): string {
  const [, , , , h, m] = local(ms, offsetMin);
  return `${two(h)}:${two(m)}`;
}

/// 14:05 today, 9/27 14:05 before.
export function dayClock(ms: number, now: number, offsetMin: number): string {
  const [, month, day] = local(ms, offsetMin);
  const time = clock(ms, offsetMin);
  return localDay(ms, offsetMin) === localDay(now, offsetMin) ? time : `${month}/${day} ${time}`;
}

/// 刚刚, 3 分钟前, 5 小时前, 昨天 14:05, 9月20日 14:05.
export function relativeTime(ms: number, now: number, offsetMin: number): string {
  return relativeTimeIn(current(), ms, now, offsetMin);
}

export function relativeTimeIn(lang: Lang, ms: number, now: number, offsetMin: number): string {
  const seconds = round((now - ms) / 1000);
  if (seconds < 45) return tr(lang, "core-logic.format.ago.now");
  const minutes = round(seconds / 60);
  if (minutes < 60) return tr(lang, "core-logic.format.ago.minutes", { n: minutes });
  const hours = round(minutes / 60);
  if (hours < 24) return tr(lang, "core-logic.format.ago.hours", { n: hours });
  const [, month, day] = local(ms, offsetMin);
  const time = clock(ms, offsetMin);
  if (hours < 48) return tr(lang, "core-logic.format.ago.yesterday", { time });
  return tr(lang, "core-logic.format.date_time", { date: monthDay(lang, month, day), time });
}

/// 9/20 14:05:09, local: a time in full, for a tip.
export function absoluteTime(ms: number, offsetMin: number): string {
  const [, month, day, , h, m] = local(ms, offsetMin);
  const s = remEuclid(Math.floor(ms / 1000), 60);
  return `${month}/${day} ${two(h)}:${two(m)}:${two(s)}`;
}

/// 1 分钟内, 40 分钟后, 3 小时后, 2 天后.
export function timeUntil(ms: number, now: number): string {
  return timeUntilIn(current(), ms, now);
}

export function timeUntilIn(lang: Lang, ms: number, now: number): string {
  const minutes = Math.max(round((ms - now) / MINUTE), 0);
  if (minutes < 60) return minutes <= 1 ? tr(lang, "core-logic.format.until.minute") : tr(lang, "core-logic.format.until.minutes", { n: minutes });
  const hours = round(minutes / 60);
  if (hours < 48) return tr(lang, "core-logic.format.until.hours", { n: hours });
  return tr(lang, "core-logic.format.until.days", { n: round(hours / 24) });
}

/// When a quota window refills, in words.
export function refillsIn(ms: number, now: number): string {
  return refillsInLang(current(), ms, now);
}

export function refillsInLang(lang: Lang, ms: number, now: number): string {
  const minutes = round((ms - now) / MINUTE);
  if (minutes <= 0) return tr(lang, "core-logic.format.refill.now");
  if (minutes < 60) return tr(lang, "core-logic.format.refill.minutes", { n: minutes });
  const hours = Math.trunc(minutes / 60);
  if (hours < 24) {
    const m = minutes % 60;
    return m === 0 ? tr(lang, "core-logic.format.refill.hours", { n: hours }) : tr(lang, "core-logic.format.refill.hours_minutes", { h: hours, m });
  }
  const h = hours % 24;
  return h === 0 ? tr(lang, "core-logic.format.refill.days", { n: Math.trunc(hours / 24) }) : tr(lang, "core-logic.format.refill.days_hours", { n: Math.trunc(hours / 24), h });
}

/// A quota window's label in the viewer's language: the station names them in Chinese (5 小时, 每周 · Opus, 每月, 3 天);
/// one it does not name so is shown as it is.
export function windowName(label: string, lang: Lang = current()): string {
  const m = /^([0-9]+) (小时|天)(.*)$/.exec(label);
  if (m) return tr(lang, m[2] === "小时" ? "core-logic.format.window.hours" : "core-logic.format.window.days", { n: Number(m[1]) }) + m[3];
  if (label.startsWith("每周")) return tr(lang, "core-logic.format.window.weekly") + label.slice(2);
  if (label.startsWith("每月")) return tr(lang, "core-logic.format.window.monthly") + label.slice(2);
  return label;
}

/// A quota window marked by its length (5H, W, M, 3D), and where it goes among the others.
export function windowMark(label: string): [string, number] {
  if (label.startsWith("每月") || label.startsWith("Monthly")) return ["M", 3];
  if (label.startsWith("每周") || label.startsWith("Weekly")) return ["W", 2];
  const lead = (unit: string) => {
    const at = label.indexOf(unit);
    if (at < 0) return null;
    const n = label.slice(0, at);
    return n !== "" && /^[0-9]+$/.test(n) ? n : null;
  };
  const h = lead(" 小时") ?? lead(" hour");
  if (h !== null) return [`${h}H`, 0];
  const d = lead(" 天") ?? lead(" day");
  return d !== null ? [`${d}D`, 1] : [label, 1];
}

/// Bytes in gigabytes, one decimal below 100.
export function gb1(bytes: number): string {
  const g = bytes / 1024 ** 3;
  return bytes >= 100 * 1024 ** 3 ? `${round(g)} GB` : `${fixed1(g)} GB`;
}

/// Bytes in the unit that suits them, one decimal below 10.
export function bytes(value: number): string {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let n = Math.max(value, 0);
  let unit = 0;
  while (n >= 1000 && unit < units.length - 1) {
    n /= 1024;
    unit++;
  }
  return unit === 0 || n >= 10 ? `${round(n)} ${units[unit]}` : `${fixed1(n)} ${units[unit]}`;
}

/// Bytes as whole gigabytes.
export function gb(value: number): string {
  return `${round(value / 1024 ** 3)} GB`;
}

/// A day's heading: 今天, 昨天, 星期三 (this week), 9月20日.
export function dayLabel(ms: number, now: number, offsetMin: number): string {
  return dayLabelIn(current(), ms, now, offsetMin);
}

export function dayLabelIn(lang: Lang, ms: number, now: number, offsetMin: number): string {
  const diff = localDay(now, offsetMin) - localDay(ms, offsetMin);
  if (diff === 0) return tr(lang, "core-logic.format.day.today");
  if (diff === 1) return tr(lang, "core-logic.format.day.yesterday");
  const [, month, day, weekday] = local(ms, offsetMin);
  if (diff < 7) return tr(lang, `core-logic.format.weekday.${weekday}`);
  return monthDay(lang, month, day);
}

/// Slack mentions and spacing out, for a title.
export function cleanText(text: string): string {
  let out = "";
  let rest = text;
  for (;;) {
    const at = rest.indexOf("<@");
    if (at < 0) break;
    out += rest.slice(0, at);
    const tail = rest.slice(at + 2);
    const m = /^[A-Z0-9]*/.exec(tail)![0].length;
    if (m > 0 && tail.slice(m).startsWith(">")) rest = tail.slice(m + 1);
    else {
      out += "<@";
      rest = tail;
    }
  }
  out += rest;
  return splitWhitespace(out).join(" ");
}

/// Rust's `split_whitespace`: Unicode white space.
export function splitWhitespace(text: string): string[] {
  return text.split(/[\s\u0085]+/u).filter((w) => w !== "");
}

/// A thread named for people: where (its channel by name, 私信, or a still.fail chat's title) and when it began.
export function threadName(threads: unknown[], channel: string, threadTs: string, offsetMin: number): [string, string] {
  const parsed = Number(threadTs);
  const started = (Number.isFinite(parsed) && threadTs.trim() !== "" ? parsed : 0) * 1000;
  const [, month, day] = local(started, offsetMin);
  const when = tr(current(), "core-logic.format.date_time", { date: monthDay(current(), month, day), time: clock(started, offsetMin) });
  const thread = threads.find((t) => str(get(t, "channel")) === channel && str(get(t, "threadTs")) === threadTs);
  const text = (k: string) => str(get(thread, k)) ?? "";
  let where: string;
  if (channel === "EMBER" || channel === "STILLFAIL") {
    const title = text("title");
    if (title !== "") where = title;
    else {
      const first = cleanText(text("firstText"));
      where = first === "" ? tr(current(), "core-logic.format.thread.chat", { brand: brand.name() }) : first;
    }
  } else if (channel.startsWith("D")) where = tr(current(), "core-logic.format.thread.dm");
  else {
    const n = text("channelName");
    where = `#${n === "" ? channel : n}`;
  }
  return [where, when];
}

/// "C0OPS/1727.0001" → its channel and thread.
export function splitThread(address: string): [string, string] | null {
  const slash = address.indexOf("/");
  if (slash < 0) return null;
  const channel = address.slice(0, slash);
  const ts = address.slice(slash + 1);
  const dot = ts.indexOf(".");
  const valid = /^[A-Z0-9]+$/.test(channel) && dot > 0 && dot < ts.length - 1 && /^[0-9]+$/.test(ts.slice(0, dot)) && /^[0-9]+$/.test(ts.slice(dot + 1));
  return valid ? [channel, ts] : null;
}

/// A Slack workspace as the station's connects know it.
export type SlackWorkspace = { name: string; url: string | null };

/// A thread a history entry came from or went to: its name, where it is, and the way there.
export function place(threads: unknown[], address: string, offsetMin: number, workspaces: Map<string, SlackWorkspace>): unknown {
  const split = splitThread(address);
  if (!split) return null;
  const [channel, ts] = split;
  const [n] = threadName(threads, channel, ts, offsetMin);
  const thread = threads.find((t) => str(get(t, "channel")) === channel && str(get(t, "threadTs")) === ts);
  const first = (get(thread, "sessions") as unknown[] | undefined)?.[0];
  const session = str(get(first, "session")) ?? null;
  if (channel === "EMBER" || channel === "STILLFAIL") return { name: n, surface: "ember", session };
  const surface = str(get(thread, "surface"));
  const team = surface?.startsWith("slack:") ? workspaces.get(surface.slice(6)) : undefined;
  const teamName = team && team.name !== "" ? team.name : null;
  const named = teamName === null ? n : n.startsWith("#") ? `${teamName}${n}` : `${teamName} ${n}`;
  const url = team?.url ? `${team.url.replace(/\/+$/, "")}/archives/${channel}/p${ts.replaceAll(".", "")}` : null;
  return { name: named, surface: "slack", session, url };
}

/// Who made a model, by its name: [id, name] for its mark; null when the marks do not know it.
export function makerOf(modelName: string): [string, string] | null {
  const m = modelName.toLowerCase();
  const has = (words: string[]) => words.some((w) => m.includes(w));
  const o = m.startsWith("o") && /^[0-9]/.test(m.slice(1));
  if (has(["claude", "opus", "sonnet", "haiku", "fable"])) return ["anthropic", "Anthropic"];
  if (has(["gpt", "codex", "openai"]) || o) return ["openai", "OpenAI"];
  if (has(["deepseek"])) return ["deepseek", "DeepSeek"];
  if (has(["qwen", "qwq"])) return ["qwen", "Qwen"];
  if (has(["glm", "zhipu"])) return ["zhipu", said("core-logic.format.maker.zhipu")];
  if (has(["gemini", "gemma"])) return ["gemini", "Google"];
  if (has(["kimi", "moonshot"])) return ["kimi", "Kimi"];
  if (has(["minimax", "abab"])) return ["minimax", "MiniMax"];
  if (has(["grok"])) return ["xai", "xAI"];
  return null;
}

/// How an agent is named: its model as people call it and its effort (GPT-6 Astra · medium).
export function agentLabel(modelId: string | null | undefined, effort: string | null | undefined): string {
  const m = modelId ? model.name(modelId) : tr(current(), "core-logic.format.default_model");
  return effort ? `${m} · ${effort}` : m;
}

/// How hard a runtime's models can think, lowest first.
export function efforts(runtime: string): string[] {
  return reasoning.fallback(runtime);
}

export function runtimeLabel(runtime: string): string {
  return runtime === "codex" ? "Codex" : "Claude Code";
}

/// A connect's link to Slack in words, and its dot.
export function connection(state: unknown): [string, string] {
  switch (str(get(state, "state")) ?? "") {
    case "connected":
      return [said("core-logic.format.connection.connected"), "online"];
    case "reconnecting":
      return [said("core-logic.format.connection.reconnecting"), "busy"];
    case "starting":
      return [said("core-logic.format.connection.starting"), "busy"];
    case "error":
      return [said("core-logic.format.connection.error"), "error"];
    case "disabled":
      return [said("core-logic.format.connection.disabled"), "offline"];
    default:
      return [said("core-logic.format.connection.no_slack"), "offline"];
  }
}

/// How a connect's conversations become sessions, in words: its line, and its short form.
export function modeText(mode: string, requireMention: boolean): [string, string] {
  if (mode === "multi-session") return [said("core-logic.format.mode.multi"), said("core-logic.format.mode.multi")];
  return requireMention
    ? [said("core-logic.format.mode.single_mention"), said("core-logic.format.mode.single")]
    : [said("core-logic.format.mode.single_all"), said("core-logic.format.mode.single")];
}

/// Why a turn failed, in words, from its `detail`.
export function failureText(detail: string): string {
  switch (detail.split(":")[0].trim()) {
    case "rate_limit":
      return said("core-logic.format.failure.rate_limit");
    case "auth":
      return said("core-logic.format.failure.auth");
    case "refused":
      return said("core-logic.format.failure.refused");
    case "model":
      return said("core-logic.format.failure.model");
    case "exited":
      return said("core-logic.format.failure.exited");
    default:
      return said("core-logic.format.failure.other");
  }
}

/// A status in words, and its tone.
export function statusText(status: string): [string, string] {
  switch (status) {
    case "running":
      return [said("core-logic.format.status.running"), "accent"];
    case "queued":
      return [said("core-logic.format.status.queued"), "accent"];
    case "final":
      return [said("core-logic.format.status.final"), "green"];
    case "block":
      return [said("core-logic.format.status.block"), "blue"];
    case "decision":
      return [said("core-logic.format.status.decision"), "blue"];
    case "failed":
      return [said("core-logic.format.status.failed"), "red"];
    case "unexpected":
      return [said("core-logic.format.status.unexpected"), "red"];
    case "aborted":
      return [said("core-logic.format.status.aborted"), "neutral"];
    default:
      return [said("core-logic.format.status.idle"), "neutral"];
  }
}

/// A profile's last check in words, and its tone.
export function checkText(check: unknown): [string, string] {
  const state = str(get(check, "state"));
  if (state === undefined) return [said("core-logic.format.check.none"), "neutral"];
  if (state === "ok") return [said("core-logic.format.check.ok"), "green"];
  if (state === "login") return [said("core-logic.format.check.login"), "amber"];
  if (state === "failed") return [said("core-logic.format.check.failed"), "red"];
  return [said("core-logic.format.check.unknown"), "neutral"];
}

/// A process's state in words.
export function processText(process: string): string {
  if (process === "running") return said("core-logic.format.process.running");
  if (process === "warm") return said("core-logic.format.process.warm");
  return said("core-logic.format.process.released");
}
