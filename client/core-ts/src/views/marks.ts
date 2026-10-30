// What each workspace has waiting for its person, for where workspaces are switched (views/marks.rs): of the chats
// they take part in, those that want them and those with something unread; the chat last open in it. Only how many
// and how urgent goes past a workspace.
import { decodeComponent } from "../accounts.ts";
import * as decisions from "../decisions.ts";
import { tr, current, type Lang } from "../i18n.ts";
import { badgeKindsOf, failsGoneOf } from "../prefs.ts";
import * as present from "../present.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
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
/// Its row's state line, and the same without its lead (奏 · , 需要你处理：, 出错：): what the dot before it does not say.
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

export function marks(views: Views, local: Local, currentWorkspace: string | null): Value {
  const prefs = views.ok({ topic: "prefs" }) ?? null;
  const kinds = badgeKindsOf(prefs);
  const all: Record<string, J> = {};
  const others = new Counts();
  let total = 0;
  const names = new Map<string, string>();
  const marks = new Map<string, { workspaceEmoji?: string; workspaceIcon?: string }>();
  for (const a of arr(views.ok({ topic: "workspaces" }))) {
    for (const w of arr(get(a, "workspaces"))) {
      if (typeof get(w, "id") !== "string") continue;
      names.set(w.id, str(get(w, "name")) ?? w.id);
      marks.set(w.id, { ...(str(get(w, "emoji")) ? { workspaceEmoji: w.emoji } : {}), ...(str(get(w, "icon")) ? { workspaceIcon: w.icon } : {}) });
    }
  }
  for (const id of workspaceIds(views.ok({ topic: "workspaces" }))) {
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
    const stations = views.stations(id) ?? [];
    const nameOf = new Map(stations.map((s) => [s.address, s.name]));
    for (const [address, row] of views.marked(stations.map((s) => s.address))) {
      if (local.beingArchived(address, row)) continue;
      const d = decisions.forViewer(row, me);
      const thread = get(row, "thread");
      const waits = d !== null && !(typeof thread === "number" && local.answered(address, thread, typeof d.seq === "number" ? d.seq : 0));
      const asked = waits ? "wait" : rowTone(row, me);
      // a failure let go (忽略) wants them no more, here or in 待处理, until the chat fails again
      const failure = asked === "alert" ? failureOf(address, row) : null;
      const tone = failure !== null && gone.has(failure) ? null : asked;
      const seen = get(row, "unread") !== true;
      const lists = [counts];
      if (get(row, "mine") === true) lists.push(mine);
      if (present.rowWatch(arr(get(row, "agents"))) !== null) lists.push(watching);
      for (const c of lists) {
        if (tone === "alert") c.alert++;
        else if (tone === "wait") c.wait++;
        else if (tone === "done") c.unread++;
      }
      if (!seen && (tone === "alert" || tone === "wait" || tone === "done")) fresh[tone === "done" ? "unread" : tone]++;
      if (!seen && tone === "done" && saidByPerson(row)) said++;
      else if (get(row, "mine") === true && present.rowState(arr(get(row, "agents"))) === "block") elsewhere++;
      // 待处理 (`items`), of what the badge counts: its failures until they run again, are archived or let go, read or
      // not (a chat read is still broken: pengxiao, 2026-10-28), as the workspace's mark counts them; its cards that
      // came to want them and were not looked at since (one looked at: its row still says it).
      if ((tone === "alert" && kinds.failed) || (!seen && tone === "wait" && kinds.wait)) {
        const [text, what] = stateText(row);
        const item: J = {
          kind: tone,
          workspace: id,
          workspaceName: names.get(id) ?? id,
          ...marks.get(id),
          station: address,
          stationName: nameOf.get(address) ?? address,
          session: get(row, "id") ?? null,
          thread: typeof thread === "number" ? thread : null,
          title: str(get(row, "title")) ?? "",
          text,
          what,
          at: typeof get(row, "lastActiveAt") === "number" ? row.lastActiveAt : 0,
        };
        if (waits && typeof d.seq === "number") item.seq = d.seq;
        if (tone === "alert" && failure !== null) item.failure = failure;
        items.push(item);
      }
    }
    // Most urgent first, the latest first within.
    items.sort((a, b) => (a.kind === b.kind ? b.at - a.at : a.kind === "alert" ? -1 : 1));
    if (currentWorkspace !== id) {
      others.alert += counts.alert;
      others.wait += counts.wait;
      others.unread += counts.unread;
    }
    const badge = badgeOf(prefs, fresh, said);
    // (a workspace turned off on the notifications page adds nothing to the app's badge; its own mark stays)
    if (views.heard(id)) total += badge;
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
    all[id] = mark;
  }
  const value: J = { workspaces: all, badge: total, badgeKinds: kinds };
  const tone = others.tone();
  if (tone !== null) {
    value.others = tone;
    value.othersLabel = tr(current(), "core-views.marks.others", { label: others.label() });
  }
  return { ok: value };
}
