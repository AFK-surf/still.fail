// What each workspace has waiting for its person, for where workspaces are switched (views/marks.rs): of the chats
// they take part in, those that want them and those with something unread; the chat last open in it. Only how many
// and how urgent goes past a workspace.
import { decodeComponent } from "../accounts.ts";
import * as decisions from "../decisions.ts";
import { tr, current, type Lang } from "../i18n.ts";
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

/// A row's state line as its list says it (its agents presented as the chats view has them).
function stateText(row: J): string {
  const shown = structuredClone(row);
  for (const a of arr(shown.agents)) present.session(a);
  return present.rowStateText(shown) ?? "";
}

const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// What the badge counts (the prefs' `badge`): the cards waiting for the person (decisions), those and the chats of
/// theirs that went wrong (attention, the default), or those and the unread too (all).
export function badgeOf(prefs: J, c: Counts): number {
  const by = get(prefs, "badge");
  if (by === "decisions") return c.wait;
  if (by === "all") return c.alert + c.wait + c.unread;
  return c.alert + c.wait;
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
  const all: Record<string, J> = {};
  const others = new Counts();
  let total = 0;
  const names = new Map<string, string>();
  for (const a of arr(views.ok({ topic: "workspaces" }))) for (const w of arr(get(a, "workspaces"))) if (typeof get(w, "id") === "string") names.set(w.id, str(get(w, "name")) ?? w.id);
  for (const id of workspaceIds(views.ok({ topic: "workspaces" }))) {
    const counts = new Counts();
    let waiting = 0;
    let elsewhere = 0;
    const items: J[] = [];
    const me = views.me(id);
    // Only the rows that ask something or are unread count (db/account.ts: found by their columns, not loaded whole).
    const stations = views.stations(id) ?? [];
    const nameOf = new Map(stations.map((s) => [s.address, s.name]));
    for (const [address, row] of views.marked(stations.map((s) => s.address))) {
      if (local.beingArchived(address, row)) continue;
      const d = decisions.forViewer(row, me);
      const thread = get(row, "thread");
      const waits = d !== null && !(typeof thread === "number" && local.answered(address, thread, typeof d.seq === "number" ? d.seq : 0));
      const tone = waits ? "wait" : rowTone(row, me);
      if (waits) waiting++;
      if (tone === "alert") counts.alert++;
      else if (tone === "wait") counts.wait++;
      else if (tone === "done") counts.unread++;
      else if (get(row, "mine") === true && present.rowState(arr(get(row, "agents"))) === "block") elsewhere++;
      if (tone === "alert" || tone === "wait") {
        const item: J = {
          kind: tone,
          workspace: id,
          workspaceName: names.get(id) ?? id,
          station: address,
          stationName: nameOf.get(address) ?? address,
          session: get(row, "id") ?? null,
          thread: typeof thread === "number" ? thread : null,
          title: str(get(row, "title")) ?? "",
          text: stateText(row),
          at: typeof get(row, "lastActiveAt") === "number" ? row.lastActiveAt : 0,
        };
        if (waits && typeof d.seq === "number") item.seq = d.seq;
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
    const badge = badgeOf(prefs, counts);
    total += badge;
    const mark: J = { alert: counts.alert, unread: counts.unread, badge, items };
    if (counts.wait > 0) mark.wait = counts.wait;
    if (waiting > 0) mark.decisions = waiting;
    if (elsewhere > 0) mark.elsewhere = elsewhere;
    const tone = counts.tone();
    if (tone !== null) {
      mark.tone = tone;
      mark.label = counts.label();
    }
    const chat = lastChat(prefs, id);
    if (chat !== null) mark.chat = chat;
    all[id] = mark;
  }
  const value: J = { workspaces: all, badge: total, badgeCounts: ["decisions", "all"].includes(get(prefs, "badge")) ? prefs.badge : "attention" };
  const tone = others.tone();
  if (tone !== null) {
    value.others = tone;
    value.othersLabel = tr(current(), "core-views.marks.others", { label: others.label() });
  }
  return { ok: value };
}
