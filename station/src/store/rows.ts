// The store's rows (the Rust station's store.rs `// ── rows`), camelCase, and how they are read from and written to the database.
// Option is `T | null`; where the Rust leaves a None Value out (EntryRow's agentIdentity, options, card) it is undefined.
// The readers (read/store.ts) read rows with these same conversions, leaving out what is not for the pages (tokens).

export type Json = any;

/// The page's own threads live on this surface, in this channel (stored under the name of before the rename).
export const STILLFAIL_SURFACE = "ember";
/// Archived by a person.
export const MANUAL = "manual";
/// Archived by the station, for idling (or brought back by something said).
export const AUTO = "auto";
/// SQLite's and Rust's i64::MAX, for "no bound".
export const I64_MAX = 9223372036854775807n;


/// Where a Slack connect's threads live: its team, or the connect itself while the team is unknown.
export function slackSurface(connect: string, teamId: string | null): string {
  return teamId ? `slack:${teamId}` : `slack:${connect}`;
}

/// Where a Feishu connect's threads live: the connect's own (docs/feishu.md).
export const feishuSurface = (connect: string): string => `feishu:${connect}`;

export type SessionScope = "thread" | "all";

/// Who looks, as far as the station's workspaces go (docs/multi-workspace.md): their workspace, and whether it is the
/// station's home one (absent: it is, as on a station in one workspace).
export type InWorkspace = { workspace: string; home?: boolean };

/// Whether a session whose chat is in `ws` (null: the station's home workspace) is one `viewer` may see and use: a
/// member of one workspace sees nothing of another's chats.
export const sees = (viewer: InWorkspace, ws: string | null): boolean => ws === viewer.workspace || (ws === null && viewer.home !== false);

export type SessionRow = {
  key: string; connect: string; scope: SessionScope; title: string | null; createdBy: string | null; runtime: string;
  profile: string; profilePinned: boolean; model: string | null; effort: string | null; fast: boolean | null;
  runtimeSessionId: string | null; workspace: string; cwd: string | null;
  /// Which of the station's workspaces its chat is in (docs/multi-workspace.md): null is its home workspace (sessions
  /// from before, and those made outside any workspace's request). Not the `workspace` above, its directory.
  ws: string | null;
  /// Not for the pages (serde skip).
  token: string;
  running: boolean; createdAt: number; lastActiveAt: number; archivedAt: number | null; archivedBy: string | null;
  shownAt: number | null;
};

/// A session as it is first recorded (what NewSession::default leaves out may be left out).
export type NewSession = {
  key: string; connect: string; scope?: SessionScope | null; title?: string | null; createdBy?: string | null;
  runtime: string; profile: string; profilePinned?: boolean; model?: string | null; effort?: string | null;
  fast?: boolean | null; workspace: string; cwd?: string | null; runtimeSessionId?: string | null; token: string;
  createdAt: number; lastActiveAt: number; ws?: string | null;
};

/// A place people talk: a Slack thread, or a chat on the station's page.
export type ThreadRow = {
  id: number; surface: string; channel: string; threadTs: string; title: string | null; autoTitle: string | null;
  createdBy: string | null; createdAt: number; home: string | null; hiddenAt: number | null; hiddenBy: string | null;
  shownAt: number | null;
};

/// The name a chat's agent gave it (Store::autoTitle).
export type AutoTitle = { title: string | null; n: number; changes: number };

/// A thread of a session, with the connect the session posts there through.
export type SessionThread = { thread: ThreadRow; connect: string };

/// A session in a thread, and the connect it posts there through.
export type Membership = { thread: number; session: string; connect: string; joinedAt: number };

/// "ember" is the station itself (named, stored and sent as before the rename).
export type AuthorKind = "person" | "agent" | "ember";
export type EntryKind = "message" | "edit";

export type Quote = { author: string; text: string; comment: string; ts?: string; role?: string; file?: string };
/// `width`, `height`: a picture's or a film's size as shown; `duration` (ms) and `frames`: a film's length and how many
/// frames its picture has (sessions/image-size.ts shownFacts), so a page says them before it reads the film.
export type Attachment = { name: string; path: string; size: number; width?: number; height?: number; thumbhash?: string; duration?: number; frames?: number };

