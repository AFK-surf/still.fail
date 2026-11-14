// What the clients show of a value, decided once: times in words beside the times, and each topic's
// value through its shape (client/core-ts/src/shapes/schema.ts) as it goes out.
import { conform, type Ty } from "./conform.ts";
import * as format from "./format.ts";
import { current as language, t } from "./i18n.ts";
import { authorNameOf } from "./entries.ts";
import { STATION_PARTS, type Topic } from "./protocol.ts";
import * as brand from "./brand.ts";
import * as decisions from "./decisions.ts";
import * as drive from "./drive.ts";
import * as prefsMod from "./prefs.ts";
import * as jobsMod from "./jobs.ts";
import { permissionsShown } from "./permissions.ts";
import { copiesShown } from "./copies.ts";
import { elevationShown } from "./elevation.ts";
import * as model from "./shapes/model.ts";
import * as providers from "./shapes/providers.ts";
import { arr as arrU, equal, get as getU, isObject, shaped, str, u64 } from "./util.ts";
import { SHAPES, TOPIC_SHAPES } from "./shapes/schema.ts";
import * as clock from "./clock.ts";
import { untracked } from "./reactive.ts";
import { GROUPS as PROFILE_GROUPS, group as profileGroup, groupTitle as profileGroupTitle } from "./views/profiles.ts";
import { codexQuotaFailure } from "./codex-quota.ts";
import { linkShown, peekShown } from "./peek-pictures.ts";
import { isStationAuthor } from "./titles.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] | undefined => arrU(v);
const get = (v: unknown, k: string | number): J => getU(v, k);

/// The time a value is put together for: now, and the viewer's offset from UTC.
export type Clock = { now: number; offsetMin: number };

/// The clock moved on to `c` (a value is put together for it): what reads a grain that changed is made again.
export function clockAt(c: Clock): void {
  clock.minute.set(`${Math.floor(c.now / 60_000)}/${c.offsetMin}`);
  clock.day.set(`${format.localDay(c.now, c.offsetMin)}/${c.offsetMin}`);
}

const DAY_MS = 86_400_000;

// The grains of the clock a making read, recorded as it reads them (`grainsOf`), so that what takes a value kept from
// it reads them too (`taken`).
const MINUTE = 1;
const DAY = 2;
let grains = 0;

function byMinute(): void {
  grains |= MINUTE;
  clock.minute.get();
}

function byDay(): void {
  grains |= DAY;
  clock.day.get();
}

/// What `fn` gives, and the grains of the clock it read (`MINUTE`, `DAY`); what it read counts for a making around it too.
export function grainsOf<T>(fn: () => T): { value: T; grains: number } {
  const outer = grains;
  grains = 0;
  try {
    const value = fn();
    return { value, grains };
  } finally {
    grains |= outer;
  }
}

/// A value made for a clock and kept with what it was made of (`made`): the minute, offset, language and product name
/// its words hold for (`at`), and the grains of the clock its making read.
export type Made<T> = { value: T; at: string; grains: number };

/// What kept words hold for: the minute of the clock they were made for (the clock they were made with, not the
/// `clock.minute` signal, which moves only as a value is put together or a ticking topic is shown, so lags now by a
/// second at each minute and by hours while nothing is), its offset, and what they are said in.
function holdsFor(c: Clock): string {
  return `${Math.floor(c.now / 60_000)}/${c.offsetMin}/${language()}/${brand.name()}`;
}

/// What `make` makes of `of` for clock `c`, kept in `kept`: the one kept while it was made in the same minute (a value
/// made again in that minute could differ only by what a decorator says of `c.now` within it, which a computed kept
/// through the minute says as stale), else made again, untracked; reads nothing reactive. A station's whole overview
/// decorated took 2.6 ms in Hermes, made again by every computed that read it, and again as one let go was read anew
/// though its record had not changed (views.ts #stationShownOf). `taken` is what a computed takes of it.
export function made<K extends object, T>(kept: WeakMap<K, Made<T>>, of: K, c: Clock, make: () => T): Made<T> {
  const at = holdsFor(c);
  const was = kept.get(of);
  if (was !== undefined && was.at === at) return was;
  const m = untracked(() => grainsOf(make));
  const next = { value: m.value, at, grains: m.grains };
  kept.set(of, next);
  return next;
}

/// A kept value as the computed taking it has it: reading the grains of the clock its making read, so that it is made
/// again as its words change, as though it had made the value itself.
export function taken<T>(m: Made<T>): T {
  if (m.grains & MINUTE) byMinute();
  if (m.grains & DAY) byDay();
  return m.value;
}

/// A moment in words (Stamp).
export function stamp(ms: number, c: Clock): Record<string, unknown> {
  // (a day or more past, its words are its day's: 昨天 18:12, 11月3日 18:12; nearer, or to come, the minute's)
  if (c.now - ms >= DAY_MS) byDay();
  else byMinute();
  return {
    past: ms <= c.now,
    at: ms,
    ago: format.relativeTime(ms, c.now, c.offsetMin),
    full: format.absoluteTime(ms, c.offsetMin),
    until: format.timeUntil(ms, c.now),
  };
}

/// Times kept in seconds (still.fail cloud's) and in milliseconds (the station's).
const SECONDS = new Set(["created_at", "expires_at", "used_at", "revoked_at", "last_seen", "lastSeen"]);
const MILLIS = new Set(["createdAt", "lastActiveAt", "lastUsedAt", "checkedAt", "resetsAt"]);
/// The fields `times` says in words (`time`), each a moment.
export const TIME_KEYS: readonly string[] = [...SECONDS, ...MILLIS];

/// When a window that refills at `resetsAt` refills, in words (as `windows` says it), read by the minute: what a row
/// kept beside its part says of its windows as it goes out (views.ts windowShown).
export function refillsOf(resetsAt: number, c: Clock): string {
  byMinute();
  return format.refillsIn(resetsAt, c.now);
}

/// What a window with `used` percent of it used has left, and how full it is.
export function leftLevel(used: number): [number, string] {
  return [format.round(Math.max(100 - used, 0)), used >= 90 ? "red" : used >= 70 ? "amber" : "ok"];
}

