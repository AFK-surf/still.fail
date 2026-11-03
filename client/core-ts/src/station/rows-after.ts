// A station's sidebar rows (GET /chats, station/src/read/views.ts `chats`) as the device holds them, brought on here by
// what the station's stream says changed: what was said in a chat, a session's summary, what the viewer pinned or
// dismissed. The station tells what it writes as it writes it, and leaves what a row makes of that to the device
// (`rows=1`, docs/core-ts.md, sync). Made by the station, each change read every row it could touch again for every
// viewer, from the disk while its machine was short of memory: 3 to 5 s each on ccvm (2026-11-03).
//
// What only the station can say (a card waiting and the messages before it, what an agent's need asks with, a chat
// new to the list or gone from it, the review's marks) is read from it, the rows that change alone (`"read"`).
import { get, isObject } from "../util.ts";
import { trim } from "../whitespace.ts";

type J = Record<string, any>;

/// A row as it is now, `"read"` where only the station can say what it is now, null where nothing of it changed.
export type After = J | "read" | null;

/// How much of a chat's latest message its row says (views.ts LAST_CHARS).
const LAST_CHARS = 200;

const n = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);

/// What a row's agent says of its session (views.ts `chats` `agent`), from the session's summary.
const AGENT_FIELDS = ["runtime", "model", "effort", "process", "pending", "lastTurn"] as const;

/// Whether a session's last turn asks a person for something (views.ts `needView`): its row's `need` is the station's.
function asks(turn: unknown): boolean {
  if (!isObject(turn)) return false;
  const ending = get(turn, "ending");
  return typeof ending === "string" ? ending === "need_help" || ending === "need_decision" : get(turn, "declared") === "block";
}

/// The row's `last` (views.ts `chats`) from a message as the stream told it.
function lastOf(e: J): J {
  const text = typeof e.text === "string" ? [...trim(e.text)].slice(0, LAST_CHARS).join("") : null;
  const last: J = { seq: e.n, authorKind: e.authorKind, author: e.author, authorName: e.authorName ?? null, text, createdAt: e.at };
  if (e.authorPicture !== undefined) last.authorPicture = e.authorPicture;
  if (e.agentIdentity != null) last.agentIdentity = e.agentIdentity;
  if (e.authorModel !== undefined) last.authorModel = e.authorModel;
  if (e.authorRuntime !== undefined) last.authorRuntime = e.authorRuntime;
  return last;
}

/// A row of a chat (`row.thread` the thread `entries` were said in, as the stream told them: GET /threads/:id/entries'
/// shape) after they were, for the viewer whose email is `me`.
export function rowAfterSaid(row: unknown, entries: readonly unknown[], me: string): After {
  if (!isObject(row)) return null;
  const said = (entries.filter(isObject) as J[]).filter((e) => n(e.n) !== null).sort((a, b) => a.n - b.n);
  if (said.length === 0) return null;
  const held = get(row, "last");
  const seen = n(get(held, "seq")) ?? -1;
  const waits = isObject(get(row, "card")) || isObject(get(row, "need"));
  const waitsOn = [n(get(get(row, "card"), "seq")), n(get(get(row, "need"), "seq"))];
  const mine = me.toLowerCase();
  const marked = get(row, "archiveRecommended") === true || get(row, "archiveCheck") !== undefined;
  let out: J = row as J;
  let last = (held ?? null) as J | null;
  let unread = get(row, "unread") === true;
  let people = (get(row, "people") as J[] | undefined) ?? [];
  let isMine = get(row, "mine") === true;
  let active = n(get(row, "lastActiveAt")) ?? 0;
  let changed = false;
  for (const e of said) {
    if (e.kind === "edit") {
      // A card's post or the message a need asks with, edited: the station's to say again.
      // (the review's marks too: they hold while the chat stands as it looked at it.)
      if (waitsOn.includes(n(e.target)) || marked) return "read";
      // An edit of its latest message is what that says now.
      if (last !== null && e.target === last.seq) {
        last = { ...last, text: typeof e.text === "string" ? [...trim(e.text)].slice(0, LAST_CHARS).join("") : null };
        changed = true;
      }
      continue;
    }
    if (e.kind !== "message") return "read";
    // What the row was read with already.
    if (e.n <= seen) continue;
    // A card posted, or a person writing while one (or a need) waits on them: what waits and what was answered is the
    // station's to say.
    if (e.card !== undefined && e.card !== null) return "read";
    if (e.authorKind === "person" && waits) return "read";
    // The review's marks hold while the chat stands as it looked at it (read/store.ts `archiveSuggested`).
    if (marked && out === row) {
      out = { ...out, archiveRecommended: false };
      delete out.archiveCheck;
      changed = true;
    }
    // A letter (another chat's agent's, kept as one before letters had a log of their own) is none of the rest.
    if (e.letter !== undefined) continue;
    if (e.authorKind === "person") {
      // Someone known only by other names than their email (the station's own page, a Slack person): the station's.
      if (typeof e.author !== "string" || !e.author.includes("@")) return "read";
      const own = e.author.toLowerCase() === mine;
      if (own) isMine = true;
      else unread = true;
      if (!people.some((p) => get(p, "id") === e.author)) people = [...people, { id: e.author, name: e.authorName ?? e.author, email: e.author, via: "cloud" }];
    } else {
      unread = true;
    }
    // Only quotes: the station says so in its own words (views.ts `quotedOnly`).
    if (typeof e.text === "string" && trim(e.text) === "" && Array.isArray(e.quotes) && e.quotes.length > 0) return "read";
    last = lastOf(e);
    active = Math.max(active, n(e.at) ?? 0);
    changed = true;
  }
  return changed ? { ...out, last, unread, people, mine: isMine, lastActiveAt: active } : null;
}

