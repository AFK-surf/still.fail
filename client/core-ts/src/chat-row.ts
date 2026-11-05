// A sidebar row as one viewer has it, made of the chat's row as its station makes it once for everyone (station/src/
// read/views.ts `sharedChats`) and what is the viewer's own: where they read to, the cards they let go, the chats they
// kept and pinned, the cards they answered, and who they are. One rule for the station (its `chats`, for devices from
// before) and the core (station/sync.ts), as titles.ts is for a chat's name: the station makes the chat list, never a
// list for one device.
import * as titles from "./titles.ts";

type J = Record<string, any>;

/// What of a row is the viewer's own.
export type Own = {
  /// Whether a person (a creator reference: id, email, via) is the viewer.
  mine: (person: unknown) => boolean;
  /// Where the viewer read each chat to, by its id (none: nothing of it).
  reads: ReadonlyMap<number, number>;
  /// The cards and needs the viewer let go, as `<thread>:<seq>`.
  dismissed: ReadonlySet<string>;
  /// The chats the viewer kept from archiving.
  kept: ReadonlySet<number>;
  /// The viewer's list visibility; absent when the station predates this mark.
  hidden?: ReadonlySet<number>;
  muted?: ReadonlySet<number>;
  /// When the viewer pinned each agent's row, by its key.
  pins: ReadonlyMap<string, number>;
};

/// The words a row says in the viewer's language.
export type Words = titles.TitleWords & { quotedOnly: string };

/// Whether something in the chat after where the viewer read is not theirs (`said`: its latest message, and the latest
/// one before that its author did not write).
function unread(said: J | null | undefined, read: number, mine: Own["mine"]): boolean {
  if (said === null || typeof said !== "object") return false;
  const byViewer = said.authorKind === "person" && mine({ id: said.author, email: said.author });
  const n = byViewer ? said.other : said.n;
  return typeof n === "number" && n > read;
}

/// The row of `shared` (a chat's row as its station made it for everyone) for a viewer.
export function rowFor(shared: J, own: Own, words: Words): J {
  const { named, mineOf, said, answeredBy, ws: _ws, ...row } = shared;
  row.title = named === undefined ? row.title : titles.chatTitle(named.thread, named.firstText ?? null, named.channelName ?? null, words);
  if (row.last && row.last.quotedOnly === true) {
    const { quotedOnly: _, ...last } = row.last;
    row.last = { ...last, text: words.quotedOnly };
  }
  const thread = typeof row.thread === "number" ? row.thread : null;
  row.unread = thread !== null && unread(said, own.reads.get(thread) ?? 0, own.mine);
  row.mine = (Array.isArray(mineOf) ? mineOf : []).some((p: unknown) => own.mine(p));
  if (thread !== null) {
    row.archiveReminderDismissed = own.kept.has(thread);
    if (own.hidden !== undefined) row.hidden = own.hidden.has(thread);
    if (own.muted !== undefined) row.muted = own.muted.has(thread);
    for (const k of ["card", "need"] as const) {
      const c = row[k];
      if (c && typeof c === "object" && own.dismissed.has(`${thread}:${c.seq}`)) row[k] = { ...c, dismissed: true };
    }
    if (row.decision && own.dismissed.has(`${thread}:${row.decision.seq}`)) row.decision = { ...row.decision, dismissed: true };
    const answered = (Array.isArray(answeredBy) ? answeredBy : []).filter((a: J) => own.mine(a.by)).map(({ by: _, ...a }: J) => a);
    if (answered.length > 0) row.answered = answered;
  }
  row.pinned = typeof row.id === "string" ? (own.pins.get(row.id) ?? null) : null;
  return row;
}
