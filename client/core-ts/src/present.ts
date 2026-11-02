// What the clients show of a value, decided once (present.rs): times in words beside the times, and each topic's
// value through its shape (client/core-ts/src/shapes/schema.ts) as it goes out.
import { conform, type Ty } from "./conform.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import type { Topic } from "./protocol.ts";
import * as brand from "./brand.ts";
import * as decisions from "./decisions.ts";
import * as drive from "./drive.ts";
import * as prefsMod from "./prefs.ts";
import * as footprint from "./footprint.ts";
import * as jobsMod from "./jobs.ts";
import { permissionsShown } from "./permissions.ts";
import { elevationShown } from "./elevation.ts";
import * as model from "./shapes/model.ts";
import * as providers from "./shapes/providers.ts";
import { arr as arrU, equal, get as getU, isObject, shaped, str, u64 } from "./util.ts";
import { SHAPES, TOPIC_SHAPES } from "./shapes/schema.ts";
import { GROUPS as PROFILE_GROUPS, group as profileGroup, groupTitle as profileGroupTitle } from "./views/profiles.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] | undefined => arrU(v);
const get = (v: unknown, k: string | number): J => getU(v, k);

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
const MILLIS = ["createdAt", "lastActiveAt", "lastUsedAt", "checkedAt", "resetsAt"];

/// What a window with `used` percent of it used has left, and how full it is.
export function leftLevel(used: number): [number, string] {
  return [format.round(Math.max(100 - used, 0)), used >= 90 ? "red" : used >= 70 ? "amber" : "ok"];
}

function windows(list: Record<string, unknown>[], c: Clock): Record<string, unknown>[] {
  const out = list.map((w) => {
    const label = str(w.label) ?? "";
    const used = typeof w.usedPercent === "number" ? w.usedPercent : 0;
    const [mark, order] = format.windowMark(label);
    const [left, level] = leftLevel(used);
    return { ...w, label: format.windowName(label), mark, order, left, level, refills: typeof w.resetsAt === "number" ? format.refillsIn(w.resetsAt, c.now) : null };
  });
  // A stable sort, as Rust's sort_by_key.
  return out.sort((a, b) => (u64(a.order) ?? 1) - (u64(b.order) ?? 1));
}

/// Every time in a value, in words beside it: an object with some gets `time: { <field>: stamp }`; a quota's windows
/// are put as they are drawn. A new value where anything is put; a part with nothing put is the part as it was.
export function times(value: unknown, c: Clock): unknown {
  if (value !== null && typeof value === "object" && shaped.has(value)) return value;
  if (Array.isArray(value)) {
    let out: unknown[] | null = null;
    for (let i = 0; i < value.length; i++) {
      const v = times(value[i], c);
      if (v !== value[i]) (out ??= [...value])[i] = v;
    }
    return out ?? value;
  }
  if (!isObject(value)) return value;
  const map: Record<string, unknown> = { ...(value as Record<string, unknown>) };
  let changed = false;
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
      map[key] = windows(v as Record<string, unknown>[], c);
      changed = true;
    } else if (key !== "time") {
      const shown = times(v, c);
      if (shown !== v) {
        map[key] = shown;
        changed = true;
      }
    }
  }
  if ("windows" in map && "state" in map) {
    const credits = map.credits;
    if (isObject(credits)) {
      const text =
        credits.unlimited === true
          ? t("core-views.present.credits.unlimited")
          : typeof credits.balance === "string"
            ? t("core-views.present.credits.balance", { balance: format.decimal(credits.balance) })
            : credits.hasCredits === false
              ? t("core-views.present.credits.none")
              : t("core-views.present.credits.unknown");
      map.creditsText = text;
      changed = true;
    }
    const count = u64(map.resetCount);
    if (count !== undefined) {
      map.resetText = t("core-views.present.resets_left", { n: count });
      changed = true;
    }
  }
  if (any) {
    // (beside the times a value already says in words: a pull request's `updatedAt`, from its card)
    map.time = isObject(map.time) ? { ...map.time, ...stamps } : stamps;
    changed = true;
  }
  return changed ? map : value;
}

const NO_TICK = new Set(["live", "thread", "letters", "history", "host", "net", "way", "stationNet", "status", "notices", "notify", "connection", "draft", "composer", "prefs", "doing", "slackTokens", "joinable", "memberships", "screens", "screenCard"]);

/// Whether a topic shows times in words, sent again each minute while shown.
export function ticks(topic: Topic): boolean {
  return !NO_TICK.has(topic.topic);
}

/// A topic's value through the shape the clients are generated from: what it does not declare is dropped, and a value
/// it does not allow is an error naming the field.
/// A topic's shape; undefined for one that goes out as it is.
export function shapeOf(topic: Topic): Ty | undefined {
  return TOPIC_SHAPES[topic.topic];
}

/// The shape of a list's items (`Vec<T>`, `Option<Vec<T>>`).
export function itemOf(ty: Ty): Ty | undefined {
  if (typeof ty === "object" && "opt" in ty) return itemOf(ty.opt);
  return typeof ty === "object" && "vec" in ty ? ty.vec : undefined;
}

/// The shape of a struct's field.
export function fieldOf(ty: Ty, field: string): Ty | undefined {
  if (typeof ty === "object" && "opt" in ty) return fieldOf(ty.opt, field);
  if (typeof ty !== "string") return undefined;
  const shape = SHAPES[ty];
  return shape?.kind === "struct" ? shape.fields.find((f) => f.name === field)?.ty : undefined;
}

/// An item of a keyed list as `decorate` would make it inside its whole (output.ts).
export function decorateItem(topic: Topic, item: unknown, c: Clock): unknown {
  if (!ticks(topic)) return item;
  return times(topic.topic === "sessions" ? session(item as J) : item, c);
}

export function conformTopic(topic: Topic, value: unknown): { ok: unknown } | { error: string } {
  const ty = TOPIC_SHAPES[topic.topic];
  if (ty === undefined) return { ok: value };
  return conform(ty, value);
}


// ── Sessions and rows (present.rs) ──

const nonEmpty = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v.trim() : null);
const lines = (text: string): string[] => text.split("\n").map((l) => l.replace(/\r$/, ""));

/// How a session's last turn ended, in today's words (all_done, need_help, waiting).
export function ending(s: J): string | null {
  const turn = get(s, "lastTurn");
  if (!isObject(turn)) return null;
  const said = str(turn.ending) ?? str(turn.declared);
  if (said === undefined) return null;
  return said === "final" ? "all_done" : said === "block" || said === "need_decision" ? "need_help" : said;
}

/// Where a session stands.
export function sessionStatus(s: J): string {
  if (get(s, "process") === "running") return "running";
  if ((u64(get(s, "pending")) ?? 0) > 0) return "queued";
  const turn = get(s, "lastTurn");
  if (!isObject(turn)) return "idle";
  // A turn not ended yet is running, whatever `process` says: the station reads its process states before its
  // database (read/pool.ts), so a turn that has just begun can come with the process still cold.
  if (turn.endedAt === null && (turn.outcome === null || turn.outcome === undefined)) return "running";
  const e = ending(s);
  if (e === "all_done") return "final";
  if (e === "need_help") return "block";
  if (e === "waiting") return "running";
  const outcome = str(turn.outcome);
  return outcome === "failed" ? "failed" : outcome === "aborted" ? "aborted" : "unexpected";
}

/// While a session waits on work it started: since when, how long at most, and in words; null otherwise.
export function waiting(s: J): J {
  const turn = get(s, "lastTurn");
  const t0 = isObject(turn) ? turn : null;
  const since = t0 && ending(s) === "waiting" && typeof t0.endedAt === "number" && Number.isInteger(t0.endedAt) ? t0.endedAt : null;
  if (since !== null && sessionStatus(s) === "running" && get(s, "process") !== "running") {
    const what = nonEmpty(t0!.waitFor);
    return {
      since,
      seconds: t0!.waitSeconds ?? null,
      text: what !== null ? t("core-views.present.waiting_for", { what }) : t("core-views.present.waiting"),
    };
  }
  return null;
}