/// A row with one of its agents after its session's summary changed from `before` (none: not held) to `summary`.
export function rowAfterSession(row: unknown, before: unknown, summary: unknown): After {
  if (!isObject(row) || !isObject(summary)) return null;
  const key = get(summary, "key");
  // Archived or back, named, its chat app or who started it otherwise: which rows there are and what they say is the
  // station's to say.
  if (get(summary, "archivedAt") !== null && get(summary, "archivedAt") !== undefined) return "read";
  if (isObject(before)) {
    for (const k of ["archivedAt", "title", "connect", "createdBy"]) if (JSON.stringify(get(before, k) ?? null) !== JSON.stringify(get(summary, k) ?? null)) return "read";
    if ((asks(get(before, "lastTurn")) || asks(get(summary, "lastTurn"))) && JSON.stringify(get(before, "lastTurn") ?? null) !== JSON.stringify(get(summary, "lastTurn") ?? null)) return "read";
  } else if (asks(get(summary, "lastTurn"))) {
    return "read";
  }
  const agents = get(row, "agents");
  if (!Array.isArray(agents)) return null;
  let changed = false;
  const next = agents.map((a) => {
    if (get(a, "key") !== key) return a;
    const v: J = { ...(a as J) };
    for (const k of AGENT_FIELDS) v[k] = get(summary, k) ?? (k === "pending" ? 0 : k === "process" ? "cold" : null);
    const watch = get(summary, "watch");
    if (watch !== undefined) v.watch = watch;
    else delete v.watch;
    if (JSON.stringify(v) !== JSON.stringify(a)) changed = true;
    return v;
  });
  let out: J = row as J;
  if (changed) out = { ...out, agents: next };
  // A row with no chat yet is as active as its session.
  const at = n(get(summary, "lastActiveAt"));
  if (get(row, "thread") === null && at !== null && at !== get(row, "lastActiveAt")) {
    out = { ...out, lastActiveAt: at };
    changed = true;
  }
  return changed ? out : null;
}

/// A row after the viewer pinned it (`at`) or let it go (null).
export function rowAfterPin(row: unknown, at: number | null): After {
  if (!isObject(row) || (get(row, "pinned") ?? null) === at) return null;
  return { ...(row as J), pinned: at };
}

/// A row after the viewer said they will not take up what waits in its chat at `seq` (its card, or its agent's need).
export function rowAfterDismiss(row: unknown, seq: number): After {
  if (!isObject(row)) return null;
  const out: J = { ...(row as J) };
  let changed = false;
  for (const k of ["card", "decision", "need"]) {
    const v = get(row, k);
    if (isObject(v) && get(v, "seq") === seq && get(v, "dismissed") !== true) {
      out[k] = { ...(v as J), dismissed: true };
      changed = true;
    }
  }
  return changed ? out : null;
}

/// A row after the viewer kept its chat from being offered for archiving (or let it be again).
export function rowAfterKept(row: unknown, kept: boolean): After {
  if (!isObject(row) || get(row, "archiveReminderDismissed") === kept) return null;
  return { ...(row as J), archiveReminderDismissed: kept };
}