function windows(list: Record<string, unknown>[], c: Clock): Record<string, unknown>[] {
  byMinute();
  const marks = format.windowMarks(list.map((w) => str(w.label) ?? ""));
  const out = list.map((w, i) => {
    const label = str(w.label) ?? "";
    const used = typeof w.usedPercent === "number" ? w.usedPercent : 0;
    const [mark, order] = marks[i]!;
    const [left, level] = leftLevel(used);
    return { ...w, label: format.windowName(label), mark, order, left, level, refills: typeof w.resetsAt === "number" ? format.refillsIn(w.resetsAt, c.now) : null };
  });
  // A stable sort, as Rust's sort_by_key.
  return out.sort((a, b) => (u64(a.order) ?? 1) - (u64(b.order) ?? 1));
}

/// When so many resets end, in words (none known: nothing).
function resetEnds(count: number, expiries: unknown, c: Clock): string[] {
  const expiry: string[] = [];
  if (count > 0 && Array.isArray(expiries)) {
    const ends = expiries.filter((at: unknown): at is number => typeof at === "number" && Number.isSafeInteger(at) && at > 0)
      .sort((a: number, b: number) => a - b).slice(0, count);
    if (ends.some((at: number) => at <= c.now)) expiry.push(t("core-views.present.resets_expired"));
    const future = ends.filter((at: number) => at > c.now).map((at: number) => format.preciseTimeUntil(at, c.now));
    if (future.length) expiry.push(t("core-views.present.resets_expire", { when: future.join(t("core-views.present.resets_separator")) }));
  }
  return expiry;
}

/// So many resets left, and when they end.
function resetsText(count: number, expiries: unknown, c: Clock): string {
  return [t("core-views.present.resets_left", { n: count }), ...resetEnds(count, expiries, c)].join(" · ");
}

/// Each kind's name, and what one gives back (a provider's own reset, `credit`, says nothing of it).
const RESET_KINDS: Record<string, [string, string | null]> = {
  session: ["core-views.present.reset.session", "core-views.present.reset.refills.session"],
  weekly: ["core-views.present.reset.weekly", "core-views.present.reset.refills.weekly"],
  full: ["core-views.present.reset.full", "core-views.present.reset.refills.full"],
  model: ["core-views.present.reset.model", "core-views.present.reset.refills.model"],
  credit: ["core-views.present.reset.credit", null],
};

/// A kind of reset as it is offered: its name, what one gives back, how many are left (`leftText`) and till when, and whether one
/// can be used now (else only once at a limit it refills). `id`, what the station is asked for (none: any).
/// What its words are made from (`model`, `expiries`) stays in it, as a window keeps its `resetsAt`: an overview is put
/// again where it goes out as another value than the one it was put in (a part of it, an account's row, one that shares
/// with the one before: store.ts), and a row put again says what it said. Without them a row lost when it ends the
/// second time it went out (2026-11-11).
function presentReset(r: Record<string, unknown>, c: Clock): Record<string, unknown> {
  const kind = Object.prototype.hasOwnProperty.call(RESET_KINDS, str(r.kind) ?? "") ? str(r.kind)! : "credit";
  const [name, gives] = RESET_KINDS[kind]!;
  const model = str(r.model) ?? "Fable";
  const left = u64(r.left) ?? 0;
  const usable = r.usable !== false;
  const refills = gives === null ? null : t(gives, { model });
  return {
    ...(typeof r.id === "string" ? { id: r.id } : {}),
    kind,
    ...(typeof r.model === "string" ? { model: r.model } : {}),
    left,
    ...(Array.isArray(r.expiries) ? { expiries: r.expiries.filter((at: unknown) => typeof at === "number" && Number.isSafeInteger(at)) } : {}),
    usable,
    title: t(name, { model }),
    // (how many on their own, where they are seen at once: the user, 2026-11-10)
    leftText: t("core-views.present.reset.left", { n: left }),
    text: [...resetEnds(left, r.expiries, c), ...(usable ? [] : [t("core-views.present.reset.needsLimit")])].join(" · "),
    ...(refills !== null ? { refills } : {}),
  };
}

/// Every time in a value, in words beside it: an object with some gets `time: { <field>: stamp }`; a quota's windows
/// are put as they are drawn. A new value where anything is put; a part with nothing put is the part as it was.
/// An object is copied only as something is first put in it, its keys looked up in sets: walking a station's 150 KB
/// overview took 1.5 ms in Hermes copying every object and looking each key up in two arrays, where most of its parts
/// have nothing put.
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
  const from = value as Record<string, unknown>;
  // (what is read is the copy once there is one: a part already put, `scoped` taken into the windows)
  let map: Record<string, unknown> | null = null;
  let stamps: Record<string, unknown> | null = null;
  for (const key of Object.keys(from)) {
    const v = (map ?? from)[key];
    if (typeof v === "number" && v > 0) {
      if (SECONDS.has(key)) (stamps ??= {})[key] = stamp(v * 1000, c);
      else if (MILLIS.has(key)) (stamps ??= {})[key] = stamp(v, c);
    } else if (key === "windows" && Array.isArray(v) && [v, (map ?? from).scoped].some((l) => Array.isArray(l) && l.some((w) => get(w, "usedPercent") !== undefined))) {
      // What its models have to themselves (`scoped`: Fable's week) drawn after the account's own. Where one model
      // is asked about (a chat's agent, an account to run a model on), views/models.ts quotaFor has left only its.
      map ??= { ...from };
      map[key] = windows([...v, ...(Array.isArray(map.scoped) ? map.scoped : [])] as Record<string, unknown>[], c);
      delete map.scoped;
    } else if (key !== "time" && !(key === "scoped" && Array.isArray((map ?? from).windows))) {
      const shown = times(v, c);
      if (shown !== v) (map ??= { ...from })[key] = shown;
    }
  }
  if ("windows" in from && "state" in from) {
    byMinute();
    const credits = (map ?? from).credits;
    if (isObject(credits)) {
      const text =
        credits.unlimited === true
          ? t("core-views.present.credits.unlimited")
          : typeof credits.balance === "string"
            ? t("core-views.present.credits.balance", { balance: format.decimal(credits.balance) })
            : credits.hasCredits === false
              ? t("core-views.present.credits.none")
              : t("core-views.present.credits.unknown");
      (map ??= { ...from }).creditsText = text;
    }
    const count = u64((map ?? from).resetCount);
    if (count !== undefined) {
      map ??= { ...from };
      map.resetText = resetsText(count, map.resetExpiries, c);
      // Each kind of reset it holds, as it is offered: a station from before kinds, or a provider with one kind (a
      // ChatGPT subscription's), all of them as one with no kind to ask for.
      const kinds = Array.isArray(map.resets) ? map.resets.filter(isObject) : count > 0 ? [{ kind: "credit", left: count, expiries: map.resetExpiries, usable: true }] : [];
      map.resets = kinds.map((r) => presentReset(r, c));
    }
  }
  if (stamps !== null) {
    map ??= { ...from };
    // (beside the times a value already says in words: a pull request's `updatedAt`, from its card)
    map.time = isObject(map.time) ? { ...map.time, ...stamps } : stamps;
  }
  return map ?? value;
}