/// A chat's watch, when one of its agents keeps watch.
export function rowWatch(agents: J[]): J {
  const names: string[] = [];
  for (const a of agents) {
    const w = get(a, "watch");
    if (!isObject(w)) continue;
    for (const n of arr(w.names) ?? []) if (typeof n === "string") names.push(n);
  }
  if (names.length === 0) return null;
  const separator = t("core-views.list_separator");
  const named = names.map((n) => t("core-views.quoted", { text: n })).join(separator);
  return { text: t("core-views.present.watching_names", { names: names.join(separator) }), ask: t("core-views.present.watch_ask", { names: named }) };
}

/// Waiting on its watch: one runs and the agent said its wait is that (`waitWatch`; said before it, taken so). Waiting on
/// anything else, a watch running or not, it waits as any.
export function watching(s: J): boolean {
  return isObject(get(s, "watch")) && waiting(s) !== null && get(get(s, "lastTurn"), "waitWatch") !== false;
}

export function shownStatus(s: J): string {
  return watching(s) ? "idle" : sessionStatus(s);
}

export function markOf(s: J): string | null {
  return badge(shownStatus(s));
}

export function badge(status: string): string | null {
  if (status === "running" || status === "queued") return "run";
  if (status === "block" || status === "decision") return "block";
  if (status === "failed" || status === "unexpected") return "failed";
  return null;
}

export function rowState(agents: J[]): string | null {
  const marks = agents.map(markOf).filter((m) => m !== null);
  return ["block", "run", "failed"].find((b) => marks.includes(b)) ?? null;
}

/// Ended: each of its agents ended all_done and no card waits for the viewer, read or not.
export function ended(row: J): boolean {
  const agents: J[] = arr(get(row, "agents")) ?? [];
  return agents.length > 0 && agents.every((a) => shownStatus(a) === "final") && !decisions.waits(row);
}

export function settled(row: J): boolean {
  return ended(row) && get(row, "unread") !== true;
}

/// Offered for archiving with one tap (the page's bar): settled, not pinned, not kept by the viewer; and where its
/// station's archive review is on (`archiveReviewed`), only once the review recommended it.
export function archivable(row: J): boolean {
  if (!settled(row) || pinned(row) || get(row, "archiveReminderDismissed") === true) return false;
  return get(row, "archiveReviewed") !== true || get(row, "archiveRecommended") === true;
}

/// Offered to archive as the viewer's `archiveHint` says (prefs.ts archiveHintOf): faded, below the rest of its day.
/// off: never; reviewed: only once its station's archive review recommended it; done: as
/// it is archivable.
export function offered(row: J, hint: prefsMod.ArchiveHint): boolean {
  if (hint === "off" || !archivable(row)) return false;
  return hint !== "reviewed" || (get(row, "archiveReviewed") === true && get(row, "archiveRecommended") === true);
}

export function pinned(row: J): boolean {
  const p = get(row, "pinned");
  return typeof p === "number" || p === true;
}

/// The message an agent's state is about, when it is in this chat: its seq.
export function stateAbout(agent: J, thread: number | null): number | null {
  const about = get(get(agent, "lastTurn"), "about");
  if (!isObject(about)) return null;
  const at = u64(about.thread) ?? null;
  if (!(at === thread || thread === null)) return null;
  return u64(about.seq) ?? null;
}

/// What leads a state line, for a client to say as a mark of its own (`StateLead`): a bell for needs-the-viewer, a
/// check for done, the waiting arc, the watch's radar; a card waiting for the viewer (奏 · …), its lead word (`text`)
/// in bold. `rest`: what follows the lead (for watching, the whole line: its words stay after the radar).
export type Lead = { kind: "need" | "done" | "wait" | "watch" | "decision"; text?: string; rest: string };

/// Where a chat stands, in words, and the message that is about; the line without its lead (what the dot before it does
/// not say); what leads it, if anything does. A line that asks for a decision (奏 · …, 要你帮忙：…) is about none: the
/// line only says so, and the chat leads to what it asks (`ChatView.asks`). `cards` false: a card waiting is not said
/// (the chat's page, which shows the card itself).
export function rowStateLine(row: J, cards = true): [string, number | null, string, Lead | null] | null {
  const thread = u64(get(row, "thread")) ?? null;
  const p = cards ? decisions.pending(row) : null;
  const lead = t("core-logic.decisions.line", { text: "" });
  const given = str(p?.text);
  const cardLine = p ? (given ?? decisions.line(str(get(p.message, "text")) ?? "")) : "";
  const word = t("core-logic.decisions.line.empty");
  const card: [string, number | null, string, Lead | null] | null = p
    ? [
      cardLine,
      null,
      given !== undefined ? (given.startsWith(lead) ? given.slice(lead.length) : given) : decisions.question(str(get(p.message, "text")) ?? ""),
      cardLine.startsWith(word) ? { kind: "decision", text: word, rest: cardLine.slice(word.length) } : null,
    ]
    : null;
  const agents: J[] = arr(get(row, "agents")) ?? [];
  const textOf = (a: J): string | null => str(get(a, "statusText")) ?? null;
  const leadOf = (a: J): Lead | null => {
    const kind = str(get(a, "statusLead"));
    return kind === "need" || kind === "done" || kind === "wait" || kind === "watch" ? { kind, rest: str(get(a, "statusRest")) ?? "" } : null;
  };
  const said = (a: J, about: number | null): [string, number | null, string, Lead | null] | null => {
    const text = textOf(a);
    return text === null ? null : [text, about, stateWhat(a) ?? text, leadOf(a)];
  };
  const atWork = agents.some((a) => shownStatus(a) === "queued" || (shownStatus(a) === "running" && waiting(a) === null));
  if (!atWork) {
    // What it asks let go by the viewer (忽略): its agent asking says nothing on their row.
    const blocked = decisions.letGo(row) ? undefined : agents.find((a) => shownStatus(a) === "block");
    if (blocked) {
      const need = nonEmpty(get(get(blocked, "lastTurn"), "need")) !== null;
      if (card && !need) return card;
      return said(blocked, null);
    }
    const failed = agents.find((a) => ["failed", "unexpected", "aborted"].includes(shownStatus(a)));
    if (failed) return said(failed, stateAbout(failed, thread));
  }
  if (card) return card;
  if (atWork) return null;
  const waits = agents.find((a) => waiting(a) !== null);
  if (waits) return said(waits, stateAbout(waits, thread));
  if (!settled(row)) return null;
  const done = agents.find((a) => nonEmpty(get(get(a, "lastTurn"), "need")) !== null);
  const text = (done && textOf(done)) ?? t("core-views.present.done");
  const doneLead: Lead = (done && leadOf(done)) ?? { kind: "done", rest: "" };
  let about = done ? stateAbout(done, thread) : null;
  if (about === null) {
    for (const a of agents) {
      about = stateAbout(a, thread);
      if (about !== null) break;
    }
  }
  return [text, about, text, doneLead];
}

/// What a chat's agent needs a person for, let go by the viewer (忽略): its words, kept at the end of its messages,
/// said as let go. Null where nothing it needs is let go.
export function rowLetGoNeed(row: J): string | null {
  if (!decisions.letGo(row)) return null;
  const agents: J[] = arr(get(row, "agents")) ?? [];
  const blocked = agents.find((a) => shownStatus(a) === "block" && nonEmpty(get(get(a, "lastTurn"), "need")) !== null);
  return blocked === undefined ? null : stateWhat(blocked);
}

export function rowStateText(row: J): string | null {
  return rowStateLine(row)?.[0] ?? null;
}

/// An agent's state line without its lead (需要你处理：, 出错：): what it needs, why it stopped; else the line as it is.
function stateWhat(a: J): string | null {
  const status = shownStatus(a);
  const said = (k: string) => nonEmpty(get(get(a, "lastTurn"), k));
  if (waiting(a) === null) {
    const need = said("need");
    if (status === "block" && need !== null) return need;
    if (status === "failed") return format.failureText(said("detail") ?? "");
    if (status === "aborted") return t("core-logic.format.status.aborted.what");
    if (status === "unexpected") return t("core-logic.format.status.unexpected.what");
  }
  return str(get(a, "statusText")) ?? null;
}