/// One entry of a thread's log (as the archive files hold them, one per line).
export type EntryRow = {
  agentIdentity: Json | undefined; thread: number; n: number; kind: EntryKind; target: number | null; ts: string | null;
  authorKind: AuthorKind; author: string; text: string | null; attachments: Attachment[]; quotes: Quote[];
  declared: string | null; client: string | null; profile: string | null; runtime: string | null; options: Json | undefined; card: Json | undefined;
  at: number;
  /// A letter's (isLetter): which way it went and the other chat. Absent on every other entry.
  letter?: Letter;
};

/// What two chats' agents wrote each other (session_send), kept apart from what is said in a chat: `in`, another chat's
/// agent wrote this one (delivered to its agents); `out`, this chat's agent wrote another (`author`, delivered to none
/// here). `title` and `link` name the other chat.
export type Letter = { way: "in" | "out"; title: string; link: string | null };

/// A message as it reads now: its latest edit's words, files and quotes.
export type MessageRow = {
  agentIdentity: Json | null; thread: number; n: number; ts: string; authorKind: AuthorKind; author: string; text: string;
  attachments: Attachment[]; quotes: Quote[]; declared: string | null; client: string | null; createdAt: number;
  editedAt: number | null; letter?: Letter;
};

/// A card someone answered (`answersSince`).
export type CardAnswer = { question: MessageRow; card: Json; by: string; at: number; answer: MessageRow | null };

/// A message a session has yet to read, with where it was said and how the session hears that thread.
export type PendingMessage = { message: MessageRow; surface: string; channel: string; threadTs: string; connect: string };

/// A thread for listings: who takes part, the last thing said, and how much the viewer has not read.
/// Whether a message is a letter (Letter): marked so when it was recorded; one from before letters were marked, by
/// another chat's agent (not of the thread's `keys`) headed as sessions/messages.ts heads them (`来自 …：`, `From …:`),
/// is one coming in. Lists, unread counts and the chat's page leave letters out, so that what agents write to each other
/// does not bury what people say; the page shows them apart (core views.ts).
export function isLetter(m: { authorKind: string; author: string; text: string; letter?: Letter }, keys: ReadonlySet<string>): boolean {
  if (m.letter !== undefined) return true;
  return m.authorKind === "agent" && !keys.has(m.author) && (m.text.startsWith("来自 ") || m.text.startsWith("From "));
}

/// isLetter in SQL, of an entry or merged row (marked when recorded, or on opening for those from before: schema.ts
/// addLetterColumn).
export const LETTER_SQL = "(letter IS NOT NULL)";

/// The Slack and Feishu threads a still.fail chat can copy what people send to when they ask (`cc`, docs/relay.md
/// "抄送"): every one its agents are in, the one said in last first, at most 20; with a connect that posts there. One
/// `?`: the chat's thread id.
export const CC_THREADS_SQL = `SELECT t.*, o.connect FROM thread_sessions m
  JOIN thread_sessions o ON o.session = m.session JOIN threads t ON t.id = o.thread
  WHERE m.thread = ? AND t.surface != '${STILLFAIL_SURFACE}'
  GROUP BY t.id
  ORDER BY (SELECT MAX(e.at) FROM entries e WHERE e.thread = t.id) DESC, t.created_at DESC, t.id DESC
  LIMIT 20`;

/// The letter an entry's `letter` column (or an archive file's entry) holds (absent: none, or one not read).
export function letterOf(v: unknown): Letter | undefined {
  const l = typeof v === "string" ? parsed(v) : v;
  if (l === null || l === undefined || typeof l !== "object") return undefined;
  const way = l.way === "in" || l.way === "out" ? l.way : null;
  if (way === null || typeof l.title !== "string") return undefined;
  return { way, title: l.title, link: typeof l.link === "string" ? l.link : null };
}

export type ThreadSummary = {
  thread: ThreadRow; sessions: Membership[]; last: number; lastMessage: MessageRow | null; read: number; unread: number;
  people: string[]; firstText: string | null;
  /// How many letters it has (Letter), in either way.
  letters: number;
};

