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

/// What a chat's row asks of its person.
export function rowTone(row: J): string | null {
  if (get(row, "mine") !== true) return null;
  const state = present.rowState(arr(get(row, "agents")));
  if (state === "failed") return "alert";
  if (state === "block") return "wait";
  return get(row, "unread") === true && state !== "run" ? "done" : null;
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
  for (const id of workspaceIds(views.ok({ topic: "workspaces" }))) {
    const counts = new Counts();
    let waiting = 0;
    for (const s of views.stations(id) ?? []) {
      const rows = arr(views.ok({ topic: "chatRows", station: s.address }));
      for (const row of rows) {
        if (local.beingArchived(s.address, row)) continue;
        const d = decisions.forViewer(row, views.me(id));
        const thread = get(row, "thread");
        const waits = d !== null && !(typeof thread === "number" && local.answered(s.address, thread, typeof d.seq === "number" ? d.seq : 0));
        if (waits) waiting++;
        const tone = rowTone(row);
        if (tone === "alert") counts.alert++;
        else if (tone === "wait" || waits) counts.wait++;
        else if (tone !== null) counts.unread++;
      }
    }
    if (currentWorkspace !== id) {
      others.alert += counts.alert;
      others.wait += counts.wait;
      others.unread += counts.unread;
    }
    const mark: J = { alert: counts.alert, unread: counts.unread };
    if (counts.wait > 0) mark.wait = counts.wait;
    if (waiting > 0) mark.decisions = waiting;
    const tone = counts.tone();
    if (tone !== null) {
      mark.tone = tone;
      mark.label = counts.label();
    }
    const chat = lastChat(prefs, id);
    if (chat !== null) mark.chat = chat;
    all[id] = mark;
  }
  const value: J = { workspaces: all };
  const tone = others.tone();
  if (tone !== null) {
    value.others = tone;
    value.othersLabel = tr(current(), "core-views.marks.others", { label: others.label() });
  }
  return { ok: value };
}