/// What a chat's agents are doing, for the 奏 page's 正在办.
export function workingLine(row: J): string | null {
  const agents: J[] = arr(get(row, "agents")) ?? [];
  const atWork = agents.some((a) => shownStatus(a) === "queued" || (shownStatus(a) === "running" && waiting(a) === null));
  if (atWork) {
    const text = str(get(get(row, "last"), "text")) ?? "";
    const last = format.cleanText(lines(format.plainText(text)).map((l) => l.trim()).find((l) => l !== "") ?? "");
    return last === "" ? t("core-views.present.working") : t("core-views.present.working.last", { last });
  }
  for (const a of agents) {
    const w = waiting(a);
    if (w !== null) return str(w.text) ?? null;
  }
  return null;
}


/// Whether a person is the viewer.
export function isViewer(me: J, person: string, slackUsers: string[]): boolean {
  const id = str(get(me, "id"));
  const email = str(get(me, "email"));
  return id === person || (email !== undefined && email.toLowerCase() === person.toLowerCase()) || slackUsers.includes(person);
}

const sameEmail = (a: unknown, b: string) => typeof a === "string" && a.toLowerCase() === b.toLowerCase();

export function memberName(members: J[], email: string): string | null {
  const m = members.find((m) => sameEmail(get(m, "email"), email));
  const name = str(get(m, "name"));
  return name ? name : null;
}

/// Slack's `<@U…>` mentions by name: the names known by Slack id (connects' bots, Slack people), else a member's.
export function mentions(text: string, named: [string, string][], members: J[]): string {
  let out = "";
  let rest = text;
  for (;;) {
    const at = rest.indexOf("<@");
    if (at < 0) break;
    out += rest.slice(0, at);
    const tail = rest.slice(at + 2);
    let len = 0;
    while (len < tail.length && /[A-Z0-9]/.test(tail[len])) len++;
    if (len > 0 && tail[len] === ">") {
      const id = tail.slice(0, len);
      const name = named.find(([b]) => b === id)?.[1] ?? memberName(members, id) ?? id;
      out += `@${name}`;
      rest = tail.slice(len + 1);
    } else {
      out += "<@";
      rest = tail;
    }
  }
  return out + rest;
}

/// A connect's bot, while it is signed in to Slack.
export function botOf(connect: J): [string, string] | null {
  const c = get(connect, "connection");
  if (c === undefined) return null;
  const state = str(get(c, "state"));
  const on = state === "connected" || state === "reconnecting";
  const id = str(get(c, "botUserId"));
  if (id === undefined || !on) return null;
  return [id, str(get(connect, "name")) ?? ""];
}

/// A person as the clients show them (`shown`).
export function person(p: J, me: J, members: J[]): J {
  if (!isObject(p)) return p;
  const strOf = (k: string): string | null => {
    const v = (p as J)[k];
    return typeof v === "string" && v !== "" ? v : null;
  };
  const id = strOf("id") ?? "";
  const email = strOf("email");
  const key = email ?? id;
  const member = members.find((m) => sameEmail(get(m, "email"), key));
  const mName = str(get(member, "name")) || null;
  const name = id === "local" ? t("core-views.present.local_page") : (mName ?? strOf("name") ?? email ?? id);
  const mine = isViewer(me, id, []) || (email !== null && isViewer(me, email, []));
  // A Slack person's own picture, as their Slack shows it; else their workspace account's.
  const picture = strOf("picture") ?? (str(get(member, "picture")) || null);
  return { ...p, shown: { name, display: mine ? t("core-views.present.you") : name, picture, mine } };
}

/// A row's people as the clients show them.
export function rowPeople(row: J, me: J, slackUsers: string[], members: J[]): J {
  if (row.people === undefined && row.creator === undefined) return row;
  const shown = (p: J): J => {
    const q = person(p, me, members);
    const id = str(get(q, "id"));
    return id !== undefined && isViewer(me, id, slackUsers) ? { ...q, shown: { ...q.shown, mine: true, display: t("core-views.present.you") } } : q;
  };
  const creator = isObject(row.creator) ? shown(row.creator) : null;
  const keyOf = (p: J) => (str(get(p, "email")) ?? str(get(p, "id")) ?? "").toLowerCase();
  const people: J[] = creator ? [creator] : [];
  for (const p of arr(row.people) ?? []) if (!people.some((q) => keyOf(q) === keyOf(p))) people.push(shown(p));
  const display = (p: J) => str(get(get(p, "shown"), "display")) ?? "";
  const starter = creator ? people.findIndex((p) => get(p, "id") !== undefined && equal(get(p, "id"), get(creator, "id"))) : -1;
  const rest = people.filter((_, i) => i !== starter).map(display);
  const text: string[] = [];
  if (starter >= 0) text.push(t("core-views.present.started_by", { name: display(people[starter]) }));
  if (rest.length > 0) text.push(rest.join(t("core-views.list_separator")));
  return { ...row, peopleText: text.join(" · "), ...(creator ? { creator } : {}), people };
}

/// Who said a row's last thing, as its line shows them.
export function lastBy(row: J, me: J, slackUsers: string[], members: J[]): J {
  const last = get(row, "last");
  if (!isObject(last)) return null;
  const kind = str(last.authorKind) ?? "person";
  const author = str(last.author) ?? "";
  const saidName = str(last.authorName) || null;
  if (kind === "agent") {
    const agent = (arr(get(row, "agents")) ?? []).find((a) => get(a, "key") === author);
    const m = str(get(last.agentIdentity, "model")) ?? str(get(agent, "model")) ?? null;
    return {
      kind: "agent",
      name: m !== null ? model.name(m) : (saidName ?? "agent"),
      model: m,
      runtime: get(agent, "runtime") ?? "claude",
      mine: false,
      state: agent ? markOf(agent) : null,
    };
  }
  if (kind === "ember" || kind === "stillfail") return { kind: "ember", name: brand.name(), mine: false };
  const mine = isViewer(me, author, slackUsers);
  const member = members.find((m) => sameEmail(get(m, "email"), author));
  const name = mine ? t("core-views.present.you") : (str(get(member, "name")) || saidName || author);
  // A Slack person's own picture, as their Slack shows it; else their workspace account's.
  const picture = str(last.authorPicture) || str(get(member, "picture")) || null;
  return { kind: "person", id: author, name, picture, mine };
}

/// A session's summary with what the clients show of it.
export function session(s: J): J {
  if (!isObject(s)) return s;
  const status = shownStatus(s);
  let [text, tone] = format.statusText(status);
  const turn = get(s, "lastTurn");
  const said = (k: string) => nonEmpty(get(turn, k));
  // What leads the words, said by a client as a mark of its own (Lead), and what follows it.
  let lead: Lead["kind"] | null = null;
  let rest = "";
  if (status === "block") {
    const need = said("need");
    if (need !== null) text = t("core-views.present.need_help", { need });
    lead = "need";
    rest = need ?? "";
  } else if (status === "final") {
    const done = said("need");
    if (done !== null) text = t("core-views.present.done_with", { done });
    lead = "done";
    rest = done ?? "";
  } else if (status === "failed") {
    text = t("core-views.present.failed", { why: format.failureText(said("detail") ?? "") });
  }
  if (waiting(s) !== null) {
    const what = nonEmpty(get(turn, "waitFor"));
    const watched = watching(s);
    text = watched ? t("core-views.present.watching") : what !== null ? t("core-views.present.waiting_for", { what }) : t("core-views.present.waiting");
    lead = watched ? "watch" : "wait";
    rest = watched ? text : what ?? "";
  }
  const o = s as J;
  const strOf = (k: string): string | null => (typeof o[k] === "string" ? o[k] : null);
  const runtime = strOf("runtime") ?? "claude";
  const m = strOf("model");
  const first = strOf("firstText");
  const title = strOf("title") || (first !== null ? format.cleanText(first) : "") || t("core-views.new_chat");
  const b = markOf(s);
  const effort = strOf("effort");
  const process = strOf("process");
  // By hand, between turns, once there is a context (a station from before can do neither).
  const actions = Array.isArray(o.contextActions) ? (o.contextActions as unknown[]) : [];
  const between = strOf("runtimeSessionId") !== null && process !== "running" && o.running !== true;
  return {
    ...o,
    statusText: text,
    ...(lead !== null ? { statusLead: lead, statusRest: rest } : {}),
    tone,
    mark: b,
    badgeText: b !== null ? badgeText(b) : null,
    titleText: title,
    agentText: format.agentLabel(m, effort),
    modelName: m ? model.name(m) : null,
    maker: maker(m),
    runtimeText: format.runtimeLabel(runtime),
    processText: process !== null ? format.processText(process) : null,
    efforts: format.efforts(runtime),
    canCompact: between && actions.includes("compact"),
    canClear: between && actions.includes("clear"),
  };
}

