// What a person hears about while a client runs (notices.rs; the `notices` topic, docs/notifications.md): a chat of
// theirs whose agent is blocked on them, went wrong, or finished with something new to read, or where someone else
// said something, or where a card newly waits for them. Noticed from the chat rows the core holds (what the sync keeps
// current), by how each row changed in a write (db/account.ts says each row before and after): looked at as they change
// (rule 2), never polled, and never all of them. A station's first rows are where it starts from. Each workspace hears
// of its own.
import * as decisions from "./decisions.ts";
import * as format from "./format.ts";
import { t } from "./i18n.ts";
import { encode } from "./ops.ts";
import * as present from "./present.ts";
import { arr as arrU, get as getU } from "./util.ts";
import type { Workspace, Workspaces } from "./workspace.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// How many notices a workspace holds, and the plain topic.
const KEEP = 20;
/// How long a notice's body may be, in characters.
export const BODY = 140;

/// How a row stood when last looked at.
type Seen = { state: string | null; seq: number; decision: number | null; pending: boolean };

/// What a workspace has heard of its chats: how the rows that changed this run stood when last looked at.
type Heard = { seen: Map<string, Map<string, Seen>>; items: J[] };

/// A row that changed: as it was and as it is (undefined: not there).
export type Changed = { id: string; before: J | undefined; after: J | undefined };

/// What notices read the rows with.
export type NoticesEnv = {
  workspaces: Workspaces;
  members: (workspace: string) => J[];
  slackUsers: (station: string) => string[];
  emailOf: (workspace: string) => string | null;
  now: () => number;
};

export class Notices {
  readonly #env: NoticesEnv;
  #next = 1;

  constructor(env: NoticesEnv) {
    this.#env = env;
  }