/// What `times` puts in a value, for the test that holds it to how it was written before (present.test.ts).
export const timesParts = { windows, resetsText, presentReset };

const NO_TICK = new Set(["chats", "live", "thread", "letters", "history", "host", "net", "way", "stationNet", "status", "notices", "notify", "connection", "draft", "composer", "prefs", "doing", "slackTokens", "joinable", "memberships", "screenCard"]);

/// Whether a topic shows times in words, sent again each minute while shown.
export function ticks(topic: Topic): boolean {
  return !NO_TICK.has(topic.topic);
}

/// A topic's value through the shape the clients are generated from: what it does not declare is dropped, and a value
/// it does not allow is an error naming the field.
/// A topic's shape; undefined for one that goes out as it is.
export function shapeOf(topic: Topic): Ty | undefined {
  // One part of a station's overview: that field's own shape in Overview, null while there is none.
  if (topic.topic === "stationPart") {
    const ty = typeof topic.part === "string" && STATION_PARTS.includes(topic.part) ? fieldOf("Overview", topic.part) : undefined;
    return ty === undefined ? undefined : typeof ty === "object" && "opt" in ty ? ty : { opt: ty };
  }
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
  // (a list's station rows say their times in words themselves, views.ts: none put in to be dropped by their shape)
  if (!ticks(topic) || topic.topic === "stations") return item;
  return times(topic.topic === "sessions" ? session(item as J) : item, c);
}

export function conformTopic(topic: Topic, value: unknown): { ok: unknown } | { error: string } {
  const ty = TOPIC_SHAPES[topic.topic];
  if (ty === undefined) return { ok: value };
  return conform(ty, value);
}


// ── Sessions and rows ──

const nonEmpty = (v: unknown): string | null => (typeof v === "string" && v.trim() !== "" ? v.trim() : null);

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
  const turn = get(s, "lastTurn");
  // A turn not ended yet is running, whatever `process` says: the station reads its process states before its
  // database (read/pool.ts), so a turn that has just begun can come with the process still cold. One that ended
  // waiting on work it started is at work too, messages given it or not: the turn they begin takes over from it,
  // not a queue between the two (its activity in the chat went and came back as words were sent, 2026-11-08).
  const e = isObject(turn) ? ending(s) : null;
  if (isObject(turn) && ((turn.endedAt === null && (turn.outcome === null || turn.outcome === undefined)) || e === "waiting")) return "running";
  if ((u64(get(s, "pending")) ?? 0) > 0) return "queued";
  if (!isObject(turn)) return "idle";
  if (e === "all_done") return "final";
  if (e === "need_help") return "block";
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
/// Whether one of a row's agents keeps watch (rowWatch not null), its words not made: what the list of those watching
/// asks of a row it does not make whole.
export function watches(agents: J[]): boolean {
  return agents.some((a) => arr(get(get(a, "watch"), "names"))?.some((n) => typeof n === "string") === true);
}

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