export function badgeText(b: string): string {
  return b === "block" ? t("core-views.present.badge.block") : b === "run" ? t("core-views.present.badge.run") : t("core-views.present.badge.failed");
}

export function maker(m: string | null | undefined): J {
  const found = m ? format.makerOf(m) : null;
  return found ? { id: found[0], name: found[1] } : null;
}

/// A connect with its state and how it runs in words.
export function connect(c: J): J {
  if (!isObject(c)) return c;
  const o = c as J;
  const [text, presence] = format.connection(o.connection ?? null, str(o.kind) ?? null);
  const mode = str(o.mode) ?? "multi-session";
  const [modeText, modeShort] = format.modeText(mode, typeof o.requireMention === "boolean" ? o.requireMention : true);
  const bind = o.bind ?? null;
  const runtime = str(get(bind, "runtime")) ?? "claude";
  const label = format.agentLabel(str(get(bind, "model")), str(get(bind, "effort")));
  const bm = str(get(bind, "model"));
  const kind = str(o.kind) ?? null;
  const words = modeWords(kind);
  const single = mode === "single-session";
  const feishu = kind === "feishu";
  return {
    ...o,
    statusText: text,
    presence,
    modeText,
    modeShort,
    modeWords: words,
    modeLabel: single ? words.single.label : words.multi.label,
    modeSentence: single
      ? words.single.description + t(o.requireMention === false ? "web-pages.connect.everyMessageSentence" : "web-pages.connect.mentionOnlySentence")
      : words.multi.description,
    placeText: str(o.team) ?? (feishu ? (str(get(o.feishu, "domain")) === "lark" ? "Lark" : t("web-pages.connect.feishu.name")) : "Slack"),
    runtimeText: format.runtimeLabel(runtime),
    runText: `${format.runtimeLabel(runtime)} · ${label}`,
    modelName: bm ? model.name(bm) : null,
    ...(isObject(o.feishu) ? { feishu: feishuApp(o.feishu) } : {}),
  };
}

/// How a connect of `kind` says how its conversations become sessions (`ModeWords`): each way's name and what it means,
/// and what waiting for an @ does there, on and off; a Feishu connect's in its groups' words.
export function modeWords(kind: string | null): J {
  const feishu = kind === "feishu";
  const way = (m: string) => ({
    label: t(feishu ? `web-main.mode.feishu.${m}.label` : `web-main.mode.${m}.label`),
    description: t(feishu ? `web-main.mode.feishu.${m}.description` : `web-main.mode.${m}.description`),
  });
  const k = (key: string) => (feishu ? `${key}.feishu` : key);
  return { multi: way("multi"), single: way("single"), mentionOn: t(k("web-pages.connect.mentionOn")), mentionOff: t(k("web-pages.connect.mentionOff")) };
}

/// The ways a connect could be switched to (`ModeChange`: every session in one, one each, and one waiting for an @ or
/// not), each with whether it changes anything, what it does to the connect's conversations in plain words, and its
/// button's words. `running`: its sessions running now.
export function modeChanges(c: J, running: number): J[] {
  const kind = str(get(c, "kind")) ?? null;
  const mode = str(get(c, "mode")) ?? "multi-session";
  const mention = get(c, "requireMention") !== false;
  // a Feishu connect's groups in place of Slack's threads and channels
  const say = (key: string, o?: Record<string, unknown>) =>
    t(kind === "feishu" && ["toSingle", "toMulti", "threadsRestart", "mentionOnly", "noMention"].some((k) => key.endsWith(`.${k}`)) ? `${key}.feishu` : key, o);
  const effects = (next: string, nextMention: boolean): string[] => {
    const out: string[] = [];
    if (mode === "multi-session" && next === "single-session") {
      out.push(say("web-pages.connect.effects.toSingle"));
      out.push(say(str(get(c, "session")) ? "web-pages.connect.effects.resumeSingle" : "web-pages.connect.effects.newSingle"));
      if (!nextMention) out.push(say("web-pages.connect.effects.noMention"));
    } else if (mode === "single-session" && next === "multi-session") {
      out.push(say("web-pages.connect.effects.toMulti"));
      out.push(say("web-pages.connect.effects.threadsRestart"));
      out.push(say("web-pages.connect.effects.switchBack"));
    } else if (nextMention !== mention) {
      out.push(say(nextMention ? "web-pages.connect.effects.mentionOnly" : "web-pages.connect.effects.noMention"));
    }
    if (running > 0) out.push(say("web-pages.connect.effects.running", { n: running }));
    return out;
  };
  return ([["multi-session", true], ["single-session", true], ["single-session", false]] as const).map(([next, nextMention]) => {
    const changed = next !== mode || (next === "single-session" && nextMention !== mention);
    const action = next === mode ? "web-pages.connect.confirmChange" : next === "single-session" ? "web-pages.connect.toSingle" : "web-pages.connect.toMulti";
    return { mode: next, requireMention: nextMention, changed, effects: changed ? effects(next, nextMention) : [], action: t(action) };
  });
}

/// A Slack app's permissions as its form shows them, in sections (mirrors SLACK_GROUPS on the station): each group's
/// name, what it lets the app do, and, for those only Slack's admins allow, what they must allow (its tip says both);
/// `fixed`: always on.
const SLACK_SECTIONS: [string, string[]][] = [
  ["messages", ["base", "public", "dm", "customize", "reactions"]],
  ["channels", ["channels", "topics", "connect"]],
  ["files", ["files", "canvases", "lists"]],
  ["people", ["people", "usergroups", "search"]],
  ["other", ["extras", "more"]],
];
const SLACK_ADMIN = new Set(["connect", "usergroups"]);

export function slackSections(): J[] {
  return SLACK_SECTIONS.map(([section, groups]) => ({
    title: t(`web-pages.slackApp.section.${section}`),
    groups: groups.map((g) => {
      const description = t(`web-pages.slackApp.group.${g}.description`);
      const admin = SLACK_ADMIN.has(g) ? t(`web-pages.slackApp.group.${g}.admin`) : null;
      return { id: g, label: t(`web-pages.slackApp.group.${g}`), description, admin, tip: admin !== null ? `${description} ${admin}` : description, fixed: g === "base" };
    }),
  }));
}

/// A Feishu connect's app, with its page in the developer console (Lark's on its own domain).
function feishuApp(f: J): J {
  const id = str(get(f, "appId")) ?? "";
  const domain = str(get(f, "domain")) === "lark" ? "lark" : "feishu";
  const open = domain === "lark" ? "https://open.larksuite.com" : "https://open.feishu.cn";
  return { appSecret: "", ...f, appId: id, domain, console: id !== "" ? `${open}/app/${encodeURIComponent(id)}` : null };
}