/// The message a turn's state is about: its thread, entry (`seq`) and ts.
export type TurnAbout = { thread: number; seq: number; ts: string };

export type TurnSummary = {
  kind: string; outcome: string | null; declared: string | null; ending: string | null; need: string | null;
  about: TurnAbout | null; waitSeconds: number | null; waitFor: string | null;
  /// Whether the wait is its session's watch keeping on (chat_state waiting `watch`); null said before it.
  waitWatch: boolean | null; detail: string | null; startedAt: number; endedAt: number | null;
};

export type TurnRow = { id: string; summary: TurnSummary };

export type SessionStats = { turns: number; pending: number; firstText: string | null; lastTurn: TurnSummary | null };

/// A profile's last check and quota, kept across restarts.
export type ProfileStatus = { check: Json | null; quota: Json | null };

export type ProcessRow = { pgid: number; startedAt: number; runtime: string; label: string };

/// A message being recorded (NewMessage::new's defaults may be left out).
export type NewMessage = {
  thread: number; ts: string; authorKind: AuthorKind; author: string; text: string; attachments?: Attachment[];
  quotes?: Quote[]; declared?: string | null; client?: string | null; profile?: string | null; runtime?: string | null; card?: Json | null;
  options?: Json | null; at?: number | null; letter?: Letter;
};

export const newMessage = (thread: number, ts: string, authorKind: AuthorKind, author: string, text: string): NewMessage => ({
  thread, ts, authorKind, author, text,
});

/// A background job a session started. `sessionKey` is serde's `session`.
export type JobRow = {
  id: string; sessionKey: string; name: string; command: string; cwd: string; port: number | null;
  /// Not for the pages (serde skip).
  token: string;
  state: string; pgid: number | null; exitCode: number | null; startedAt: number; endedAt: number | null;
  restarts: number; log: string; watch: boolean;
  /// Waiting in the station's queue for room (jobs/admit.ts): running as far as its agent is concerned, not started yet.
  queued?: boolean;
  /// It uses the screen (windows, a simulator): one such job at a time.
  screen?: boolean;
  /// The sandbox size it asked for, by the name the sandboxes' operator gave it (agents/sandbox.ts): a sandbox of its
  /// own, of that size.
  size?: string;
};

export type JobNotice = { at: number; text: string };

/// What a person chose in a widget an agent posted. `thread` is (channel, thread ts) when its message is still there.
export type WidgetModel = { path: string; name: string; thread: [string, string] | null; model: string };

/// Whom a turn works for (Store::startTurnFor).
export type TurnFor = { profile: string | null; person: string | null; thread: number | null };

/// What the store says changed, for whoever follows it (the admin API's /events, the hub).
export type StoreChange =
  /// Anything about that session changed.
  | { type: "session"; key: string }
  /// It was deleted; `ws` the workspace its chat was in (null: the home one).
  | { type: "sessionRemoved"; key: string; ws?: string | null }
  /// Entries were appended there (contiguous, in order), or its sessions changed (none).
  | { type: "thread"; id: number; entries: EntryRow[] }
  /// It went, with every entry it had; `ws` as its session's.
  | { type: "threadRemoved"; id: number; ws?: string | null }
  /// A viewer's read position moved.
  | { type: "read"; viewer: string; thread: number; n: number }
  /// The Slack users a viewer said are them changed.
  | { type: "identities"; viewer: string }
  /// The chats a viewer pinned changed.
  | { type: "pins"; viewer: string }
  /// The decisions a viewer dismissed changed.
  | { type: "dismissed"; viewer: string }
  /// The recorded runtime processes changed.
  | { type: "processes" }
  | { type: "decisionChecks" }
  /// A background job started, started again, ended or said something (its session changes as well).
  | { type: "job"; id: string }
  /// A job that was over was taken off its session's record.
  | { type: "jobRemoved"; id: string; session: string }
  /// Model calls were recorded (store/usage.ts), of these sessions.
  | { type: "usage"; sessions: string[] }
  /// A session went on in another runtime session, or in none (its context cleared): where its context stands changed.
  | { type: "conversation"; key: string };