/// What a finger's swipe asks before archiving a chat (only the swipe: its menu's and its key's 归档 ask only for a watch):
/// its watch's words while one of its agents keeps watch, else while one is at work or waits on work it started (an
/// archived one finishes its turn and waits on nothing after); and while someone else started it (`starter`: their
/// name; archiving takes it off the whole workspace's lists, not the viewer's alone; `hides`: the viewer can hide it
/// from their own list instead), said first, before what it is doing; null otherwise.
export function swipeAsk(agents: J[], starter: string | null = null, hides = false): string | null {
  const watch = rowWatch(agents);
  const state = watch !== null ? (watch.ask as string) : agents.some((a) => markOf(a) === "run") ? t("core-views.present.run_ask") : null;
  if (starter === null) return state;
  const others = t(hides ? "core-views.present.others_ask_hide" : "core-views.present.others_ask", { name: starter });
  return state === null ? others : t("core-views.present.asks_both", { first: others, then: state });
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

/// Offered to archive as the viewer's `archiveHint` says (prefs.ts archiveHintOf): faded.
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
/// check for done, the waiting arc, the watch's radar; a card waiting for the viewer (待处理 · …), its lead word (`text`)
/// in bold. `rest`: what follows the lead (for watching, the whole line: its words stay after the radar).
export type Lead = { kind: "need" | "done" | "wait" | "watch" | "decision"; text?: string; rest: string };

/// Where a chat stands, in words, and the message that is about; the line without its lead (what the dot before it does
/// not say); what leads it, if anything does. A line that asks for a decision (待处理 · …, 要你帮忙：…) is about none: the
/// line only says so, and the chat leads to what it asks (`ChatView.asks`). `cards` false: a card waiting is not said
/// (the chat's page, which shows the card itself).
export function rowStateLine(row: J, cards = true, alreadySaid: (agent: J) => boolean = () => false): [string, number | null, string, Lead | null] | null {
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
    const failures = agents.filter((a) => ["failed", "unexpected", "aborted"].includes(shownStatus(a)));
    if (failures.length > 0) {
      const unsaid = failures.find((a) => !alreadySaid(a));
      return unsaid ? said(unsaid, stateAbout(unsaid, thread)) : null;
    }
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

/// Whether a person is the viewer.
export function isViewer(me: J, person: string, slackUsers: string[]): boolean {
  const id = str(get(me, "id"));
  const email = str(get(me, "email"));
  return id === person || (email !== undefined && email.toLowerCase() === person.toLowerCase()) || slackUsers.includes(person);
}

/// A members list's members by their e-mail in lower case, the first of each, while the list is as long as it was
/// (a workspace's is shared and never changed in place). Looked up for every person of every row of a list: each a
/// scan of the list, both sides lowered at every step, was a third of making a row (13 ms of 42 for 420 rows in
/// Hermes, 2026-11-11).
const membersByEmail = new WeakMap<J[], { length: number; of: Map<string, J> }>();

/// The member whose e-mail is `email`, whatever its case: the first in the list.
function memberOf(members: J[], email: string): J {
  let kept = membersByEmail.get(members);
  if (kept === undefined || kept.length !== members.length) {
    const of = new Map<string, J>();
    for (const m of members) {
      const e = get(m, "email");
      if (typeof e !== "string") continue;
      const key = e.toLowerCase();
      if (!of.has(key)) of.set(key, m);
    }
    kept = { length: members.length, of };
    membersByEmail.set(members, kept);
  }
  return kept.of.get(email.toLowerCase());
}

export function memberName(members: J[], email: string): string | null {
  const m = memberOf(members, email);
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
  const member = memberOf(members, key);
  const mName = str(get(member, "name")) || null;
  const name = id === "local" ? t("core-views.present.local_page") : (mName ?? strOf("name") ?? email ?? id);
  const mine = isViewer(me, id, []) || (email !== null && isViewer(me, email, []));
  // A Slack person's own picture, as their Slack shows it; else their workspace account's.
  const picture = strOf("picture") ?? (str(get(member, "picture")) || null);
  return { ...p, shown: { name, display: mine ? t("core-views.present.you") : name, picture, mine } };
}

/// The workspace's members a row's people and its last line name (rowPeople, lastBy read their names and pictures): what
/// of the members a row is made of, the rest of them nothing of its.
export function rowMembers(row: J, members: J[]): J[] {
  const out: J[] = [];
  const add = (key: string | undefined) => {
    const m = key === undefined || key === "" ? undefined : memberOf(members, key);
    if (m !== undefined && !out.includes(m)) out.push(m);
  };
  // (as person() keys them: the email, else the id)
  const keyOf = (p: J) => {
    const email = str(get(p, "email"));
    return email !== undefined && email !== "" ? email : str(get(p, "id"));
  };
  if (isObject(get(row, "creator"))) add(keyOf(row.creator));
  for (const p of arr(get(row, "people")) ?? []) add(keyOf(p));
  const last = get(row, "last");
  const kind = str(get(last, "authorKind")) ?? "person";
  if (isObject(last) && kind !== "agent" && !isStationAuthor(kind)) add(str(last.author));
  return out;
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
    const identity = isObject(last.agentIdentity) ? last.agentIdentity : null;
    const runtime = str(get(identity, "runtime")) ?? str(get(last, "authorRuntime")) ?? get(agent, "runtime") ?? "claude";
    const otherRuntime = str(get(last, "authorRuntime")) !== undefined && get(agent, "runtime") !== undefined && runtime !== get(agent, "runtime");
    const m = (identity !== null ? str(get(identity, "model")) : otherRuntime ? str(get(last, "authorModel")) : str(get(agent, "model"))) ?? null;
    return {
      kind: "agent",
      name: m !== null ? model.name(m) : identity !== null ? format.agentLabel(null, str(get(identity, "effort"))) : otherRuntime ? format.runtimeLabel(runtime) : (saidName ?? "agent"),
      model: m,
      runtime,
      mine: false,
      state: agent ? markOf(agent) : null,
    };
  }
  if (isStationAuthor(kind)) return { kind: "station", name: brand.name(), mine: false };
  const mine = isViewer(me, author, slackUsers);
  const member = memberOf(members, author);
  const name = mine ? t("core-views.present.you") : (str(get(member, "name")) || saidName || author);
  // A Slack person's own picture, as their Slack shows it; else their workspace account's.
  const picture = str(last.authorPicture) || str(get(member, "picture")) || null;
  return { kind: "person", id: author, name, picture, mine };
}

/// Where a session stands, in words (`statusText`), what leads them (`statusLead`, said by a client as a mark of its own)
/// and what follows that (`statusRest`); and its colour (`tone`): what a row's state line reads of its agents
/// (rowStateLine), and a session's summary says (session).
function statusOf(s: J): { text: string; tone: J; lead: Lead["kind"] | null; rest: string } {
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
  return { text, tone, lead, rest };
}

/// An agent as a chat list's row's state line reads it (rowStateLine: its state in words, what leads them), its summary
/// as it is besides: what session() says of it and that alone reads.
export function agentStated(s: J): J {
  if (!isObject(s)) return s;
  const { text, lead, rest } = statusOf(s);
  return { ...s, statusText: text, ...(lead !== null ? { statusLead: lead, statusRest: rest } : {}) };
}

/// An agent as a chat list's row holds it (views.ts #listRow): what the row draws of it (RowAgent: `runtime`, `agentText`,
/// `maker`, as session() says them), and what the core reads of a list's row's agents besides: `key`, `model` (who said
/// a found message, lastBy: views.ts #foundMessages, views/search.ts).
export function listedAgent(s: J): J {
  if (!isObject(s)) return s;
  const o = s as J;
  const m = typeof o.model === "string" ? o.model : null;
  const out: J = {};
  if (o.key !== undefined) out.key = o.key;
  if (o.runtime !== undefined) out.runtime = o.runtime;
  if (o.model !== undefined) out.model = o.model;
  out.agentText = format.agentLabel(m, typeof o.effort === "string" ? o.effort : null);
  out.maker = maker(m);
  return out;
}

/// Whether the viewer said a row's last thing: lastBy's `mine`, all a chat list's row says of who said it (LastBy).
export function lastByMine(row: J, me: J, slackUsers: string[]): boolean | null {
  const last = get(row, "last");
  if (!isObject(last)) return null;
  const kind = str(last.authorKind) ?? "person";
  if (kind === "agent" || isStationAuthor(kind)) return false;
  return isViewer(me, str(last.author) ?? "", slackUsers);
}

/// A session's summary with what the clients show of it.
export function session(s: J): J {
  if (!isObject(s)) return s;
  const { text, tone, lead, rest } = statusOf(s);
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

/// Who made model `m`: as the model catalog says (`said`, the station's `modelMakers` entry for it), else by its name.
export function maker(m: string | null | undefined, said?: J): J {
  const lab = str(get(said, "maker"));
  const found = lab ? format.labMaker(lab, str(get(said, "makerName")) ?? null) : m ? format.makerOf(m) : null;
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
  const way = !single && feishu && get(o.feishu, "threads") === true ? words.threads : words.multi;
  return {
    ...o,
    statusText: text,
    presence,
    modeText,
    modeShort,
    modeWords: words,
    modeLabel: single ? words.single.label : way.label,
    modeSentence: single
      ? words.single.description + t(o.requireMention === false ? "web-pages.connect.everyMessageSentence" : "web-pages.connect.mentionOnlySentence")
      : way.description,
    placeText: str(o.team) ?? (feishu ? (str(get(o.feishu, "domain")) === "lark" ? "Lark" : t("web-pages.connect.feishu.name")) : kind === "comma" ? "Comma" : "Slack"),
    runtimeText: format.runtimeLabel(runtime),
    runText: `${format.runtimeLabel(runtime)} · ${label}`,
    modelName: bm ? model.name(bm) : null,
    ...(isObject(o.feishu) ? { feishu: feishuApp(o.feishu) } : {}),
  };
}

/// How a connect of `kind` says how its conversations become sessions (`ModeWords`): each way's name and what it means,
/// and what waiting for an @ does there, on and off; a Feishu connect's in its groups' words, with its thread mode.
export function modeWords(kind: string | null): J {
  const feishu = kind === "feishu";
  const way = (m: string) => ({
    label: t(feishu ? `web-main.mode.feishu.${m}.label` : `web-main.mode.${m}.label`),
    description: t(feishu ? `web-main.mode.feishu.${m}.description` : `web-main.mode.${m}.description`),
  });
  const k = (key: string) => (feishu ? `${key}.feishu` : key);
  return { multi: way("multi"), ...(feishu ? { threads: way("threads") } : {}), single: way("single"), mentionOn: t(k("web-pages.connect.mentionOn")), mentionOff: t(k("web-pages.connect.mentionOff")) };
}

/// The ways a connect could be switched to (`ModeChange`: every session in one, one each (a Feishu connect's by its
/// group or its thread), and one waiting for an @ or not), each with whether it changes anything, what it does to the connect's conversations in plain words, and its
/// button's words. `running`: its sessions running now.
export function modeChanges(c: J, running: number): J[] {
  const kind = str(get(c, "kind")) ?? null;
  const mode = str(get(c, "mode")) ?? "multi-session";
  const mention = get(c, "requireMention") !== false;
  const threads = mode === "multi-session" && get(get(c, "feishu"), "threads") === true;
  // a Feishu connect's groups in place of Slack's threads and channels
  const say = (key: string, o?: Record<string, unknown>) =>
    t(kind === "feishu" && ["toSingle", "toMulti", "threadsRestart", "mentionOnly", "noMention"].some((k) => key.endsWith(`.${k}`)) ? `${key}.feishu` : key, o);
  const effects = (next: string, nextMention: boolean, nextThreads: boolean): string[] => {
    const out: string[] = [];
    if (mode === "multi-session" && next === "multi-session") {
      if (nextThreads !== threads) out.push(t(nextThreads ? "web-pages.connect.effects.toThreads.feishu" : "web-pages.connect.effects.toGroups.feishu"));
    } else if (mode === "multi-session" && next === "single-session") {
      out.push(say("web-pages.connect.effects.toSingle"));
      out.push(say(str(get(c, "session")) ? "web-pages.connect.effects.resumeSingle" : "web-pages.connect.effects.newSingle"));
      if (!nextMention) out.push(say("web-pages.connect.effects.noMention"));
    } else if (mode === "single-session" && next === "multi-session") {
      out.push(nextThreads ? t("web-pages.connect.effects.singleToThreads.feishu") : say("web-pages.connect.effects.toMulti"));
      out.push(say("web-pages.connect.effects.threadsRestart"));
      out.push(say("web-pages.connect.effects.switchBack"));
    } else if (nextMention !== mention) {
      out.push(say(nextMention ? "web-pages.connect.effects.mentionOnly" : "web-pages.connect.effects.noMention"));
    }
    if (running > 0) out.push(say("web-pages.connect.effects.running", { n: running }));
    return out;
  };
  const ways = [["multi-session", true, false], ...(kind === "feishu" ? [["multi-session", true, true]] : []), ["single-session", true, false], ["single-session", false, false]] as [string, boolean, boolean][];
  return ways.map(([next, nextMention, nextThreads]) => {
    const changed = next !== mode || (next === "single-session" && nextMention !== mention) || nextThreads !== threads;
    const action = next === mode ? "web-pages.connect.confirmChange" : next === "single-session" ? "web-pages.connect.toSingle" : "web-pages.connect.toMulti";
    return { mode: next, requireMention: nextMention, ...(kind === "feishu" ? { threads: nextThreads } : {}), changed, effects: changed ? effects(next, nextMention, nextThreads) : [], action: t(action) };
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

/// An older station can still have Codex's raw RPC error saved. Give it the same treatment as a new station's answer.
function legacyCodexQuota(p: J): J {
  const q = get(p, "quota");
  const detail = get(q, "detail");
  if (get(p, "runtime") !== "codex" || !["unavailable", "blocked"].includes(get(q, "state")) || typeof detail !== "string" || !detail.startsWith("codex {")) return q;
  const failure = codexQuotaFailure(detail);
  const key = failure.kind === "other" ? "failed" : failure.kind;
  return {
    ...q,
    state: failure.kind === "blocked" ? "blocked" : "unavailable",
    detail: t(`core-views.present.trouble.codex_${key}`, { status: failure.status }),
  };
}

/// A profile with its last check in words, its models' makers and series, what it can do, and its trouble.
export function profile(p: J): J {
  if (!isObject(p)) return p;
  const o: J = { ...p };
  if (isObject(o.quota)) o.quota = legacyCodexQuota(o);
  if (get(o.access, "kind") === "env" && typeof get(o.access, "provider") === "string") o.access = { ...o.access, kind: "api-provider" };
  const blocked = get(o.quota, "state") === "blocked";
  const [text, tone] = o.enabled === false ? [t("core-views.present.profile.disabled"), "neutral"] : blocked ? [t("core-views.present.profile.blocked"), "red"] : format.checkText(o.check ?? null);
  o.checkText = text;
  o.checkTone = tone;
  o.trouble = o.enabled === false ? null : profileTrouble(o);
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
  // Only subscriptions have a plan. A check may report it, or an allowance (e.g. Grok's billing).
  const checkPlan = get(o.check, "state") === "ok" ? knownPlan(get(o.check, "plan")) : undefined;
  const canShowQuotaPlan = !isObject(o.check) || ["ok", "unknown"].includes(String(get(o.check, "state")));
  const quotaPlan = canShowQuotaPlan && get(o.quota, "state") !== "blocked" ? knownPlan(get(o.quota, "plan")) : undefined;
  const checkAt = get(o.check, "checkedAt");
  const quotaAt = get(o.quota, "checkedAt");
  const newerQuota = typeof checkAt === "number" && typeof quotaAt === "number" && quotaAt > checkAt;
  const plan = kind === "subscription" ? (newerQuota ? quotaPlan || checkPlan || "" : checkPlan || quotaPlan || "") : "";
  o.planText = planName(plan, str(o.runtime));
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
  const detail = withoutPart(withoutPart((detailOf ?? "").replace(/^(可用[，,]|Works,)\s*/, ""), named), kind === "subscription" ? (checkPlan ?? "") : "");
  // A machine's token-only check may have said `max` while its own login identifies that plan as Ultra.
  o.checkLine = o.enabled === false ? "" : isObject(o.check)
    ? withoutPart(detail, o.runtime === "claude" && checkPlan?.toLowerCase() === "ultra" ? "max" : "")
    : t("core-views.present.profile.never_checked");
  return o;
}

/// Opt-in Devin Fusion pairings (`fusion-<lead>-sidekick-<side>`), factored into sorted lead and sidekick tables.
export function buildFusion(raw: J): J | null {
  if (!isObject(raw)) return null;
  const rawSides = arr(raw.sides)?.filter((s): s is string => typeof s === "string" && s !== "") ?? [];
  const rawLeads = isObject(raw.leads) ? raw.leads : null;
  if (rawSides.length === 0 || !rawLeads) return null;
  const leadSides = new Map<string, Set<string>>();
  const sideSet = new Set<string>();
  for (const [rawLead, idxs] of Object.entries(rawLeads)) {
    const lead = model.devinFusionLead(rawLead);
    if (lead === "" || !Array.isArray(idxs)) continue;
    for (const idx of idxs) {
      const side = typeof idx === "number" ? rawSides[idx] : undefined;
      if (typeof side !== "string" || side === "") continue;
      let set = leadSides.get(lead);
      if (!set) {
        set = new Set();
        leadSides.set(lead, set);
      }
      set.add(side);
      sideSet.add(side);
    }
  }
  if (leadSides.size === 0 || sideSet.size === 0) return null;
  const sideIds = rawSides.filter((s, i) => sideSet.has(s) && rawSides.indexOf(s) === i);
  const sideIndex = new Map(sideIds.map((id, i) => [id, i]));
  const sides = sideIds.map((id) => ({ id, name: model.sidekickName(id), maker: maker(id) }));
  const leads = [...leadSides.entries()]
    .sort(([a], [b]) => model.compareOrder(a, b))
    .map(([id, set]) => ({
      id,
      name: model.name(id),
      maker: maker(id),
      sides: [...set].map((sid) => sideIndex.get(sid)!).sort((a, b) => a - b),
    }));
  return { leads, sides };
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
const SIGN_IN: Record<string, string> = { claude: "Claude", grok: "Grok", cursor: "Cursor", devin: "Devin", agy: "Google" };

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

/// Whether this core can read a station's host reading.
export function hostFits(h: J): boolean {
  return "ok" in conform("Host", host(h));
}

/// A machine as the clients show it.
export function host(h: J): J {
  if (!isObject(h)) return h;
  const src = h as J;
  const o: J = { ...src };
  // (a station from before the name said its memory as emberRssBytes)
  const rss = typeof src.stationRssBytes === "number" ? src.stationRssBytes : typeof src.emberRssBytes === "number" ? src.emberRssBytes : 0;
  delete o.emberRssBytes;
  o.stationRssBytes = rss;
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
  const meter = (label: string, short: string, percent: number, value: string, note: string | null, room: { remaining: string; big: string; unit: string; title: string; titleShort?: string; total: string; totalShort?: string }) => {
    const p = format.round(Math.min(Math.max(percent, 0), 100));
    return { label, short, percent: p, left: 100 - p, level: p >= 90 ? "red" : p >= 75 ? "amber" : "ok", value, note, ...room };
  };
  const swap = n("memory", "swapUsedBytes");
  const cpuModel = str(src.cpuModel) || null;
  const busy = src.cpuBusy;
  const cpuPercent = typeof busy === "number" ? busy * 100 : load * 100;
  const idle = format.round(100 - Math.min(Math.max(cpuPercent, 0), 100));
  const loadText = t("core-views.present.host.load", { load: format.fixed1(load * cpus) });
  const cpuRoom = { remaining: t("core-views.present.host.idle", { percent: idle }), big: String(idle), unit: "%", title: t("core-views.present.host.cpu_idle"), titleShort: t("core-views.present.host.cpu_idle_short"), total: loadText };
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
    remaining: remaining(memTotal - memUsed), big: big(memTotal - memUsed), unit: "GB", title: t("core-views.present.host.memory_left"), total: t("core-views.present.host.memory_total", { size: format.gb(memTotal) }), totalShort: t("core-views.present.host.total_short", { size: format.gb(memTotal) }),
  });
  const disk = meter(t("core-views.present.host.disk"), t("core-views.present.host.disk_short"), diskTotal > 0 ? ((diskTotal - diskFree) / diskTotal) * 100 : 0, t("core-views.present.host.disk_value", { free: format.gb1(diskFree), total: format.gb1(diskTotal) }), null, {
    remaining: remaining(diskFree), big: big(diskFree), unit: "GB", title: t("core-views.present.host.disk_left"), total: t("core-views.present.host.disk_total", { size: format.gb(diskTotal) }), totalShort: t("core-views.present.host.total_short", { size: format.gb(diskTotal) }),
  });
  // Each GPU is an ordinary resource dial: free capacity in its figure, used capacity in its cells.
  const gpus = (arr(src.gpus) ?? []).filter(isObject);
  o.gpus = gpus.map((gpu: J, i: number) => {
    const label = gpus.length === 1 ? "GPU" : `GPU ${i + 1}`;
    const name = str(gpu.name)?.trim() || "GPU";
    const busy = typeof gpu.busy === "number" && Number.isFinite(gpu.busy) && gpu.busy >= 0 && gpu.busy <= 1 ? gpu.busy : null;
    const total = typeof gpu.memoryTotalBytes === "number" && Number.isFinite(gpu.memoryTotalBytes) && gpu.memoryTotalBytes > 0 ? gpu.memoryTotalBytes : null;
    const used = typeof gpu.memoryUsedBytes === "number" && Number.isFinite(gpu.memoryUsedBytes) && gpu.memoryUsedBytes >= 0 && (total === null || gpu.memoryUsedBytes <= total) ? gpu.memoryUsedBytes : null;
    const size = (bytes: number) => {
      const g = Math.max(bytes, 0) / GIB;
      return Number.isInteger(g) ? String(g) : format.fixed1(g);
    };
    const cores = typeof gpu.cores === "number" && Number.isFinite(gpu.cores) && gpu.cores > 0 ? t("core-views.present.host.cores", { n: gpu.cores }) : "";
    const memoryNote = used !== null && total !== null ? t("core-views.present.host.gpu_memory_free", { free: size(total - used), total: size(total) })
      : used !== null ? t("core-views.present.host.gpu_memory_used", { used: size(used) })
      : total !== null ? t("core-views.present.host.gpu_memory_total", { total: size(total) }) : cores;
    const title = t("core-views.present.host.gpu_idle", { gpu: label });
    const titleShort = t("core-views.present.host.gpu_idle_short", { gpu: label });
    if (busy !== null) {
      const m = meter(label, label, busy * 100, "", null, { remaining: "", big: String(format.round(100 - busy * 100)), unit: "%", title, titleShort, total: memoryNote });
      return { big: m.big, unit: m.unit, left: m.left, level: m.level, title: m.title, titleShort: m.titleShort, total: m.total, model: name === "GPU" ? "" : name };
    }
    if (total !== null && used !== null) {
      const m = meter(label, label, used / total * 100, "", null, {
        remaining: "", big: big(total - used), unit: "GB", title: t("core-views.present.host.gpu_memory_left", { gpu: label }), titleShort: t("core-views.present.host.gpu_memory_left_short"),
        total: t("core-views.present.host.gpu_memory_all", { size: format.gb(total) }),
      });
      return { big: m.big, unit: m.unit, left: m.left, level: m.level, title: m.title, titleShort: m.titleShort, total: m.total, model: name === "GPU" ? "" : name };
    }
    return { big: "—", unit: "", left: 100, level: "ok", title, titleShort, total: memoryNote, model: name === "GPU" ? "" : name };
  });
  // What the machine is, the same line wherever it is named: its chip, its memory, its system.
  o.identity = [cpuModel, memTotal > 0 ? format.gb(memTotal) : null, os || null].filter((x) => x !== null).join(" · ");
  // The rest, a row each, only where the machine is looked at closely.
  const uptimeText = days > 0 ? t("core-views.present.host.uptime_days_hours", { days, hours }) : t("core-views.present.host.uptime_hours", { hours });
  o.details = [
    { label: t("core-views.present.host.hostname"), value: str(src.hostname) ?? "" },
    { label: t("core-views.present.host.chip"), value: [cpuModel, cpus > 0 ? cores : null, arch || null].filter((x) => x !== null).join(" · ") },
    { label: t("core-views.present.host.uptime"), value: uptimeText },
    { label: brand.name(), value: t("core-views.present.host.process", { size: `${format.round(rss / 1024 ** 2)} MB` }) },
  ].filter((d) => d.value !== "");
  o.meters = [cpu, memory, disk];
  o.usage = [memory, disk].map((m) => `${m.label} ${m.value}`).join(" · ");
  o.stationText = `${brand.name()} ${format.round(rss / 1024 ** 2)} MB`;
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
      value = jobsMod.log(v, c, topic.lines);
      break;
    case "slackApp":
      if (isObject(v)) value = { ...v, sections: slackSections() };
      break;
    // A web link's card: when a pull request or an issue last changed, in words (3 小时前); its pictures by their tokens,
    // their bytes asked beside (peek-pictures.ts).
    case "linkPreview": {
      const shown = linkShown(v);
      value = isObject(shown) && typeof shown.updatedAt === "number" && shown.updatedAt > 0 ? { ...shown, time: { updatedAt: stamp(shown.updatedAt, c) } } : shown;
      break;
    }
    // A file's card: when it was last written, in words; its picture by its token, as a link's.
    case "filePeek": {
      const shown = peekShown(v);
      value = isObject(shown) && typeof shown.mtime === "number" && shown.mtime > 0 ? { ...shown, time: { mtime: stamp(shown.mtime, c) } } : shown;
      break;
    }
    // One message's card: who said it, when, and its words as a chat's row has them. No such message: nothing.
    case "messagePeek":
      value = messagePeek(v, c);
      break;
  }
  const own = DECORATORS[topic.topic];
  if (own) value = own(value, c);
  return times(value, c);
}

function messagePeek(answer: J, c: Clock): J | null {
  const entry = arr(answer.entries)?.find((e: J) => e.kind === "message");
  if (entry === undefined) return null;
  const text = format.cleanText(format.plainText(str(entry.text) ?? ""));
  const at = entry.at;
  return { author: str(authorNameOf(entry.authorKind, entry.author, entry.authorName)) ?? "", text: text === "" ? t("core-views.file") : text, ...(typeof at === "number" && at > 0 ? { time: { at: stamp(at, c) } } : {}) };
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
  // Where its chats are copied (copies.ts); none said, none shown.
  const copies = copiesShown(v.copies, c);
  if (copies === undefined) delete v.copies;
  else v.copies = copies;
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
  const connects = arr(v.connects);
  if (connects) v.connects = connects.map(connect);
  const updates = arr(v.updates);
  if (updates) v.updates = updates.map((u) => software(get(u, "id") === "station" ? { ...u, name: "Station" } : u));
  const listed = arr(v.profiles);
  // A stable sort: by kind of account (a station's list is a section each), those in trouble first in each.
  const kindOf = (p: J) => PROFILE_GROUPS.indexOf(get(p, "group"));
  const profiles = listed?.map(profile).sort((a, b) => kindOf(a) - kindOf(b) || Number(get(a, "trouble") === null) - Number(get(b, "trouble") === null));
  if (profiles) v.profiles = profiles;
  const logins = arr(v.machineLogins);
  if (logins) v.machineLogins = loginsOffered(logins, profiles ?? []);
  return v;
}

/// A station's own logins (an overview's `machineLogins`), each with whether it is offered as a profile (signed in, on a
/// plan, its runtime not run by the machine's own profile already, its account not a subscription one of `profiles`
/// is) and its plan in words: an overview's as it is decorated, and the accounts' list's beside its kept rows (views.ts
/// #offeredOf), which hold of each profile what this reads.
export function loginsOffered(logins: J[], profiles: J[]): J[] {
  const subscriptions: [J, string][] = [];
  const taken: J[] = [];
  for (const p of profiles) {
    if (get(get(p, "access"), "kind") === "subscription") {
      const runtime = get(p, "runtime");
      const email = str(get(p, "email"));
      if (runtime !== undefined && email !== undefined && email.trim() !== "") subscriptions.push([runtime, email.trim().toLowerCase()]);
    }
    if (get(p, "machine") === true && get(p, "runtime") !== undefined) taken.push(get(p, "runtime"));
  }
  {
    return logins.map((l) => {
      const plan = knownPlan(get(l, "plan"));
      const email = str(get(l, "email"));
      const offered =
        get(l, "loggedIn") === true &&
        typeof plan === "string" &&
        plan !== "" &&
        !(get(l, "runtime") !== undefined && taken.some((r) => equal(r, get(l, "runtime")))) &&
        !(email !== undefined && subscriptions.some(([runtime, bound]) => equal(get(l, "runtime"), runtime) && email.trim().toLowerCase() === bound));
      const planText = typeof plan === "string" ? planName(plan, str(get(l, "runtime"))) : "";
      return isObject(l) ? { ...l, offered, planText } : l;
    });
  }
}

/// A subscription's plan as its vendor names it. Codex's `prolite`, `pro` and `promax` distinguish the three ChatGPT
/// Pro tiers; the same word `pro` for another runtime need not mean the ChatGPT plan. The numbers name the plans,
/// rather than stating what this person was billed.
const PLAN_NAMES: Record<string, string> = { prolite: "Pro Lite", promax: "Pro Max" };
const CODEX_PLAN_NAMES: Record<string, string> = { prolite: "Pro 100", pro: "Pro 200", promax: "Pro 500" };

/// An unknown tier is a provider's sentinel, not the name of a plan.
function knownPlan(value: unknown): string | undefined {
  const plan = str(value)?.trim();
  return plan && plan.toLowerCase() !== "unknown" ? plan : undefined;
}

function planName(plan: string, runtime?: string): string {
  const name = plan.toLowerCase();
  return (runtime === "codex" ? CODEX_PLAN_NAMES[name] : undefined) ?? PLAN_NAMES[name] ?? plan.split(/[_\s]+/).filter((w) => w !== "").map((w) => `${w[0]!.toUpperCase()}${w.slice(1)}`).join(" ");
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
    // While its download is measured, how much of it is in, in words (正在下载 1.5.6：60/88 MB).
    const step = percent !== undefined ? str(v.progress) : null;
    return { runtime, state: "installing", title: t("core-views.install.installing", { name }), ...(step ? { note: step } : {}), ...(percent !== undefined ? { percent } : {}) };
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

/// A piece of software as it is said: its version as shown, what is said of it on
/// hover (up to date, or that the last check failed), and while it updates or once that failed, in words.
export function software(u: J): J {
  const installed = get(u, "installed") === true;
  const version = typeof get(u, "version") === "string" ? (get(u, "version") as string) : null;
  const latest = typeof get(u, "latest") === "string" ? (get(u, "latest") as string) : null;
  const shownText = installed ? (version ?? t(get(u, "id") === "station" ? "core-views.software.dev" : "core-views.software.unknown")) : t("core-views.software.not_installed");
  const tips = [
    installed && get(u, "repairable") !== true && get(u, "newer") !== true && get(u, "downgrade") !== true && latest !== null ? t("core-views.software.latest") : null,
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