/// A profile with its last check in words, its models' makers and series, what it can do, and its trouble.
export function profile(p: J): J {
  if (!isObject(p)) return p;
  const o: J = { ...p };
  if (get(o.access, "kind") === "env" && typeof get(o.access, "provider") === "string") o.access = { ...o.access, kind: "api-provider" };
  const blocked = get(o.quota, "state") === "blocked";
  const [text, tone] = blocked ? [t("core-views.present.profile.blocked"), "red"] : format.checkText(o.check ?? null);
  o.checkText = text;
  o.checkTone = tone;
  o.trouble = profileTrouble(o);
  // The kind of account it is listed under, as the workspace's list has it (views/profiles.ts).
  o.group = profileGroup(o);
  o.groupTitle = profileGroupTitle(o.group);
  const strs = (list: J[]) => list.filter((m): m is string => typeof m === "string");
  // What it runs: those named in config.json, then the rest its check found (the station's `models`).
  const all = strs(arr(o.models) ?? []);
  const found = new Set(strs(arr(get(o.check, "models")) ?? []).map(model.key));
  const makers: Record<string, J> = {};
  for (const m of all) makers[m] = maker(m);
  const modelsText = all.length === 0 ? t("core-views.present.profile.no_models") : t("core-views.present.profile.models", { n: all.length });
  const bySeries = series([...all].sort());
  // Named by hand and not listed by its provider: the ones that can be taken off.
  const added = strs(arr(o.named) ?? []).filter((m) => !found.has(model.key(m)));
  const names: Record<string, string> = {};
  for (const m of [...all, ...strs(o.model !== undefined ? [o.model] : [])]) if (m !== "") names[m] = model.name(m);
  const [usesList, provider] = uses(o);
  const pid = str(get(o.access, "provider"));
  const src = pid !== undefined ? providers.find(pid) : null;
  const decisionOnly = src !== null && !!src.decision && !src.chat && !src.responses && !src.anthropic;
  o.canAddModel = (get(o.access, "kind") === "api-provider" && !decisionOnly) || get(o.access, "kind") === "env";
  if (decisionOnly) {
    const f = get(o.check, "decision") ?? null;
    o.decisionOnly = true;
    o.decisionModels = get(f, "state") === "ready" ? (get(f, "models") ?? []) : [];
    // Said in the viewer's language from what the station names (`reason`); a station from before that, as it said it.
    const reason = str(get(f, "reason")) ?? "";
    o.decisionText = DECISION_REASONS.includes(reason)
      ? t(`core-views.present.profile.decision.${reason}`, { n: o.decisionModels.length })
      : str(get(f, "detail")) || t("core-views.present.profile.decision_pending");
  }
  o.uses = usesList;
  const kind = get(o.access, "kind");
  const plain = (kind === "subscription" || kind === "env") && !usesList.includes("decision");
  o.usesText = plain ? "" : usesText(usesList);
  if (provider) {
    o.providerName = provider[0];
    o.providerMark = provider[1];
  }
  o.makers = makers;
  o.names = names;
  o.series = bySeries;
  o.modelsText = modelsText;
  o.available = all;
  o.added = added;
  o.modelsReading = !isObject(o.check) && !decisionOnly;
  // What it is, in a word (a page's facts): the machine's own login, its provider, else its kind of account.
  o.kindText = o.machine === true ? t("core-views.present.profile.machine") : (o.providerName ?? accessLabel(str(kind) ?? ""));
  // Who a sign-in goes to: OpenCode for OpenCode Go, Kimi for Kimi Code, else its runtime's vendor.
  o.signInProvider = kind === "opencode-go" ? "OpenCode" : get(o.access, "provider") === "kimi-code" ? "Kimi"
    : (SIGN_IN[str(o.runtime) ?? ""] ?? "ChatGPT");
  // Its last check in a line (its detail, without the 可用 (Works) a working one starts with: its state says that, nor the
  // address it signed in as where that is its name: its head says it), or that it has none yet.
  const detailOf = str(get(o.check, "detail"));
  const named = str(o.name) ?? "";
  o.checkLine = isObject(o.check)
    ? withoutPart((detailOf ?? "").replace(/^(可用[，,]|Works,)\s*/, ""), named)
    : t("core-views.present.profile.never_checked");
  return o;
}

/// A line of parts (a detail's: 已登录，an address，a plan) without the part that is `part` and the comma before it.
function withoutPart(line: string, part: string): string {
  if (part === "") return line;
  const pieces = line.split(/([，,]\s*)/);
  const kept: string[] = [];
  for (let i = 0; i < pieces.length; i += 2) {
    if (pieces[i] === part) continue;
    if (kept.length > 0) kept.push(pieces[i - 1]);
    kept.push(pieces[i]);
  }
  return kept.join("");
}

/// Who a runtime's subscription signs in to.
const SIGN_IN: Record<string, string> = { claude: "Claude", grok: "Grok", cursor: "Cursor", devin: "Devin" };

/// A kind of account in words.
function accessLabel(kind: string): string {
  switch (kind) {
    case "subscription": return t("core-views.present.access.subscription");
    case "opencode-go": return "OpenCode Go";
    case "anthropic-api": return "Anthropic API";
    case "api-provider": return t("core-views.present.access.provider");
    case "env": return t("core-views.present.access.env");
    default: return "";
  }
}

const KINDS = new Set(["subscription", "anthropic-api", "opencode-go", "api-provider", "env"]);

function uses(p: J): [string[], [string, string | null] | null] {
  const runs = (r: string) => (arr(p.runtimes) ?? []).includes(r);
  const k = str(get(p.access, "kind"));
  const kind = k !== undefined && KINDS.has(k) ? k : null;
  let source: providers.Source | null = null;
  let at: providers.Endpoints | null = null;
  if (kind === "api-provider") {
    const id = str(get(p.access, "provider"));
    source = id !== undefined ? providers.find(id) : null;
    at = source ? providers.endpoints(source, str(get(p.access, "endpoint")), str(get(p.access, "protocol"))) : null;
  } else if (kind === "opencode-go" || kind === "anthropic-api") {
    source = providers.ofKind(kind);
    at = source ? providers.endpoints(source, null, null) : null;
  }
  // A Kimi Code sign-in has no key a decision could be asked with (its token is renewed every few minutes).
  const signedIn = get(p.access, "login") === true;
  const decision = (at !== null && at.chat !== null && !signedIn) || get(get(p.check, "decision"), "state") === "ready";
  const list = [...format.RUNTIMES.filter(runs), ...(decision ? ["decision"] : [])];
  const provider: [string, string | null] | null = source && kind === "api-provider" ? [source.name, source.mark ?? null] : null;
  return [list, provider];
}

/// What a profile can do (`claude`, `codex`, `dsh`, `grok`, `cursor`, `devin`, `decision`), in words: Claude Code · DeepSeek Harness · 自动决策.
export function usesText(list: string[]): string {
  return list.map((u) => (u === "decision" ? t("core-views.present.uses.decision") : format.runtimeLabel(u))).join(" · ");
}

/// Provider/check states to a safe next step.
export function profileTrouble(p: J): J {
  const check = get(p, "check");
  const quota = get(p, "quota");
  const detail = (v: J, fallback: string) => {
    const d = get(v, "detail");
    return typeof d === "string" && d.trim() !== "" ? d : fallback;
  };
  const issue = (title: string, d: string, next: string, action: string, label: string) => ({ title, detail: d, next, action, label });
  if (get(quota, "state") === "blocked")
    return issue(t("core-views.present.trouble.blocked"), detail(quota, t("core-views.present.trouble.blocked_detail")), t("core-views.present.trouble.blocked_next"), "quota", t("core-views.present.trouble.quota_again"));
  const state = get(check, "state");
  if (state === "login" || state === "failed") {
    const title = state === "login" ? t("core-views.present.trouble.login") : t("core-views.present.trouble.check_failed");
    const why = detail(check, title);
    const machine = get(p, "machine") === true;
    if (machine && state === "login") return issue(title, why, t("core-views.present.trouble.command_next"), "command", t("core-views.present.trouble.command_label"));
    const kind = str(get(get(p, "access"), "kind"));
    // A subscription, or a profile signed in to an account (OpenCode Go's, Kimi Code's): signed in again.
    const signsIn = kind === "subscription" || get(get(p, "access"), "login") === true;
    if (signsIn && !machine && state === "login") return issue(title, why, t("core-views.present.trouble.login_next"), "login", t("core-views.present.trouble.login_label"));
    if (kind === "anthropic-api" || kind === "opencode-go" || kind === "api-provider") return issue(title, why, t("core-views.present.trouble.key_next"), "key", t("core-views.present.trouble.key_label"));
    if (kind === "env") return issue(title, why, t("core-views.present.trouble.env_next"), "env", t("core-views.present.trouble.env_label"));
    return issue(title, why, t("core-views.present.trouble.check_next"), "check", t("core-views.present.trouble.check_label"));
  }
  if (get(quota, "state") === "unavailable")
    return issue(t("core-views.present.trouble.unavailable"), detail(quota, t("core-views.present.trouble.unavailable_detail")), t("core-views.present.trouble.unavailable_next"), "quota", t("core-views.present.trouble.quota_again"));
  return null;
}

/// Models by series, newest first, those of no known series last as 其他.
export function series(models: string[]): J {
  const sortedModels = [...models].sort(model.compareOrder);
  const out: [string, string[]][] = [];
  for (const m of sortedModels) {
    const fam = model.family(m) ?? t("core-views.present.models_other");
    const found = out.find(([f]) => f === fam);
    if (found) found[1].push(m);
    else out.push([fam, [m]]);
  }
  return out.map(([name, list]) => ({ name, models: list }));
}