// ── words ──

/// How a turn ended or a post was declared, in the words from before: final, block, waiting.
export function saidBefore(declared: string): string {
  if (declared === "all_done") return "final";
  if (declared === "need_decision" || declared === "need_help") return "block";
  return declared;
}

/// The same in today's words: final is all_done, block and need_decision need_help.
export function ending(declared: string): string {
  if (declared === "final") return "all_done";
  if (declared === "block" || declared === "need_decision") return "need_help";
  return declared;
}

/// Options to pick from as a card.
export const optionsCard = (options: Json): Json => ({ type: "options", options });

/// EntryRow::card: its own card, else its options as an options card (a post from before cards).
export const cardOfEntry = (e: EntryRow): Json | undefined => e.card ?? (e.options === undefined ? undefined : optionsCard(e.options));

/// `serde_json::from_str::<Value>(..).ok()`: undefined when it does not parse.
export function parsed(text: string | null | undefined): Json | undefined {
  if (text === null || text === undefined) return undefined;
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

/// A message's card as kept: its `card` column, else its `options` (from before cards) as an options card.
export function cardOf(card: string | null, options: string | null): Json | undefined {
  const own = parsed(card);
  if (own !== undefined) return own;
  const before = parsed(options);
  return before === undefined ? undefined : optionsCard(before);
}

// serde's reading (and writing) of Attachment and Quote: their fields in their order, unknown ones dropped, a wrong one
// fails the list.
const isObj = (v: Json) => v !== null && typeof v === "object" && !Array.isArray(v);
const optional = (v: Json, ok: (v: Json) => boolean) => v === undefined || v === null || ok(v);
const isStr = (v: Json) => typeof v === "string";
const isU64 = (v: Json) => typeof v === "number" && Number.isInteger(v) && v >= 0;
const isU32 = (v: Json) => isU64(v) && v <= 0xffffffff;

export function attachment(a: Json): Attachment {
  if (!isObj(a) || !isStr(a.name) || !isStr(a.path) || !isU64(a.size)) throw new Error("attachment");
  if (!optional(a.width, isU32) || !optional(a.height, isU32) || !optional(a.thumbhash, isStr)) throw new Error("attachment");
  if (!optional(a.duration, isU64) || !optional(a.frames, isU32)) throw new Error("attachment");
  const v: Attachment = { name: a.name, path: a.path, size: a.size };
  if (a.width !== undefined && a.width !== null) v.width = a.width;
  if (a.height !== undefined && a.height !== null) v.height = a.height;
  if (a.thumbhash !== undefined && a.thumbhash !== null) v.thumbhash = a.thumbhash;
  if (a.duration !== undefined && a.duration !== null) v.duration = a.duration;
  if (a.frames !== undefined && a.frames !== null) v.frames = a.frames;
  return v;
}

export function quote(q: Json): Quote {
  if (!isObj(q) || !isStr(q.author) || !isStr(q.text) || !isStr(q.comment)) throw new Error("quote");
  if (!optional(q.ts, isStr) || !optional(q.role, isStr) || !optional(q.file, isStr)) throw new Error("quote");
  const v: Quote = { author: q.author, text: q.text, comment: q.comment };
  if (q.ts !== undefined && q.ts !== null) v.ts = q.ts;
  if (q.role !== undefined && q.role !== null) v.role = q.role;
  if (q.file !== undefined && q.file !== null) v.file = q.file;
  return v;
}

/// from_json_list: a stored list, or none when it does not read.
function fromJsonList<T>(text: string | null, read: (v: Json) => T): T[] {
  const list = parsed(text);
  if (!Array.isArray(list)) return [];
  try {
    return list.map(read);
  } catch {
    return [];
  }
}

/// json_list: none for an empty list, else the list as serde writes it.
export function jsonList<T>(value: T[], write: (v: Json) => T): string | null {
  return value.length === 0 ? null : JSON.stringify(value.map(write));
}

/// AuthorKind::parse.
export function authorKind(s: string): AuthorKind {
  if (s === "agent") return "agent";
  if (s === "ember" || s === "stillfail") return "ember";
  return "person";
}

export function toSession(r: Json): SessionRow {
  return {
    key: r.key, connect: r.connect, scope: r.scope === "all" ? "all" : "thread", title: r.title, createdBy: r.created_by,
    runtime: r.runtime, profile: r.profile, profilePinned: r.profile_pinned === 1, model: r.model, effort: r.effort,
    fast: r.fast === null || r.fast === undefined ? null : r.fast !== 0, runtimeSessionId: r.runtime_session_id,
    workspace: r.workspace, cwd: r.cwd ?? null, ws: r.ws ?? null, token: r.token, running: r.running === 1, createdAt: r.created_at,
    lastActiveAt: r.last_active_at, archivedAt: r.archived_at, archivedBy: r.archived_by, shownAt: r.shown_at,
  };
}

/// A chat an agent opened for another (opened_chats): each side by its station ('' for this one) and session key.
export type Opened = {
  childStation: string; child: string; parentStation: string; parent: string; key: string; title: string | null;
  link: string | null; state: string | null; createdAt: number;
};

export function toOpened(r: Json): Opened {
  return {
    childStation: r.child_station, child: r.child, parentStation: r.parent_station, parent: r.parent, key: r.key, title: r.title,
    link: r.link, state: r.state, createdAt: r.created_at,
  };
}

/// A chat published as a snapshot (docs/public-share.md): its link's id and key, by whom and when, up to which message.
export type Published = { id: string; thread: number; key: string; title: string; by: string; byName: string; at: number; upto: number; size: number };

export function toPublished(r: Json): Published {
  return { id: r.id, thread: r.thread, key: r.key, title: r.title, by: r.created_by, byName: r.by_name, at: r.created_at, upto: r.upto, size: r.size };
}

/// How long a chat stays shared with a workspace whose agents neither read it nor write to it (docs/chat-share.md):
/// after that a person must share it again.
export const XSHARE_IDLE_MS = 6 * 60 * 60_000;

/// Why a chat once shared with an agent's workspace is not now.
export const LAPSED = "that chat's share with your workspace lapsed, unused for 6 hours: a person of its workspace must share it again (by @-mentioning it in a message to you, or in its chat info)";

/// A chat shared with other workspaces (chat_shares, docs/chat-share.md): each workspace with when its agents last read
/// it or wrote to it, or it was shared with them (`used`).
export type ChatShare = { to: { workspace: string; name: string; used: number }[]; write: boolean; by: string; at: number };

/// A chat_shares row as stored: every workspace it names, those whose share lapsed too (one kept from before `used`
/// was used when it was shared).
export function toChatShare(r: Json): ChatShare {
  let to: Json = [];
  try {
    to = JSON.parse(r.shared);
  } catch {}
  const list = Array.isArray(to)
    ? to.filter((t: Json) => typeof t?.workspace === "string").map((t: Json) => ({ workspace: t.workspace as string, name: String(t.name ?? t.workspace), used: typeof t.used === "number" ? t.used : r.at }))
    : [];
  return { to: list, write: r.write === 1, by: r.by, at: r.at };
}

/// Whether a workspace's share is still on at `now`: used within XSHARE_IDLE_MS.
export const shareLive = (t: { used: number }, now: number) => now - t.used < XSHARE_IDLE_MS;

/// A share as it is at `now`: the workspaces it is still on for; null when none.
export function liveShare(share: ChatShare, now: number): ChatShare | null {
  const to = share.to.filter((t) => shareLive(t, now));
  return to.length === 0 ? null : { ...share, to };
}

export function toThread(r: Json): ThreadRow {
  return {
    id: r.id, surface: r.surface, channel: r.channel, threadTs: r.thread_ts, title: r.title, autoTitle: r.auto_title,
    createdBy: r.created_by, createdAt: r.created_at, home: r.home, hiddenAt: r.hidden_at, hiddenBy: r.hidden_by,
    shownAt: r.shown_at,
  };
}

export const toSessionThread = (r: Json): SessionThread => ({ thread: toThread(r), connect: r.connect });

export const toMembership = (r: Json): Membership => ({ thread: r.thread, session: r.session, connect: r.connect, joinedAt: r.joined_at });

export function toEntry(r: Json): EntryRow {
  return {
    agentIdentity: parsed(r.agent_identity), thread: r.thread, n: r.n, kind: r.kind === "edit" ? "edit" : "message",
    target: r.target, ts: r.ts, authorKind: authorKind(r.author_kind), author: r.author, text: r.text,
    attachments: fromJsonList(r.attachments, attachment), quotes: fromJsonList(r.quotes, quote), declared: r.declared,
    client: r.client, profile: r.profile, runtime: r.runtime ?? null, options: parsed(r.options), card: parsed(r.card), at: r.at,
    ...withLetter(r.letter),
  };
}

/// `letter` when there is one (letterOf), to spread into a row.
export const withLetter = (v: unknown): { letter?: Letter } => {
  const letter = letterOf(v);
  return letter === undefined ? {} : { letter };
};

export function toMessage(r: Json): MessageRow {
  return {
    agentIdentity: parsed(r.agent_identity) ?? null, thread: r.thread, n: r.n, ts: r.ts ?? "",
    authorKind: authorKind(r.author_kind), author: r.author, text: r.text ?? "",
    attachments: fromJsonList(r.attachments, attachment), quotes: fromJsonList(r.quotes, quote), declared: r.declared,
    client: r.client, createdAt: r.created_at, editedAt: r.edited_at, ...withLetter(r.letter),
  };
}

/// to_about: all three, or none.
function toAbout(r: Json): TurnAbout | null {
  return r.about_thread !== null && r.about_n !== null && r.about_ts !== null ? { thread: r.about_thread, seq: r.about_n, ts: r.about_ts } : null;
}

/// TurnSummary from a turns row (or session_stats' `l.*`).
export function toTurnSummary(r: Json): TurnSummary {
  return {
    kind: r.kind, outcome: r.outcome, declared: r.declared === null ? null : saidBefore(r.declared),
    ending: r.declared === null ? null : ending(r.declared), need: r.need, about: toAbout(r), waitSeconds: r.wait_seconds,
    waitFor: r.wait_for, waitWatch: r.wait_watch === null || r.wait_watch === undefined ? null : r.wait_watch === 1, detail: r.detail, startedAt: r.started_at, endedAt: r.ended_at,
  };
}

/// TurnSummary as serde writes it: camelCase, the skipped Nones (ending, need, about, waitSeconds, waitFor, waitWatch) left
/// out.
export function turnSummaryJson(t: TurnSummary): Record<string, Json> {
  const v: Record<string, Json> = { kind: t.kind, outcome: t.outcome, declared: t.declared };
  if (t.ending !== null) v.ending = t.ending;
  if (t.need !== null) v.need = t.need;
  if (t.about !== null) v.about = t.about;
  if (t.waitSeconds !== null) v.waitSeconds = t.waitSeconds;
  if (t.waitFor !== null) v.waitFor = t.waitFor;
  if (t.waitWatch !== null) v.waitWatch = t.waitWatch;
  v.detail = t.detail;
  v.startedAt = t.startedAt;
  v.endedAt = t.endedAt;
  return v;
}

export function toJob(r: Json): JobRow {
  return {
    id: r.id, sessionKey: r.session_key, name: r.name, command: r.command, cwd: r.cwd, port: r.port, token: r.token,
    state: r.state, pgid: r.pgid, exitCode: r.exit_code, startedAt: r.started_at, endedAt: r.ended_at,
    restarts: r.restarts, log: r.log, watch: r.watch !== 0, ...(r.queued === 1 ? { queued: true } : {}), ...(r.screen === 1 ? { screen: true } : {}),
    ...(typeof r.size === "string" ? { size: r.size } : {}),
  };
}

/// Entries merged into their messages, as the `merged` view does: for a thread read from its archive file.
export function mergeEntries(entries: EntryRow[]): MessageRow[] {
  const messages = new Map<number, MessageRow>();
  for (const e of entries) {
    if (e.kind === "message") {
      messages.set(e.n, {
        agentIdentity: e.agentIdentity ?? null, thread: e.thread, n: e.n, ts: e.ts ?? "", authorKind: e.authorKind,
        author: e.author, text: e.text ?? "", attachments: e.attachments, quotes: e.quotes, declared: e.declared,
        client: e.client, createdAt: e.at, editedAt: null, ...(e.letter !== undefined ? { letter: e.letter } : {}),
      });
    } else {
      const m = e.target === null ? undefined : messages.get(e.target);
      if (m) {
        m.text = e.text ?? "";
        m.attachments = e.attachments;
        m.quotes = e.quotes;
        m.editedAt = e.at;
      }
    }
  }
  return [...messages.values()].sort((a, b) => a.n - b.n);
}

/// The first `n` characters (Rust's `chars().take(n)`: code points, not UTF-16 units).
export function takeChars(text: string, n: number): string {
  let out = "";
  let count = 0;
  for (const c of text) {
    if (count++ >= n) break;
    out += c;
  }
  return out;
}

/// Rust's ordering of String keys (a BTreeMap's): by their UTF-8 bytes.
export const byBytes = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/// The jobs running now, the latest first, by the index on their state (schema.ts jobs_up): the main thread's and the
/// readers' (who keeps watch).
export const JOBS_RUNNING = "SELECT * FROM jobs WHERE state = 'running' ORDER BY started_at DESC";

/// A session's jobs, the latest first, by the index on their session (schema.ts jobs_by_session): the main thread's and
/// the readers'.
export const SESSION_JOBS = "SELECT * FROM jobs WHERE session_key = ? ORDER BY started_at DESC";

/// The session that went on with a runtime's session (`?1`, `?2`: its current one, or one it ran in before), the latest
/// active first: by the indexes on them (schema.ts sessions_by_runtime_id, runtime_sessions_by_id), not by asking every
/// session in turn which it ran in.
export const SESSION_OF_RUNTIME = `SELECT key FROM (
    SELECT key, last_active_at FROM sessions WHERE runtime_session_id = ?2 AND runtime = ?1
    UNION ALL SELECT s.key, s.last_active_at FROM runtime_sessions r JOIN sessions s ON s.key = r.session_key WHERE r.id = ?2 AND s.runtime = ?1
  ) ORDER BY last_active_at DESC LIMIT 1`;

/// What each list of chats asks of the cards answered lately (answersSince, the main thread's and the readers'): the
/// latest card, or post with options, before a person's message (schema.ts addClientColumn's entries_cards and
/// entries_options), and the cards closed since (closed_cards_at).
export const CARD_BEFORE = "SELECT max(n) AS n FROM entries WHERE thread = ? AND n < ? AND kind = 'message' AND card IS NOT NULL";
export const OPTIONS_BEFORE = "SELECT max(n) AS n FROM entries WHERE thread = ? AND n < ? AND kind = 'message' AND options IS NOT NULL";
export const CLOSED_SINCE = "SELECT thread, n, viewer, at FROM closed_cards WHERE at >= ?";
/// A thread's people's messages since `?2` (the items of a sidebar a change touched), by schema.ts entries_people_since.
export const SAID_SINCE = "SELECT thread, n FROM entries WHERE thread = ? AND author_kind = 'person' AND kind = 'message' AND at >= ?";

/// The usage page's calls are kept added up by this much time (schema.ts USAGE_QUARTERS): a quarter of an hour, which
/// every time zone's offset is a whole number of.
export const QUARTER_MS = 900_000;

/// A context falling under half of what the call before sent (at least this much), on the same account and model, was
/// compacted (sessions/pool.ts; what schema.ts USAGE_COMPACTIONS keeps).
export const COMPACTED_FROM = 50_000;

/// Who wrote in a thread, each with when they first did: as the database keeps them (schema.ts LIST_STATE
/// thread_people), each's first message's time.
export const PEOPLE_AT = "SELECT p.author, e.at FROM thread_people p JOIN entries e ON e.thread = p.thread AND e.n = p.first_n WHERE p.thread = ?";
