// What each workspace has waiting for its person, for where workspaces are switched: of the chats
// they take part in, those that want them and those with something unread; the chat last open in it. Only how many
// and how urgent goes past a workspace.
import { decodeComponent } from "../accounts.ts";
import * as decisions from "../decisions.ts";
import { tr, current, type Lang } from "../i18n.ts";
import { badgeKindsOf, failsGoneOf, type BadgeKinds } from "../prefs.ts";
import * as present from "../present.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
import { work } from "../work.ts";
import { PENDING_PREFIX, type Local } from "./local.ts";
import type { Views } from "./views.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// The workspaces' ids, as the accounts' `/v1/me` list them.
export function workspaceIds(workspaces: J): string[] {
  return arr(workspaces)
    .flatMap((a) => arr(get(a, "workspaces")))
    .flatMap((w) => (typeof get(w, "id") === "string" ? [w.id as string] : []));
}

/// What a chat's row asks of its person: alert when an agent of a chat they started (or, a row that does not say who
/// started it, take part in) went wrong, done when it is unread with nobody at work. A row waiting for someone is
/// counted by whom it waits for (`decisions.forViewer`), not here: an agent needing whoever started a chat of someone
/// else's waits for them.
export function rowTone(row: J, me: J = null): string | null {
  if (get(row, "mine") !== true) return null;
  const state = present.rowState(arr(get(row, "agents")));
  if (state === "failed") return startedBy(row, me) ? "alert" : null;
  return get(row, "unread") === true && state !== "run" && state !== "block" ? "done" : null;
}

/// Whether the viewer started a chat (a row that does not say: whether they take part in it).
function startedBy(row: J, me: J): boolean {
  const creator = get(row, "creator");
  const who = typeof creator === "string" ? creator : (str(get(creator, "email")) ?? str(get(creator, "id")));
  return me === null || who === null ? get(row, "mine") === true : present.isViewer(me, who, []);
}

/// A failure of a chat's (its row's tone alert), as 待处理 names it to be let go (`failsGone`): the chat, and when its
/// agents that went wrong last ended. The same chat failing again is another.
export function failureOf(station: string, row: J): string {
  let at = 0;
  for (const a of arr(get(row, "agents"))) {
    if (present.markOf(a) !== "failed") continue;
    const turn = get(a, "lastTurn");
    const when = [get(turn, "endedAt"), get(turn, "startedAt"), get(a, "lastActiveAt")].find((n) => typeof n === "number");
    if (typeof when === "number" && when > at) at = when;
  }
  const thread = get(row, "thread");
  return `${station}/${str(get(row, "id")) ?? `thread:${typeof thread === "number" ? thread : ""}`}@${at}`;
}

/// A row's state line as its list says it (its agents presented as the chats view has them).
/// Its row's state line, and the same without its lead (待处理 · , 需要你处理：, 出错：): what the dot before it does not say.
function stateText(row: J): [string, string] {
  const shown = isObject(row) && Array.isArray(row.agents) ? { ...row, agents: row.agents.map((a: J) => present.session(a)) } : row;
  const line = present.rowStateLine(shown);
  return line === null ? ["", ""] : [line[0], line[2]];
}

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// What the badge counts (the prefs' `badgeKinds`, or as their `badge` says), of what came since the person last looked
/// (`c`; `said`: of its unread, those someone else said last): the cards waiting for them, the chats of theirs that went
/// wrong, the unread an agent said last, the unread someone else did. A chat looked at is not counted until it wants
/// them anew.
export function badgeOf(prefs: J, c: Counts, said = 0): number {
  const k = badgeKindsOf(prefs);
  if (!k.on) return 0;
  return (k.wait ? c.wait : 0) + (k.failed ? c.alert : 0) + (k.done ? c.unread - said : 0) + (k.message ? said : 0);
}

/// Whether the last thing said in a row is someone else's (not an agent's or the station's): what the badge's `message`
/// counts of the unread.
function saidByPerson(row: J): boolean {
  const last = get(row, "last");
  return isObject(last) && (str(last.authorKind) ?? "person") === "person";
}