const GIB = 1024 ** 3;

/// A machine as the clients show it.
export function host(h: J): J {
  if (!isObject(h)) return h;
  const src = h as J;
  const o: J = { ...src };
  const n = (...path: string[]): number => {
    let v: J = src;
    for (const k of path) v = get(v, k);
    return typeof v === "number" ? v : 0;
  };
  const cpus = n("cpus");
  const load = n("load");
  const uptime = n("uptimeSec");
  const memUsed = n("memory", "usedBytes");
  const memTotal = n("memory", "totalBytes");
  const diskFree = n("disk", "freeBytes");
  const diskTotal = n("disk", "totalBytes");
  const os = str(src.os) ?? "";
  const cores = t("core-views.present.host.cores", { n: cpus });
  const summary = `${cores} · ${format.gb(memTotal)}`;
  const days = Math.floor(uptime / 86_400);
  const hours = Math.floor((uptime % 86_400) / 3600);
  o.summary = summary;
  o.line = `${os} · ${summary} · ${t("core-views.present.host.up_days", { n: days })}`;
  const arch = str(src.arch) ?? "";
  // Each as the allowances are drawn: how much is left (`left`, its fill and cells) and that in words; on a machine's
  // own page, that large (`big` `unit`), what it is (`title`) and what it is out of (`total`).
  const meter = (label: string, short: string, percent: number, value: string, note: string | null, room: { remaining: string; big: string; unit: string; title: string; total: string }) => {
    const p = format.round(Math.min(Math.max(percent, 0), 100));
    return { label, short, percent: p, left: 100 - p, level: p >= 90 ? "red" : p >= 75 ? "amber" : "ok", value, note, ...room };
  };
  const swap = n("memory", "swapUsedBytes");
  const cpuModel = str(src.cpuModel) || null;
  const busy = src.cpuBusy;
  const cpuPercent = typeof busy === "number" ? busy * 100 : load * 100;
  const idle = format.round(100 - Math.min(Math.max(cpuPercent, 0), 100));
  const loadText = t("core-views.present.host.load", { load: format.fixed1(load * cpus) });
  const cpuRoom = { remaining: t("core-views.present.host.idle", { percent: idle }), big: String(idle), unit: "%", title: t("core-views.present.host.cpu_idle"), total: loadText };
  const cpu =
    typeof busy === "number"
      ? meter("CPU", "CPU", cpuPercent, `${format.round(cpuPercent)}%`, [loadText, cpuModel].filter((x) => x !== null).join(" · "), cpuRoom)
      : meter(t("core-views.present.host.cpu_load"), "CPU", cpuPercent, `${format.round(cpuPercent)}%`, cpuModel, cpuRoom);
  o.facts = [
    str(src.hostname) ?? "",
    os,
    `${arch} · ${cores}`,
    days > 0 ? t("core-views.present.host.up_days_hours", { days, hours }) : t("core-views.present.host.up_hours", { hours }),
  ];
  const remaining = (bytes: number) => t("core-views.present.host.remaining", { size: format.fixed1(Math.max(bytes, 0) / GIB) });
  // What is left in gigabytes, large: one decimal below 100.
  const big = (bytes: number) => format.gb1(Math.max(bytes, 0)).replace(/ GB$/, "");
  const memory = meter(t("core-views.present.host.memory"), t("core-views.present.host.memory_short"), memTotal > 0 ? (memUsed / memTotal) * 100 : 0, `${format.gb1(memUsed)} / ${format.gb1(memTotal)}`, swap > 0 ? `swap ${format.gb1(swap)}` : null, {
    remaining: remaining(memTotal - memUsed), big: big(memTotal - memUsed), unit: "GB", title: t("core-views.present.host.memory_left"), total: t("core-views.present.host.out_of", { size: format.gb(memTotal) }),
  });
  const disk = meter(t("core-views.present.host.disk"), t("core-views.present.host.disk_short"), diskTotal > 0 ? ((diskTotal - diskFree) / diskTotal) * 100 : 0, t("core-views.present.host.disk_value", { free: format.gb1(diskFree), total: format.gb1(diskTotal) }), null, {
    remaining: remaining(diskFree), big: big(diskFree), unit: "GB", title: t("core-views.present.host.disk_left"), total: t("core-views.present.host.out_of", { size: format.gb(diskTotal) }),
  });
  // What the machine is, the same line wherever it is named: its chip, its memory, its system.
  o.identity = [cpuModel, memTotal > 0 ? format.gb(memTotal) : null, os || null].filter((x) => x !== null).join(" · ");
  // The rest, a row each, only where the machine is looked at closely.
  const uptimeText = days > 0 ? t("core-views.present.host.uptime_days_hours", { days, hours }) : t("core-views.present.host.uptime_hours", { hours });
  o.details = [
    { label: t("core-views.present.host.hostname"), value: str(src.hostname) ?? "" },
    { label: t("core-views.present.host.chip"), value: [cpuModel, cpus > 0 ? cores : null, arch || null].filter((x) => x !== null).join(" · ") },
    { label: t("core-views.present.host.uptime"), value: uptimeText },
    { label: brand.name(), value: t("core-views.present.host.process", { size: `${format.round(n("emberRssBytes") / 1024 ** 2)} MB` }) },
  ].filter((d) => d.value !== "");
  o.meters = [cpu, memory, disk];
  o.usage = [memory, disk].map((m) => `${m.label} ${m.value}`).join(" · ");
  o.emberText = `${brand.name()} ${format.round(n("emberRssBytes") / 1024 ** 2)} MB`;
  return o;
}

/// How a connection to a station goes, in words (直连, Tailscale, 北京中继) and as a word to tell apart (Tailscale's is
/// direct: no relay of still.fail's or the workspace's on the way): a reading's (`net`) or
/// its way alone (`way`), `{ path, relay }`.
function reached(r: J, relayName: (host: string) => string | null): { path: string; via: string } {
  const relayHost = str(r.relay) || null;
  const path =
    r.path === "direct"
      ? t("core-views.present.net.direct")
      : r.path === "tailnet"
        ? t("core-views.present.net.tailnet")
        : r.path === "relay"
        ? relayHost !== null
          ? (() => {
              const name = relayName(relayHost);
              return name !== null ? t("core-views.present.net.relay_named", { name }) : t("core-views.present.net.relay_host", { host: relayHost });
            })()
          : t("core-views.present.net.relay")
        : t("core-views.present.net.choosing");
  return { path, via: r.path === "direct" || r.path === "tailnet" ? "direct" : r.path === "relay" ? "relay" : "choosing" };
}

/// How a station is reached as the places that name it show it (`StationWay`), from its `way`.
export function way(raw: J, relayName: (host: string) => string | null): J {
  if (!isObject(raw)) return null;
  return reached(raw, relayName);
}

