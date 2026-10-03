// What the clients show of a value, decided once (present.rs): times in words beside the times, and each topic's
// value through its shape (client/shapes) as it goes out.
import { conform, type Ty } from "./conform.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import type { Topic } from "./protocol.ts";
import { arr, get, isObject, str, u64 } from "./util.ts";

/// The time a value is put together for: now, and the viewer's offset from UTC.
export type Clock = { now: number; offsetMin: number };

/// A moment in words (Stamp).
export function stamp(ms: number, c: Clock): Record<string, unknown> {
  return {
    past: ms <= c.now,
    at: ms,
    ago: format.relativeTime(ms, c.now, c.offsetMin),
    full: format.absoluteTime(ms, c.offsetMin),
    until: format.timeUntil(ms, c.now),
  };
}

/// Times kept in seconds (still.fail cloud's) and in milliseconds (the station's).
const SECONDS = ["created_at", "expires_at", "used_at", "revoked_at", "last_seen", "lastSeen"];
const MILLIS = ["createdAt", "lastActiveAt", "checkedAt", "resetsAt"];

/// What a window with `used` percent of it used has left, and how full it is.
export function leftLevel(used: number): [number, string] {
  return [format.round(Math.max(100 - used, 0)), used >= 90 ? "red" : used >= 70 ? "amber" : "ok"];
}

function windows(list: Record<string, unknown>[], c: Clock): void {
  for (const w of list) {
    const label = str(w.label) ?? "";
    const used = typeof w.usedPercent === "number" ? w.usedPercent : 0;
    const [mark, order] = format.windowMark(label);
    w.mark = mark;
    w.order = order;
    const [left, level] = leftLevel(used);
    w.left = left;
    w.level = level;
    w.refills = typeof w.resetsAt === "number" ? format.refillsIn(w.resetsAt, c.now) : null;
  }
  // A stable sort, as Rust's sort_by_key.
  list.sort((a, b) => (u64(a.order) ?? 1) - (u64(b.order) ?? 1));
}

/// Every time in a value, in words beside it: an object with some gets `time: { <field>: stamp }`; a quota's windows
/// are put as they are drawn.
export function times(value: unknown, c: Clock): void {
  if (Array.isArray(value)) {
    for (const v of value) times(v, c);
    return;
  }
  if (!isObject(value)) return;
  const map = value as Record<string, unknown>;
  const stamps: Record<string, unknown> = {};
  let any = false;
  for (const key of Object.keys(map)) {
    const v = map[key];
    if (typeof v === "number" && v > 0) {
      if (SECONDS.includes(key)) {
        stamps[key] = stamp(v * 1000, c);
        any = true;
      } else if (MILLIS.includes(key)) {
        stamps[key] = stamp(v, c);
        any = true;
      }
    } else if (key === "windows" && Array.isArray(v) && v.some((w) => get(w, "usedPercent") !== undefined)) {
      windows(v as Record<string, unknown>[], c);
    } else if (key !== "time") {
      times(v, c);
    }
  }
  if ("windows" in map && "state" in map) {
    const credits = map.credits;
    if (isObject(credits)) {
      const text =
        credits.unlimited === true
          ? t("core-views.present.credits.unlimited")
          : typeof credits.balance === "string"
            ? t("core-views.present.credits.balance", { balance: credits.balance })
            : credits.hasCredits === false
              ? t("core-views.present.credits.none")
              : t("core-views.present.credits.unknown");
      map.creditsText = text;
    }
    const count = u64(map.resetCount);
    if (count !== undefined) map.resetText = t("core-views.present.resets_left", { n: count });
  }
  if (any) map.time = stamps;
}

const NO_TICK = new Set(["live", "thread", "history", "host", "net", "status", "notices", "notify", "connection", "draft", "prefs", "doing", "adbShare", "slackTokens"]);

/// Whether a topic shows times in words, sent again each minute while shown.
export function ticks(topic: Topic): boolean {
  return !NO_TICK.has(topic.topic);
}

/// Each topic's shape (present.rs `conform`); topics with none go as they are.
const SHAPED: Record<string, Ty> = {
  chats: "ChatsView",
  chatSearch: "ChatSearchView",
  chat: "ChatView",
  stations: { vec: "StationView" },
  connects: "ConnectsView",
  history: "HistoryView",
  live: "Live",
  overview: "Overview",
  sessions: { vec: "Session" },
  session: "SessionDetail",
  threads: { vec: "ChatThread" },
  host: "Host",
  footprint: "FootprintView",
  status: "StatusView",
  connection: "ConnectionView",
  notices: "NoticesView",
  draft: "DraftView",
  notify: "NotifyView",
  archive: "ArchiveView",
  newChat: "NewChatView",
  pick: "PickView",
  chatJobs: "ChatJobsView",
  longJobs: "LongJobsView",
  usage: "UsageView",
  job: "Job",
  jobLog: "JobLogView",
  prefs: "PrefsView",
  changelog: "ChangelogView",
  connectFlow: "ConnectFlowView",
  slackTokens: "SlackTokensView",
  doing: "DoingView",
  adbShare: "AdbShareView",
  workspaceMarks: "WorkspaceMarksView",
  decisions: "DecisionsView",
};

/// A topic's value through the shape the clients are generated from: what it does not declare is dropped, and a value
/// it does not allow is an error naming the field.
export function conformTopic(topic: Topic, value: unknown): { ok: unknown } | { error: string } {
  const ty = SHAPED[topic.topic];
  if (ty === undefined) return { ok: value };
  return conform(ty, value);
}

/// What the station modules put into a topic's value as it goes out (present.rs `decorate`), by topic. Filled in by
/// the modules that own them (views, jobs, footprint…), so this file stays free of them.
export type Decorator = (value: unknown, c: Clock) => unknown;
const DECORATORS: Record<string, Decorator> = {};
/// Decorators that replace the times pass (`return` in present.rs): the value is theirs alone.
const ALONE = new Set<string>();

export function decorateWith(topic: string, decorator: Decorator, alone = false): void {
  DECORATORS[topic] = decorator;
  if (alone) ALONE.add(topic);
}

/// What goes out of a topic, with what the clients show of it put in. Returns the (possibly new) value.
export function decorate(topic: Topic, value: unknown, c: Clock): unknown {
  const own = DECORATORS[topic.topic];
  if (own && ALONE.has(topic.topic)) return own(value, c);
  if (!ticks(topic)) return value;
  if (own) value = own(value, c);
  times(value, c);
  return value;
}

export { arr };