/// The chat last open in a workspace, from the prefs.
export function lastChat(prefs: J, workspace: string): J {
  const open = get(get(prefs, "openChat"), workspace);
  if (isObject(open)) return structuredClone(open);
  const path = get(get(prefs, "lastChat"), workspace);
  if (typeof path !== "string") return null;
  const prefix = `/w/${workspace}/s/`;
  if (!path.startsWith(prefix)) return null;
  const rest = path.slice(prefix.length);
  const at = rest.indexOf("/chats/");
  if (at < 0) return null;
  const station = rest.slice(0, at);
  const key = decodeComponent(rest.slice(at + 7).split(/[?#/]/)[0]);
  return station !== "" && key !== "" && !key.startsWith(PENDING_PREFIX) ? { station: `${workspace}/${station}`, key } : null;
}

export class Counts {
  alert: number;
  wait: number;
  unread: number;
  constructor(alert = 0, wait = 0, unread = 0) {
    this.alert = alert;
    this.wait = wait;
    this.unread = unread;
  }
  tone(): string | null {
    return this.alert > 0 ? "alert" : this.wait > 0 ? "wait" : this.unread > 0 ? "done" : null;
  }
  label(): string {
    return this.labelIn(current());
  }
  labelIn(lang: Lang): string {
    const parts: string[] = [];
    if (this.alert > 0) parts.push(tr(lang, "core-views.marks.alert", { n: this.alert }));
    if (this.wait > 0) parts.push(tr(lang, "core-views.marks.wait", { n: this.wait }));
    if (this.unread > 0) parts.push(tr(lang, "core-views.marks.unread", { n: this.unread }));
    return parts.join(" · ");
  }
}


const okOf = (v: Value | undefined): J => (v !== undefined && "ok" in v ? v.ok : undefined);

/// What of the prefs the workspaces' marks are put together with (`marks`): what the badge counts, and the language
/// their words are in (a language chosen is written to the prefs: what was said in the last is made again). Read alone
/// (Views `prefsPart`), so that a pref written at every switch of workspace (`workspace`) makes none of it again.
export function marksPrefs(v: Value | undefined): { kinds: BadgeKinds; lang: unknown } {
  const p = okOf(v);
  return { kinds: badgeKindsOf(p), lang: get(p, "lang") };
}

/// What of the prefs one workspace's mark is made with (`workspaceMark`), as a prefs record of that alone: what the
/// badge counts, the language, its failures let go and the chat last open in it. Made once for each workspace and kept
/// (Views `markOf`): the store keeps a part read by the function that picks it.
export function prefsOf(workspace: string): (v: Value | undefined) => J {
  return (v) => {
    const p = okOf(v);
    if (!isObject(p)) return null;
    // (another workspace's let go or opened is nothing of it, nor whether any is)
    const one = (field: string) => {
      const v = isObject(p[field]) ? p[field][workspace] : undefined;
      return v === undefined ? undefined : { [workspace]: v };
    };
    return { badge: p.badge, badgeKinds: p.badgeKinds, lang: p.lang, failsGone: one("failsGone"), openChat: one("openChat"), lastChat: one("lastChat") };
  };
}

/// What a marked row says of itself to its viewer, made of the row alone: whether it waits for them (and what it asks),
/// its tone and failure as its own, the lists it is in, whether someone else said its last, its state line. Kept with the row (one is the same frozen object while its record is unchanged: db/account.ts
/// `#cached`), made again for a row that changed, another viewer or another language: every row of every workspace
/// made again at every switch of workspace was most of what that took (13-20 ms of 14-22 in Hermes, 2 workspaces of
/// 420 chats, 2026-11-11). What it comes to with what is kept here and not in the row (being archived, answered from
/// here, a failure let go, what the badge counts) is not kept.
type RowMade = {
  station: string;
  id: unknown;
  email: unknown;
  lang: Lang;
  asks: boolean;
  seq: unknown;
  tone: string | null;
  failure: string | null;
  watch: boolean;
  block: boolean;
  byPerson: boolean;
  text: [string, string];
};
const rowsMade = new WeakMap<object, RowMade>();

function rowMade(station: string, row: J, me: J): RowMade {
  const lang = current();
  const id = get(me, "id");
  const email = get(me, "email");
  const kept = isObject(row) ? rowsMade.get(row) : undefined;
  if (kept !== undefined && kept.station === station && kept.id === id && kept.email === email && kept.lang === lang) return kept;
  work.marked++;
  const d = decisions.forViewer(row, me);
  const tone = rowTone(row, me);
  const agents = arr(get(row, "agents"));
  const made: RowMade = {
    station,
    id,
    email,
    lang,
    asks: d !== null,
    seq: get(d, "seq"),
    tone,
    failure: tone === "alert" ? failureOf(station, row) : null,
    watch: present.rowWatch(agents) !== null,
    block: get(row, "mine") === true && present.rowState(agents) === "block",
    byPerson: saidByPerson(row),
    text: stateText(row),
  };
  if (isObject(row)) rowsMade.set(row, made);
  return made;
}

/// One workspace's mark (`marks`'s `workspaces[id]`), made of its own stations' rows and `prefs`, what of the prefs it
/// reads (`prefsOf`). Views keeps it for the workspace (`markOf`): which workspace is shown is nothing of it.
export function workspaceMark(views: Views, local: Local, id: string, prefs: J): J {
  work.workspaceMarks++;
  const kinds = badgeKindsOf(prefs);
  let name = id;
  let look: { workspaceEmoji?: string; workspaceIcon?: string } = {};
  for (const a of arr(views.ok({ topic: "workspaces" }))) {
    for (const w of arr(get(a, "workspaces"))) {
      if (get(w, "id") !== id) continue;
      name = str(get(w, "name")) ?? id;
      look = { ...(str(get(w, "emoji")) ? { workspaceEmoji: w.emoji } : {}), ...(str(get(w, "icon")) ? { workspaceIcon: w.icon } : {}) };
    }
  }
  const counts = new Counts();
  // The same of the lists the rail leads to besides the whole one (我参与的, 监控中).
  const mine = new Counts();
  const watching = new Counts();
  // Of those, the ones not looked at since they came to want them: what the badge counts.
  const fresh = new Counts();
  let said = 0;
  let elsewhere = 0;
  const items: J[] = [];
  const me = views.me(id);
  const gone = failsGoneOf(prefs, id);
  // Only the rows that ask something or are unread count (db/account.ts: found by their columns, not loaded whole).
  // (their addresses and names alone: not each one's link, which comes and goes: Views `stationsNamed`)
  const stations = views.stationsNamed(id);
  const nameOf = new Map(stations.map((s) => [s.address, s.name]));
  for (const [address, row] of views.marked(stations.map((s) => s.address))) {
    if (local.beingArchived(address, row)) continue;
    const made = rowMade(address, row, me);
    const thread = get(row, "thread");
    const waits = made.asks && !(typeof thread === "number" && local.answered(address, thread, typeof made.seq === "number" ? made.seq : 0));
    const asked = waits ? "wait" : made.tone;
    // a failure let go (忽略) wants them no more, here or in 待处理, until the chat fails again
    const failure = asked === "alert" ? made.failure : null;
    const tone = failure !== null && gone.has(failure) ? null : asked;
    const seen = get(row, "unread") !== true;
    const lists = [counts];
    if (get(row, "mine") === true) lists.push(mine);
    if (made.watch) lists.push(watching);
    for (const c of lists) {
      if (tone === "alert") c.alert++;
      else if (tone === "wait") c.wait++;
      else if (tone === "done") c.unread++;
    }
    if (!seen && (tone === "alert" || tone === "wait" || tone === "done")) fresh[tone === "done" ? "unread" : tone]++;
    const byPerson = !seen && tone === "done" && made.byPerson;
    if (byPerson) said++;
    else if (made.block) elsewhere++;
    // 待处理 (`items`), of what the badge counts: its failures until they run again, are archived or let go, read or
    // not (a chat read is still broken: pengxiao, 2026-10-28), as the workspace's mark counts them; its cards that
    // came to want them and were not looked at since (one looked at: its row still says it); its unread the badge
    // counts, so every number on it can be found there.
    if ((tone === "alert" && kinds.failed) || (!seen && tone === "wait" && kinds.wait) || (!seen && tone === "done" && (byPerson ? kinds.message : kinds.done))) {
      const [text, what] = made.text;
      const item: J = {
        kind: tone,
        workspace: id,
        workspaceName: name,
        ...look,
        station: address,
        stationName: nameOf.get(address) ?? address,
        session: get(row, "id") ?? null,
        thread: typeof thread === "number" ? thread : null,
        title: str(get(row, "title")) ?? "",
        text,
        what,
        at: typeof get(row, "lastActiveAt") === "number" ? row.lastActiveAt : 0,
      };
      if (waits && typeof made.seq === "number") item.seq = made.seq;
      else if (tone === "done" && typeof get(get(row, "last"), "seq") === "number") item.seq = get(row, "last").seq;
      if (tone === "alert" && failure !== null) item.failure = failure;
      items.push(item);
    }
  }
  // Most urgent first, the latest first within.
  const urgency = (kind: string) => ["alert", "wait", "done"].indexOf(kind);
  items.sort((a, b) => urgency(a.kind) - urgency(b.kind) || b.at - a.at);
  const badge = badgeOf(prefs, fresh, said);
  const mark: J = { alert: counts.alert, unread: counts.unread, badge, items };
  if (counts.wait > 0) mark.wait = counts.wait;
  if (elsewhere > 0) mark.elsewhere = elsewhere;
  const tone = counts.tone();
  if (tone !== null) {
    mark.tone = tone;
    mark.label = counts.label();
  }
  if (mine.tone() !== null) mark.mineTone = mine.tone();
  if (watching.tone() !== null) mark.watchingTone = watching.tone();
  const chat = lastChat(prefs, id);
  if (chat !== null) mark.chat = chat;
  return mark;
}

/// A workspace's mark with what the others have waiting (`others`, `othersLabel`: their most urgent and in words, as
/// the place where workspaces are switched shows them while it is the one shown), the same object while they and the
/// mark are as they were.
const withOthers = new WeakMap<object, { tone: string | null; label: string | null; out: J }>();

/// Every workspace's mark (`workspaceMark`, each kept for its workspace), what the app's badge comes to, and in each
/// what the others have waiting. One value whichever workspace is shown, so the app holds it across a switch of
/// workspace: asked of the one shown (`workspace`), a new subscription at every switch went out whole (24.6 KB of the
/// real-size two, shaped again, 2.4 ms in Hermes on a Mac Studio before 大屏's list could be made) for the one field
/// that differed.
export function marks(views: Views): Value {
  const { kinds } = views.prefsPart(marksPrefs);
  const ids = workspaceIds(views.ok({ topic: "workspaces" }));
  const made = ids.map((id) => [id, views.markOf(id)] as [string, J]);
  const lang = current();
  const all: Record<string, J> = {};
  let total = 0;
  for (const [id, mark] of made) {
    const others = new Counts();
    for (const [other, m] of made) {
      if (other === id) continue;
      others.alert += m.alert;
      others.wait += m.wait ?? 0;
      others.unread += m.unread;
    }
    const tone = others.tone();
    const label = tone === null ? null : tr(lang, "core-views.marks.others", { label: others.labelIn(lang) });
    const was = withOthers.get(mark);
    let out: J = mark;
    if (was !== undefined && was.tone === tone && was.label === label) out = was.out;
    else if (tone !== null) {
      out = { ...mark, others: tone, othersLabel: label };
      withOthers.set(mark, { tone, label, out });
    }
    // (a workspace turned off on the notifications page adds nothing to the app's badge; its own mark stays)
    if (views.heard(id)) total += mark.badge;
    all[id] = out;
  }
  return { ok: { workspaces: all, badge: total, badgeKinds: kinds } };
}