/// A station's connection as its card shows it (`StationNet`).
export function net(raw: J, relayName: (host: string) => string | null): J {
  if (!isObject(raw)) return null;
  const r = raw as J;
  const { path, via } = reached(r, relayName);
  const samples: J[] = arr(r.samples) ?? [];
  const figure = (ms: number) => ({
    text: ms >= 1000 ? `${format.fixed1(ms / 1000)} s` : `${Math.max(format.round(ms), 1)} ms`,
    level: ms >= 1000 ? "red" : ms >= 300 ? "amber" : "ok",
  });
  const rtt = typeof r.rttMs === "number" ? figure(r.rttMs) : null;
  const named = (h: string) => relayName(h) ?? h;
  const through = r.path === "relay" ? (str(r.relay) ?? null) : null;
  const m = r.measured;
  const measured = isObject(m)
    ? {
        measuring: m.measuring === true,
        relays: (arr(m.relays) ?? []).flatMap((x: J) => {
          const h = str(get(x, "relay"));
          if (h === undefined) return [];
          const ms = get(x, "rttMs");
          // "direct": the way that goes straight there, no relay.
          if (h === "direct") return [{ name: t("core-views.present.net.direct"), rtt: typeof ms === "number" ? figure(ms) : null, current: r.path === "direct" }];
          if (h === "tailnet") return [{ name: t("core-views.present.net.tailnet"), rtt: typeof ms === "number" ? figure(ms) : null, current: r.path === "tailnet" }];
          return [{ name: named(h), rtt: typeof ms === "number" ? figure(ms) : null, current: through === h }];
        }),
        moved: typeof m.moved === "string" ? named(m.moved) : null,
      }
    : null;
  const history = samples.map((s) => get(s, "rttMs")).filter((x): x is number => typeof x === "number").map((ms) => format.round(ms * 10) / 10);
  const lastSample = samples[samples.length - 1];
  const rate = (key: string) => {
    const b = get(lastSample, key);
    return typeof b === "number" ? `${format.bytes(b)}/s` : "—";
  };
  const num = (key: string) => (typeof r[key] === "number" ? r[key] : 0);
  let sent = 0;
  let lost = 0;
  for (const s of samples) {
    sent += typeof get(s, "sent") === "number" ? get(s, "sent") : 0;
    lost += typeof get(s, "lost") === "number" ? get(s, "lost") : 0;
  }
  const daily = typeof r.todayRxBytes === "number";
  const [rx, tx] = daily ? [num("todayRxBytes"), num("todayTxBytes")] : [num("rxBytes"), num("txBytes")];
  // Over a minute of a quiet link a lost packet or two is most of what there is to count: shown once enough went.
  const loss =
    sent >= 100 && lost / sent >= 0.01
      ? (() => {
          const pct = (lost / sent) * 100;
          return { text: t("core-views.present.net.loss", { percent: format.fixed1(pct) }), level: pct >= 10 ? "red" : "amber" };
        })()
      : null;
  return {
    path,
    via,
    rtt,
    rttHistory: history,
    down: rate("rxBps"),
    up: rate("txBps"),
    total: daily
      ? t("core-views.present.net.total_today", { down: format.bytes(rx), up: format.bytes(tx) })
      : t("core-views.present.net.total_session", { down: format.bytes(rx), up: format.bytes(tx) }),
    downTotal: format.bytes(rx),
    upTotal: format.bytes(tx),
    loss,
    measured,
    lan: (arr(r.lan) ?? []).filter((a: J) => typeof a === "string"),
  };
}

// ── Decoration ──

/// What the views put into a topic's value as it goes out (theirs: chats, chat, archive…), by topic; registered by
/// the views so this file stays free of them.
export type Decorator = (value: unknown, c: Clock) => unknown;
const DECORATORS: Record<string, Decorator> = {};

export function decorateWith(topic: string, decorator: Decorator): void {
  DECORATORS[topic] = decorator;
}

/// What goes out of a topic, with what the clients show of it put in. Returns the (possibly new) value.
export function decorate(topic: Topic, value: unknown, c: Clock): unknown {
  switch (topic.topic) {
    case "host":
      return host(value);
    case "footprint":
      return footprint.shown(value, c);
    case "drive":
      return drive.shown(value, c);
    case "prefs":
      return prefsMod.shown(value);
  }
  if (!ticks(topic)) return value;
  const v = value as J;
  switch (topic.topic) {
    case "sessions":
      if (Array.isArray(v)) value = v.map((s) => (shaped.has(s) ? s : session(s)));
      break;
    case "session":
      if (isObject(v) && v.session !== undefined) value = { ...v, session: session(v.session) };
      break;
    case "overview":
      if (isObject(v)) value = overview(v as J, c, typeof topic.station === "string" ? topic.station : null);
      break;
    case "chat": {
      const agents = arr(get(v, "agents"));
      if (agents) value = { ...v, agents: agents.map((a) => (Array.isArray(get(a, "jobs")) ? { ...a, jobs: a.jobs.map((j: J) => jobsMod.shown(j, c)) } : a)) };
      break;
    }
    case "job":
      value = jobsMod.shown(v, c);
      break;
    case "jobLog":
      value = jobsMod.log(v, c);
      break;
    case "slackApp":
      if (isObject(v)) value = { ...v, sections: slackSections() };
      break;
    // A web link's card: when a pull request or an issue last changed, in words (3 小时前).
    case "linkPreview":
      if (isObject(v) && typeof v.updatedAt === "number" && v.updatedAt > 0) value = { ...v, time: { updatedAt: stamp(v.updatedAt, c) } };
      break;
    // A file's card: when it was last written, in words.
    case "filePeek":
      if (isObject(v) && typeof v.mtime === "number" && v.mtime > 0) value = { ...v, time: { mtime: stamp(v.mtime, c) } };
      break;
  }
  const own = DECORATORS[topic.topic];
  if (own) value = own(value, c);
  return times(value, c);
}

function overview(value: J, c: Clock, station: string | null): J {
  const v: J = { ...value };
  // A Mac station's grants to still.fail Helper, in words (permissions.ts); none said, none shown.
  const permissions = station === null ? undefined : permissionsShown(v.permissions, station);
  if (permissions === undefined) delete v.permissions;
  else v.permissions = permissions;
  // A Windows station's running as administrator, in words (elevation.ts); none said, none shown.
  const elevation = elevationShown(v.elevation);
  if (elevation === undefined) delete v.elevation;
  else v.elevation = elevation;
  const decided = v.automaticDecisions;
  if (isObject(decided)) {
    const shown: J = { ...decided };
    const recent = arr(decided.recent);
    if (recent) shown.recent = recent.map((row) => (typeof get(row, "at") === "number" ? { ...row, stamp: stamp(row.at, c) } : row));
    if (isObject(decided.policy)) shown.policy = archivePolicy(decided.policy as J, c);
    v.automaticDecisions = shown;
  }
  if (isObject(v.archiving)) v.archiving = archiving(v.archiving as J, v.automaticDecisions);
  const processes = arr(v.processes);
  if (processes) {
    let mb = 0;
    for (const p of processes) if (typeof get(p, "rssMb") === "number") mb += p.rssMb;
    v.processesText =
      processes.length === 0
        ? t("core-views.present.processes.none")
        : t("core-views.present.processes.running", { n: processes.length, size: mb >= 1024 ? `${format.fixed1(mb / 1024)} GB` : `${mb} MB` });
  }
  if (isObject(v.footprint)) v.footprint = footprint.brief(v.footprint);
  const connects = arr(v.connects);
  if (connects) v.connects = connects.map(connect);
  const updates = arr(v.updates);
  if (updates) v.updates = updates.map((u) => software(get(u, "id") === "station" ? { ...u, name: "Station" } : u));
  const listed = arr(v.profiles);
  // A stable sort: by kind of account (a station's list is a section each), those in trouble first in each.
  const kindOf = (p: J) => PROFILE_GROUPS.indexOf(get(p, "group"));
  const profiles = listed?.map(profile).sort((a, b) => kindOf(a) - kindOf(b) || Number(get(a, "trouble") === null) - Number(get(b, "trouble") === null));
  if (profiles) v.profiles = profiles;
  const subscriptions: [J, string][] = [];
  const taken: J[] = [];
  for (const p of profiles ?? []) {
    if (get(get(p, "access"), "kind") === "subscription") {
      const runtime = get(p, "runtime");
      const email = str(get(p, "email"));
      if (runtime !== undefined && email !== undefined && email.trim() !== "") subscriptions.push([runtime, email.trim().toLowerCase()]);
    }
    if (get(p, "machine") === true && get(p, "runtime") !== undefined) taken.push(get(p, "runtime"));
  }
  const logins = arr(v.machineLogins);
  if (logins) {
    v.machineLogins = logins.map((l) => {
      const plan = get(l, "plan");
      const email = str(get(l, "email"));
      const offered =
        get(l, "loggedIn") === true &&
        typeof plan === "string" &&
        plan !== "" &&
        !(get(l, "runtime") !== undefined && taken.some((r) => equal(r, get(l, "runtime")))) &&
        !(email !== undefined && subscriptions.some(([runtime, bound]) => equal(get(l, "runtime"), runtime) && email.trim().toLowerCase() === bound));
      const planText = typeof plan === "string" ? planName(plan) : "";
      return isObject(l) ? { ...l, offered, planText } : l;
    });
  }
  return v;
}

/// A subscription's plan as its vendor names it, from the word its login keeps (Claude's `max`, ChatGPT's `plus`,
/// `prolite`, `free_workspace`): those not plain words as said, the rest each word capitalized.
const PLAN_NAMES: Record<string, string> = { prolite: "Pro Lite" };