  #heard(w: Workspace): Heard {
    return w.part<Heard>("heard", () => ({ seen: new Map(), items: [] }));
  }

  /// A workspace's notices; with none given, every workspace's, the latest KEEP.
  value(workspace: string | null): J {
    if (workspace !== null) {
      const w = this.#env.workspaces.get(workspace);
      return { items: w ? structuredClone(this.#heard(w).items) : [] };
    }
    const all = this.#env.workspaces.all().flatMap((w) => structuredClone(this.#heard(w).items));
    const n = (v: J) => {
      const id = typeof v.id === "string" ? v.id.replace(/^n+/, "") : "";
      return /^[0-9]+$/.test(id) ? Number(id) : 0;
    };
    all.sort((a, b) => n(a) - n(b));
    return { items: all.slice(Math.max(all.length - KEEP, 0)) };
  }

  /// Forgets the stations no longer kept in sync (`stations`: those that are).
  keep(stations: string[]): void {
    for (const w of this.#env.workspaces.all()) {
      const seen = this.#heard(w).seen;
      for (const station of [...seen.keys()]) if (!stations.includes(station)) seen.delete(station);
    }
  }

  /// Rows of a station that changed (`first`: its rows read for the first time, where it starts from): what is worth
  /// telling is noticed, in its workspace, and answered.
  changed(station: string, rows: Changed[], first: boolean): J[] {
    const added: J[] = [];
    const its = this.#env.workspaces.ofStation(station);
    const heard = this.#heard(its);
    let seenHere = heard.seen.get(station);
    if (!seenHere) {
      seenHere = new Map();
      heard.seen.set(station, seenHere);
    }
    const workspace = station.includes("/") ? station.slice(0, station.indexOf("/")) : "";
    const email = this.#env.emailOf(workspace);
    const me = { id: email, email };
    const members = this.#env.members(workspace);
    const slackUsers = this.#env.slackUsers(station);
    for (const change of rows) {
      const row = change.after;
      if (row === undefined) {
        seenHere.delete(change.id);
        continue;
      }
      const old = seenHere.get(change.id) ?? (change.before !== undefined ? seen(change.before) : undefined);
      const next = seen(row);
      if (next.state === "run") next.pending = old !== undefined && (old.pending || next.seq > old.seq);
      seenHere.set(change.id, next);
      if (first) continue;
      const found = noticed(row, old, me, slackUsers, members);
      if (found !== null) added.push(this.#add(its, station, row, found[0], found[1]));
    }
    return added;
  }

  #add(into: Workspace, station: string, row: J, kind: string, body: string): J {
    const at = station.indexOf("/");
    const [workspace, id] = at >= 0 ? [station.slice(0, at), station.slice(at + 1)] : ["", station];
    const session = typeof get(row, "id") === "string" ? row.id : "";
    const n = this.#next++;
    const notice = {
      id: `n${n}`,
      kind,
      station,
      workspace,
      stationId: id,
      session,
      thread: get(row, "thread") ?? null,
      title: title(row),
      body,
      tag: `${workspace}/${id}/${session}`,
      url: `/o/${workspace}/${id}/${encode(session)}`,
      at: Math.trunc(this.#env.now()),
    };
    const items = this.#heard(into).items;
    items.push(notice);
    while (items.length > KEEP) items.shift();
    return structuredClone(notice);
  }
}

function seen(row: J): Seen {
  const p = decisions.pending(row);
  const decision = typeof get(p, "seq") === "number" ? p.seq : null;
  return { state: present.rowState(arr(get(row, "agents"))), seq: lastSeq(row), decision, pending: false };
}

function lastSeq(row: J): number {
  const s = get(get(row, "last"), "seq");
  return typeof s === "number" && Number.isInteger(s) ? s : 0;
}

/// What a row's change is worth telling its person, and in what words.
function noticed(row: J, thenSeen: Seen | undefined, me: J, slackUsers: string[], members: J[]): [string, string] | null {
  if (get(row, "mine") !== true || (get(row, "connect") !== undefined && row.connect !== null)) return null;
  const now = seen(row);
  const then = thenSeen ?? { state: null, seq: 0, decision: null, pending: false };
  const by = present.lastBy(row, me, slackUsers, members);
  const mine = get(by, "mine") === true;
  const card = decisions.ofRow(row);
  if (card !== null && now.decision !== null && now.decision !== then.decision) {
    const text = typeof get(get(card, "message"), "text") === "string" ? card.message.text : "";
    const line = decisions.line(text);
    const cut = line.indexOf(" · ");
    const shown = cut >= 0 && line.slice(0, cut) === t("core-logic.decisions.line.empty") ? line.slice(cut + 3) : line;
    return ["wait", body("wait", "", shown)];
  }
  const last = get(row, "last");
  const hasLast = last !== null && typeof last === "object" && !Array.isArray(last);
  let text = hasLast ? format.cleanText(typeof last.text === "string" ? last.text : "") : "";
  if (text === "" && hasLast) text = t("core-misc.notice.file");
  const byName = typeof get(by, "name") === "string" ? by.name : "";
  if (now.state === "block" && then.state !== "block" && card === null) {
    let need: string | null = null;
    for (const a of arr(get(row, "agents"))) {
      if (present.sessionStatus(a) !== "block") continue;
      const n = get(get(a, "lastTurn"), "need");
      if (typeof n === "string" && n.trim() !== "") {
        need = n.trim();
        break;
      }
    }
    return ["block", need !== null ? body("block", "", need) : body("block", byName, text)];
  }
  const fresh = now.seq > then.seq;
  const kind = get(by, "kind");
  if (fresh && (kind === "ember" || kind === "stillfail") && text.startsWith("⚠️")) return ["failed", body("failed", "", text.slice("⚠️".length).trim())];
  const unread = get(row, "unread") === true;
  if (!unread || !(fresh || then.pending) || mine || now.state === "run" || !hasLast) return null;
  const k = kind === "agent" ? "done" : kind === "person" ? "message" : null;
  if (k === null) return null;
  return [k, body(k, byName, text)];
}

/// A notice's body, as still.fail cloud words a push the same: one line, cut short.
export function body(kind: string, by: string, text: string): string {
  const words = format.splitWhitespace(text).join(" ");
  let line: string;
  if (kind === "block") line = t("core-misc.notice.block", { text: words });
  else if (kind === "wait") line = t("core-misc.notice.wait", { text: words });
  else if (kind === "failed") line = t("core-misc.notice.failed", { text: words });
  else if (by !== "") line = `${by}: ${words}`;
  else line = words;
  return cut(line.replace(/[ ·:]+$/, ""), BODY);
}

function cut(text: string, max: number): string {
  const chars = Array.from(text);
  return chars.length <= max ? text : `${chars.slice(0, max - 1).join("")}…`;
}

function title(row: J): string {
  const v = get(row, "title");
  const words = typeof v === "string" ? format.splitWhitespace(v).join(" ") : "";
  return words !== "" ? words : t("core-misc.notice.untitled");
}
