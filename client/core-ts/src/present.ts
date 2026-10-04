// What the clients show of a value, decided once (present.rs): times in words beside the times, and each topic's
// value through its shape (client/core-ts/src/shapes/schema.ts) as it goes out.
import { conform, type Ty } from "./conform.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import type { Topic } from "./protocol.ts";
import * as brand from "./brand.ts";
import * as decisions from "./decisions.ts";
import * as footprint from "./footprint.ts";
import * as jobsMod from "./jobs.ts";
import * as model from "./shapes/model.ts";
import * as providers from "./shapes/providers.ts";
import { arr as arrU, equal, get as getU, isObject, shaped, str, u64 } from "./util.ts";
import { SHAPES } from "./shapes/schema.ts";

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
  if (value !== null && typeof value === "object" && shaped.has(value)) return;
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
  profiles: "ProfilesView",
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
/// A topic's shape; undefined for one that goes out as it is.
export function shapeOf(topic: Topic): Ty | undefined {
  return SHAPED[topic.topic];
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
  if (topic.topic === "sessions") session(item as J);
  times(item, c);
  return item;
}

export function conformTopic(topic: Topic, value: unknown): { ok: unknown } | { error: string } {
  const ty = SHAPED[topic.topic];
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

export function watching(s: J): boolean {
  return isObject(get(s, "watch")) && waiting(s) !== null;
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

export function settled(row: J): boolean {
  const agents: J[] = arr(get(row, "agents")) ?? [];
  return agents.length > 0 && agents.every((a) => shownStatus(a) === "final") && !decisions.waits(row) && get(row, "unread") !== true;
}

/// Shown as one to archive (faded, below the rest of its day, archived with one tap): settled, not pinned, not kept by
/// the viewer; and where its station's archive review is on (`archiveReviewed`), only once the review recommended it.
export function archivable(row: J): boolean {
  if (!settled(row) || pinned(row) || get(row, "archiveReminderDismissed") === true) return false;
  return get(row, "archiveReviewed") !== true || get(row, "archiveRecommended") === true;
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

/// Where a chat stands, in words, and the message that is about.
export function rowStateLine(row: J): [string, number | null] | null {
  const thread = u64(get(row, "thread")) ?? null;
  const p = decisions.pending(row);
  const card: [string, number | null] | null = p
    ? [str(p.text) ?? decisions.line(str(get(p.message, "text")) ?? ""), u64(p.seq) ?? null]
    : null;
  const agents: J[] = arr(get(row, "agents")) ?? [];
  const textOf = (a: J): string | null => str(get(a, "statusText")) ?? null;
  const atWork = agents.some((a) => shownStatus(a) === "queued" || (shownStatus(a) === "running" && waiting(a) === null));
  if (!atWork) {
    const blocked = agents.find((a) => shownStatus(a) === "block");
    if (blocked) {
      const need = nonEmpty(get(get(blocked, "lastTurn"), "need")) !== null;
      if (card && !need) return card;
      const text = textOf(blocked);
      return text === null ? null : [text, stateAbout(blocked, thread) ?? card?.[1] ?? null];
    }
    const failed = agents.find((a) => ["failed", "unexpected", "aborted"].includes(shownStatus(a)));
    if (failed) {
      const text = textOf(failed);
      return text === null ? null : [text, stateAbout(failed, thread)];
    }
  }
  if (card) return card;
  if (atWork) return null;
  const waits = agents.find((a) => waiting(a) !== null);
  if (waits) {
    const text = textOf(waits);
    return text === null ? null : [text, stateAbout(waits, thread)];
  }
  if (!settled(row)) return null;
  const done = agents.find((a) => nonEmpty(get(get(a, "lastTurn"), "need")) !== null);
  const text = (done && textOf(done)) ?? t("core-views.present.done");
  let about = done ? stateAbout(done, thread) : null;
  if (about === null) {
    for (const a of agents) {
      about = stateAbout(a, thread);
      if (about !== null) break;
    }
  }
  return [text, about];
}

/// What a chat's agents are doing, for the 奏 page's 正在办.
export function workingLine(row: J): string | null {
  const agents: J[] = arr(get(row, "agents")) ?? [];
  const atWork = agents.some((a) => shownStatus(a) === "queued" || (shownStatus(a) === "running" && waiting(a) === null));
  if (atWork) {
    const text = str(get(get(row, "last"), "text")) ?? "";
    const last = format.cleanText(lines(text).map((l) => l.trim()).find((l) => l !== "") ?? "");
    return last === "" ? t("core-views.present.working") : t("core-views.present.working.last", { last });
  }
  for (const a of agents) {
    const w = waiting(a);
    if (w !== null) return str(w.text) ?? null;
  }
  return null;
}

export function rowStateText(row: J): string | null {
  return rowStateLine(row)?.[0] ?? null;
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

/// Slack's `<@U…>` mentions by name.
export function mentions(text: string, bots: [string, string][], members: J[]): string {
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
      const name = bots.find(([b]) => b === id)?.[1] ?? memberName(members, id) ?? id;
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
export function person(p: J, me: J, members: J[]): void {
  if (!isObject(p)) return;
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
  const picture = str(get(member, "picture")) || null;
  (p as J).shown = { name, display: mine ? t("core-views.present.you") : name, picture, mine };
}

/// A row's people as the clients show them.
export function rowPeople(row: J, me: J, slackUsers: string[], members: J[]): void {
  if (row.people === undefined && row.creator === undefined) return;
  const shown = (p: J): J => {
    const q = structuredClone(p);
    person(q, me, members);
    const id = str(get(q, "id"));
    if (id !== undefined && isViewer(me, id, slackUsers)) {
      q.shown.mine = true;
      q.shown.display = t("core-views.present.you");
    }
    return q;
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
  row.peopleText = text.join(" · ");
  if (creator) row.creator = creator;
  row.people = people;
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
  const pic = get(member, "picture");
  return { kind: "person", id: author, name, picture: typeof pic === "string" && pic !== "" ? pic : null, mine };
}

/// A session's summary with what the clients show of it.
export function session(s: J): void {
  if (!isObject(s)) return;
  const status = shownStatus(s);
  let [text, tone] = format.statusText(status);
  const turn = get(s, "lastTurn");
  const said = (k: string) => nonEmpty(get(turn, k));
  if (status === "block") {
    const need = said("need");
    if (need !== null) text = t("core-views.present.need_help", { need });
  } else if (status === "final") {
    const done = said("need");
    if (done !== null) text = t("core-views.present.done_with", { done });
  } else if (status === "failed") {
    text = t("core-views.present.failed", { why: format.failureText(said("detail") ?? "") });
  }
  if (waiting(s) !== null) {
    const what = nonEmpty(get(turn, "waitFor"));
    text = isObject(get(s, "watch")) ? t("core-views.present.watching") : what !== null ? t("core-views.present.waiting_for", { what }) : t("core-views.present.waiting");
  }
  const o = s as J;
  const strOf = (k: string): string | null => (typeof o[k] === "string" ? o[k] : null);
  const runtime = strOf("runtime") ?? "claude";
  const m = strOf("model");
  const first = strOf("firstText");
  const title = strOf("title") || (first !== null ? format.cleanText(first) : "") || t("core-views.no_messages");
  const b = markOf(s);
  o.statusText = text;
  o.tone = tone;
  o.mark = b;
  o.badgeText = b !== null ? badgeText(b) : null;
  o.titleText = title;
  const effort = strOf("effort");
  const process = strOf("process");
  o.agentText = format.agentLabel(m, effort);
  o.modelName = m ? model.name(m) : null;
  o.maker = maker(m);
  o.runtimeText = format.runtimeLabel(runtime);
  o.processText = process !== null ? format.processText(process) : null;
  o.efforts = format.efforts(runtime);
}

export function badgeText(b: string): string {
  return b === "block" ? t("core-views.present.badge.block") : b === "run" ? t("core-views.present.badge.run") : t("core-views.present.badge.failed");
}

export function maker(m: string | null | undefined): J {
  const found = m ? format.makerOf(m) : null;
  return found ? { id: found[0], name: found[1] } : null;
}

/// A connect with its state and how it runs in words.
export function connect(c: J): void {
  if (!isObject(c)) return;
  const o = c as J;
  const [text, presence] = format.connection(o.connection ?? null);
  const mode = str(o.mode) ?? "multi-session";
  const [modeText, modeShort] = format.modeText(mode, typeof o.requireMention === "boolean" ? o.requireMention : true);
  const bind = o.bind ?? null;
  const runtime = str(get(bind, "runtime")) ?? "claude";
  const label = format.agentLabel(str(get(bind, "model")), str(get(bind, "effort")));
  o.statusText = text;
  o.presence = presence;
  o.modeText = modeText;
  o.modeShort = modeShort;
  o.runtimeText = format.runtimeLabel(runtime);
  o.runText = `${format.runtimeLabel(runtime)} · ${label}`;
  const bm = str(get(bind, "model"));
  o.modelName = bm ? model.name(bm) : null;
}

/// A profile with its last check in words, its models' makers and series, what it can do, and its trouble.
export function profile(p: J): void {
  if (!isObject(p)) return;
  const o = p as J;
  if (get(o.access, "kind") === "env" && typeof get(o.access, "provider") === "string") o.access.kind = "api-provider";
  const blocked = get(o.quota, "state") === "blocked";
  const [text, tone] = blocked ? [t("core-views.present.profile.blocked"), "red"] : format.checkText(o.check ?? null);
  o.checkText = text;
  o.checkTone = tone;
  o.trouble = profileTrouble(o);
  const found: J[] = [...(arr(get(o.check, "models")) ?? []), ...(arr(o.modelsSaving) ?? [])];
  const strs = (list: J[]) => list.filter((m): m is string => typeof m === "string");
  const models = arr(o.models) ?? [];
  const makers: Record<string, J> = {};
  for (const m of strs([...models, ...found])) makers[m] = maker(m);
  const enabled = strs(models);
  const all = [...new Set([...strs(found), ...enabled])].sort();
  const modelsText = all.length === 0 ? t("core-views.present.profile.no_models") : t("core-views.present.profile.models", { enabled: enabled.length, n: all.length });
  const bySeries = series(all);
  const available: string[] = [];
  for (const m of [...strs(found), ...enabled]) if (!available.includes(m)) available.push(m);
  const names: Record<string, string> = {};
  for (const m of strs([...models, ...found, ...(o.model !== undefined ? [o.model] : [])])) if (m !== "") names[m] = model.name(m);
  const [usesList, provider] = uses(o);
  const pid = str(get(o.access, "provider"));
  const src = pid !== undefined ? providers.find(pid) : null;
  const decisionOnly = src !== null && !!src.decision && !src.chat && !src.responses && !src.anthropic;
  o.canAddModel = get(o.access, "kind") === "api-provider" && !decisionOnly;
  if (decisionOnly) {
    const f = get(o.check, "decision") ?? null;
    o.decisionOnly = true;
    o.decisionModels = get(f, "state") === "ready" ? (get(f, "models") ?? []) : [];
    o.decisionText = str(get(f, "detail")) || t("core-views.present.profile.decision_pending");
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
  o.available = available;
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
  const decision = (at !== null && at.chat !== null) || get(get(p.check, "decision"), "state") === "ready";
  const list = ([[runs("claude"), "claude"], [runs("codex"), "codex"], [decision, "decision"]] as [boolean, string][]).filter(([on]) => on).map(([, id]) => id);
  const provider: [string, string | null] | null = source && kind === "api-provider" ? [source.name, source.mark ?? null] : null;
  return [list, provider];
}

function usesText(list: string[]): string {
  return list.map((u) => (u === "claude" ? t("core-views.present.uses.claude") : u === "codex" ? t("core-views.present.uses.codex") : t("core-views.present.uses.decision"))).join(" · ");
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
    if (kind === "subscription" && !machine && state === "login") return issue(title, why, t("core-views.present.trouble.login_next"), "login", t("core-views.present.trouble.login_label"));
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
export function host(h: J): void {
  if (!isObject(h)) return;
  const o = h as J;
  const src = structuredClone(o);
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
  const meter = (label: string, short: string, percent: number, value: string, note: string | null) => {
    const p = format.round(Math.min(Math.max(percent, 0), 100));
    return { label, short, percent: p, level: p >= 90 ? "red" : p >= 75 ? "amber" : "ok", value, note };
  };
  const swap = n("memory", "swapUsedBytes");
  const cpuModel = str(src.cpuModel) || null;
  const busy = src.cpuBusy;
  const cpu =
    typeof busy === "number"
      ? meter("CPU", "CPU", busy * 100, `${format.round(busy * 100)}%`, [t("core-views.present.host.load", { load: format.fixed1(load * cpus) }), cpuModel].filter((x) => x !== null).join(" · "))
      : meter(t("core-views.present.host.cpu_load"), "CPU", load * 100, `${format.round(load * 100)}%`, cpuModel);
  o.facts = [
    str(src.hostname) ?? "",
    os,
    `${arch} · ${cores}`,
    days > 0 ? t("core-views.present.host.up_days_hours", { days, hours }) : t("core-views.present.host.up_hours", { hours }),
  ];
  const remaining = (bytes: number) => t("core-views.present.host.remaining", { size: format.fixed1(Math.max(bytes, 0) / GIB) });
  o.meters = [
    cpu,
    {
      ...meter(t("core-views.present.host.memory"), t("core-views.present.host.memory_short"), memTotal > 0 ? (memUsed / memTotal) * 100 : 0, `${format.gb1(memUsed)} / ${format.gb1(memTotal)}`, swap > 0 ? `swap ${format.gb1(swap)}` : null),
      remaining: remaining(memTotal - memUsed),
    },
    {
      ...meter(t("core-views.present.host.disk"), t("core-views.present.host.disk_short"), diskTotal > 0 ? ((diskTotal - diskFree) / diskTotal) * 100 : 0, t("core-views.present.host.disk_value", { free: format.gb1(diskFree), total: format.gb1(diskTotal) }), null),
      remaining: remaining(diskFree),
    },
  ];
  o.emberText = `${brand.name()} ${format.round(n("emberRssBytes") / 1024 ** 2)} MB`;
}

/// A station's connection as its card shows it (`StationNet`).
export function net(raw: J, relayName: (host: string) => string | null): J {
  if (!isObject(raw)) return null;
  const r = raw as J;
  const relayHost = str(r.relay) || null;
  const path =
    r.path === "direct"
      ? t("core-views.present.net.direct")
      : r.path === "relay"
        ? relayHost !== null
          ? (() => {
              const name = relayName(relayHost);
              return name !== null ? t("core-views.present.net.relay_named", { name }) : t("core-views.present.net.relay_host", { host: relayHost });
            })()
          : t("core-views.present.net.relay")
        : t("core-views.present.net.choosing");
  const samples: J[] = arr(r.samples) ?? [];
  const figure = (ms: number) => ({
    text: ms >= 1000 ? `${format.fixed1(ms / 1000)} s` : `${Math.max(format.round(ms), 1)} ms`,
    level: ms >= 1000 ? "red" : ms >= 300 ? "amber" : "ok",
  });
  const rtt = typeof r.rttMs === "number" ? figure(r.rttMs) : null;
  const named = (h: string) => relayName(h) ?? h;
  const via = r.path === "relay" ? (str(r.relay) ?? null) : null;
  const m = r.measured;
  const measured = isObject(m)
    ? {
        measuring: m.measuring === true,
        relays: (arr(m.relays) ?? []).flatMap((x: J) => {
          const h = str(get(x, "relay"));
          if (h === undefined) return [];
          const ms = get(x, "rttMs");
          return [{ name: named(h), rtt: typeof ms === "number" ? figure(ms) : null, current: via === h }];
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
  const loss =
    sent >= 20 && lost / sent >= 0.01
      ? (() => {
          const pct = (lost / sent) * 100;
          return { text: t("core-views.present.net.loss", { percent: format.fixed1(pct) }), level: pct >= 10 ? "red" : "amber" };
        })()
      : null;
  return {
    path,
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
  };
}

/// Posts worth concentrating on at the end of a chat.
export function focusMessage(message: J): boolean {
  if (get(message, "authorKind") !== "agent" || get(message, "system") === true) return false;
  const e = str(get(message, "ending")) ?? str(get(message, "declared"));
  if (e === "all_done" || e === "final") return true;
  const d = get(message, "decision");
  if (get(d, "resolved") === true || get(d, "dismissed") === true) return false;
  return ["need_human", "need_help", "need_decision", "block"].includes(e ?? "") || (d !== undefined && get(d, "resolved") === false);
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
      host(value);
      return value;
    case "footprint":
      return footprint.shown(value, c);
  }
  if (!ticks(topic)) return value;
  const v = value as J;
  switch (topic.topic) {
    case "sessions":
      for (const s of arr(v) ?? []) if (!shaped.has(s)) session(s);
      break;
    case "session":
      if (isObject(v) && v.session !== undefined) session(v.session);
      break;
    case "overview":
      if (isObject(v)) overview(v as J, c);
      break;
    case "chat":
      for (const a of arr(get(v, "agents")) ?? []) {
        const jobs = arr(get(a, "jobs"));
        if (jobs) for (let i = 0; i < jobs.length; i++) jobs[i] = jobsMod.shown(jobs[i], c);
      }
      break;
    case "decisions":
      decisions.today(v, c);
      break;
    case "job":
      value = jobsMod.shown(v, c);
      break;
    case "jobLog":
      jobsMod.log(v, c);
      break;
  }
  const own = DECORATORS[topic.topic];
  if (own) value = own(value, c);
  times(value, c);
  return value;
}

function overview(v: J, c: Clock): void {
  for (const row of arr(get(v.automaticDecisions, "recent")) ?? []) {
    if (typeof get(row, "at") === "number") row.stamp = stamp(row.at, c);
  }
  const processes = arr(v.processes);
  if (processes) {
    let mb = 0;
    for (const p of processes) if (typeof get(p, "rssMb") === "number") mb += p.rssMb;
    v.processesText =
      processes.length === 0
        ? t("core-views.present.processes.none")
        : t("core-views.present.processes.running", { n: processes.length, size: mb >= 1024 ? `${format.fixed1(mb / 1024)} GB` : `${mb} MB` });
  }
  if (isObject(v.footprint)) footprint.brief(v.footprint);
  for (const c of arr(v.connects) ?? []) connect(c);
  const station = (arr(v.updates) ?? []).find((u) => get(u, "id") === "station");
  if (station) station.name = "Station";
  const profiles = arr(v.profiles);
  if (profiles) {
    for (const p of profiles) profile(p);
    // A stable sort: those in trouble first.
    const sortedProfiles = [...profiles].sort((a, b) => Number(get(a, "trouble") === null) - Number(get(b, "trouble") === null));
    profiles.splice(0, profiles.length, ...sortedProfiles);
  }
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
  for (const l of arr(v.machineLogins) ?? []) {
    const plan = get(l, "plan");
    const email = str(get(l, "email"));
    l.offered =
      get(l, "loggedIn") === true &&
      typeof plan === "string" &&
      plan !== "" &&
      !(get(l, "runtime") !== undefined && taken.some((r) => equal(r, get(l, "runtime")))) &&
      !(email !== undefined && subscriptions.some(([runtime, bound]) => equal(get(l, "runtime"), runtime) && email.trim().toLowerCase() === bound));
  }
}