function planName(plan: string): string {
  return PLAN_NAMES[plan.toLowerCase()] ?? plan.split(/[_\s]+/).filter((w) => w !== "").map((w) => `${w[0]!.toUpperCase()}${w.slice(1)}`).join(" ");
}

/// The days a station's automatic archiving offers to wait (设置 › 归档): once idle, and heard only in Slack (0: never).
export const IDLE_DAYS = [1, 3, 7, 30];
export const SLACK_DAYS = [0, 3, 7, 30];

/// Days, as a choice says them: none is never.
function daysText(n: number): string {
  return n <= 0 ? t("web-pages.archiving.never") : t("web-pages.archiving.days", { n });
}

/// The days offered, with the one kept when it is none of them.
export function daysOffered(kept: number, base: number[]): number[] {
  return kept > 0 && !base.includes(kept) ? [...base, kept].sort((a, b) => a - b) : base;
}

/// The ways a station can archive on its own, in their order.
const ARCHIVE_MODES = ["off", "idle", "reviewed"] as const;

/// Whether a station's archive review (自动决策 › 归档建议) is on, and that said alone, by which model (`decided`: its
/// overview's `automaticDecisions`).
export function archiveReview(decided: J): { on: boolean; text: string } {
  const rule = get(get(decided, "settings"), "completion");
  const on = get(rule, "enabled") === true;
  const id = typeof get(rule, "model") === "string" ? (get(rule, "model") as string) : "";
  const model = (arr(get(decided, "models")) ?? []).find((m) => get(m, "id") === id);
  const name = typeof get(model, "name") === "string" ? (get(model, "name") as string) : id;
  return { on, text: on ? t("web-pages.archiving.reviewOnShort", { model: name }) : t("web-pages.archiving.reviewOffShort") };
}

/// How a station archives on its own, as its row and its page in 设置 › 归档 say it: `mode`, never (no days), once
/// idle, or once idle and recommended by its review (`off`, `idle`, `reviewed`); that in a line with Slack's
/// (`summaryText`); and the days each choice offers (`daysOffered`, `slackDaysOffered`, with their words). With its
/// review (`decided`: its overview's `automaticDecisions`): whether it is on (`reviewOn`, `reviewText`), whether what is
/// set waits on a review that is off (`stalled`, its row's line `lineText` then saying so), each way to choose and what
/// choosing it saves (`modes`: its days and whether reviewed; not `allowed` to be recommended by a review that is off),
/// and what the way chosen does (`modeNote`).
export function archiving(view: J, decided?: J): J {
  const days = typeof view.days === "number" ? view.days : 0;
  const slack = typeof view.slackDays === "number" ? view.slackDays : 0;
  const mode = days <= 0 ? "off" : view.reviewed === true ? "reviewed" : "idle";
  const how = mode === "off" ? t(`web-pages.archiving.mode.${mode}`) : `${t(`web-pages.archiving.mode.${mode}`)} · ${daysText(days)}`;
  const review = archiveReview(decided);
  const summaryText = t("web-pages.archiving.summary", { how, slack: daysText(slack) });
  const stalled = mode === "reviewed" && !review.on;
  const offered = daysOffered(days, IDLE_DAYS);
  const slackOffered = daysOffered(slack, SLACK_DAYS);
  const note = t(`web-pages.archiving.mode.${mode}Hint`);
  return {
    ...view,
    mode,
    summaryText,
    daysOffered: offered,
    slackDaysOffered: slackOffered,
    daysOfferedText: offered.map(daysText),
    slackDaysOfferedText: slackOffered.map(daysText),
    reviewOn: review.on,
    reviewText: review.text,
    stalled,
    lineText: stalled ? t("web-pages.archiving.stalled") : summaryText,
    modes: ARCHIVE_MODES.map((m) => ({
      mode: m,
      label: t(`web-pages.archiving.mode.${m}`),
      // off forgets the days; idle or reviewed keeps those kept, or one
      days: m === "off" ? 0 : days > 0 ? days : 1,
      reviewed: m === "reviewed",
      allowed: !(m === "reviewed" && !review.on && mode !== "reviewed"),
    })),
    modeNote: review.on ? note : `${note} ${t(mode === "reviewed" ? "web-pages.archiving.reviewNeeded" : "web-pages.archiving.stationNeedsReview")}`,
  };
}

/// The archive policy's lines: the checks it counted, and who changed it last, where, when and what.
function archivePolicy(policy: J, c: Clock): J {
  const p: J = { ...policy };
  const failed = u64(p.failed) ?? 0;
  const counted = t("core-views.policy.checked", { n: u64(p.checked) ?? 0, days: u64(p.days) ?? 7 });
  p.summaryText = failed > 0 ? `${counted} · ${t("core-views.policy.failed", { n: failed })}` : counted;
  const change = p.change;
  if (!isObject(change)) return p;
  const by: J = change.by ?? {};
  const who =
    by.kind === "agent"
      ? t("core-views.policy.byAgent", { agent: format.runtimeLabel(str(by.runtime) || "claude"), chat: str(by.title) || str(by.session) })
      : str(by.name) || str(by.email) || t("core-views.policy.someone");
  const when = typeof change.at === "number" ? format.relativeTime(change.at, c.now, c.offsetMin) : "";
  p.changeText = [t("core-views.policy.changedBy", { who }), when, str(change.summary)].filter((x) => x !== "").join(" · ");
  return p;
}

/// The station's reasons for what a profile can decide with (station/src/sessions/decision.ts), each said in words.
const DECISION_REASONS = ["no_probabilities", "signed_out", "address", "found", "none_verified", "changed"];

/// A runtime the station does not have (a chat's notice says so, or a plan's sign-in runs its command): installing it
/// there, as the station's updates (`updates`, its overview's) say it stands, and whether the viewer may (`manages`: the
/// workspace's owner or an admin), in a line (`title`: not installed, installing, could not, installed). Nothing offered
/// by a station older than its updates.
export function installView(runtime: string, updates: J[], manages: boolean): J | null {
  const v = updates.find((u) => get(u, "id") === runtime);
  if (v === undefined) return null;
  const name = str(v.name) ?? format.runtimeLabel(runtime);
  if (v.state === "updating") {
    const percent = u64(v.percent);
    return { runtime, state: "installing", title: t("core-views.install.installing", { name }), ...(percent !== undefined ? { percent } : {}) };
  }
  if (v.installed === true) return { runtime, state: "installed", title: t("core-views.install.installed", { name }) };
  const can = manages && v.updatable === true;
  if (v.state === "failed") {
    const why = str(v.message);
    return { runtime, state: "failed", title: t("core-views.install.failed", { name }), ...(why ? { detail: why } : {}), ...(can ? { action: t("core-views.install.retry") } : {}) };
  }
  const title = t("core-views.install.missing", { name });
  if (can) return { runtime, state: "missing", title, action: t("core-views.install.action") };
  const why = str(v.note) ?? (manages ? null : t("core-views.install.managers_only"));
  return { runtime, state: "missing", title, ...(why !== null ? { note: why } : {}) };
}

/// A piece of software as it is said (the web's Versions.tsx describe): its version as shown, what is said of it on
/// hover (up to date, or that the last check failed), and while it updates or once that failed, in words.
export function software(u: J): J {
  const installed = get(u, "installed") === true;
  const version = typeof get(u, "version") === "string" ? (get(u, "version") as string) : null;
  const latest = typeof get(u, "latest") === "string" ? (get(u, "latest") as string) : null;
  const shownText = installed ? (version ?? t(get(u, "id") === "station" ? "core-views.software.dev" : "core-views.software.unknown")) : t("core-views.software.not_installed");
  const tips = [
    installed && get(u, "newer") !== true && get(u, "downgrade") !== true && latest !== null ? t("core-views.software.latest") : null,
    installed && latest === null && typeof get(u, "checkedAt") === "number" ? t("core-views.software.check_failed_retry") : null,
  ].filter((x): x is string => x !== null);
  const progress = get(u, "progress");
  return {
    ...u,
    shownText,
    tipText: tips.join(t("core-views.software.separator")),
    updatingText: typeof progress === "string" ? progress : t(installed ? "core-views.software.updating" : "core-views.software.installing"),
    failedText: t(installed ? "core-views.software.update_failed" : "core-views.software.install_failed"),
  };
}
