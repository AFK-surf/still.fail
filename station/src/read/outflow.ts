// The statistics a Comma connect sends of the workspace (comma/stats.ts), as one station reads them of its own: what
// its agents spent and the chats they worked in (with what each asks of whom now, its link in the app, and whether a
// Comma Router wrote in it), written out field by field here, so that what the station keeps changing never changes
// what another station of another version is answered (`outflow.read`, comma/peer.ts, named so as stations of every
// version answer it). The chats of one workspace of the station's (its home one, unless another station of a workspace
// it joined asks).
import type { Json, Store } from "./store.ts";
import * as store from "./store.ts";
import { ending, sees } from "../store/rows.ts";
import { outflowChatIndexReady, outflowChatScopes } from "../store/outflow-index.ts";
import { titleNeedsFirstText, titleOf } from "./views.ts";
import { slackCreator } from "./slack-known.ts";
import { usage } from "./usage.ts";
import type { Lang } from "../ops/i18n.ts";
import { type PageBase, sessionPage } from "../sessions/page.ts";

/// Which workspace's chats are read, as `sees` takes a viewer.
export type Of = { workspace: string; home: boolean };

/// The home workspace: its chats are those of no other workspace.
export const HOME: Of = { workspace: "\u0000home", home: true };

/// Who a person reference is, as far as known: their name and email, and where they were heard (`slack`, `feishu`,
/// `cloud`, `local`). A chat app's person whose name is not known has none here, not their id.
function person(s: Store, ref: string): Json {
  const chat = slackCreator(s, ref);
  if (chat !== null) return { name: ref.endsWith(`:${chat.name}`) ? null : chat.name, email: chat.email, via: chat.via };
  if (ref === "local") return { name: null, email: null, via: "local" };
  return { name: null, email: ref, via: "cloud" };
}

/// v1 `usage`: the model calls from `from` until `to` (ms), added up by day in UTC+`tz` minutes, chat, session, person,
/// account and model, with what they cost at list prices (null for a model without one); `people` the rows' persons.
export function outflowUsage(s: Store, lang: Lang, from: number, to: number, tz: number, of: Of = HOME): Json {
  // The export has no remote-task field, so it need not wait for or read those statistics.
  const read = usage(s, lang, BigInt(from), BigInt(to), BigInt(tz), false, of, false, { remoteRuns: false, metadata: false }) as Json;
  const rows = (read.rows as Json[]).map((r) => ({
    day: r.day, thread: r.thread, session: r.session, person: r.person, account: r.profile, runtime: r.runtime, model: r.model,
    calls: r.calls, input: r.input, cacheRead: r.cacheRead, cacheWrite: r.cacheWrite, output: r.output, cost: r.cost,
  }));
  const people: Record<string, Json> = {};
  for (const r of rows) if (r.person !== null && !(r.person in people)) people[r.person] = person(s, r.person);
  return { from, to, tz, since: read.since ?? null, rows, people };
}

/// How a chat stands, by its agents' latest turn: `working` while one runs, else how it said it ended (`all_done`,
/// `need_human`, `waiting`), `ended` when it said nothing.
function state(turn: Json | null): string | null {
  if (turn === null) return null;
  if (turn.outcome === null || turn.outcome === undefined) return "working";
  if (typeof turn.declared !== "string") return "ended";
  const said = ending(turn.declared);
  return said === "need_help" ? "need_human" : said;
}

/// A card's assignee, the email of who decides it, as the card on message `n` of `thread` names one: by its key.
function assigneeAt(s: Store, thread: number, n: number): string | null {
  const r = s.db.prepare("SELECT card FROM entries WHERE thread = ? AND n = ? AND kind = 'message'").get(thread, n) as { card: string | null } | undefined;
  if (typeof r?.card !== "string") return null;
  try {
    const assignee = JSON.parse(r.card)?.assignee;
    return typeof assignee === "string" && assignee.trim() !== "" ? assignee.trim().toLowerCase() : null;
  } catch {
    return null;
  }
}

/// Whether a chat's latest message (that is not a letter) is one its creator has not read: past where they read it
/// to in the app, and not theirs. Each by its key (thread_state, the message, their read mark).
function unreadBy(s: Store, thread: number, ref: string, email: string): boolean {
  const said = s.db.prepare(`SELECT e.n, e.author_kind, e.author FROM thread_state t JOIN entries e ON e.thread = t.thread AND e.n = t.said_n
    WHERE t.thread = ?`).get(thread) as { n: number; author_kind: string; author: string } | undefined;
  if (said === undefined) return false;
  if (said.author_kind === "person" && (said.author === ref || said.author.toLowerCase() === email)) return false;
  const read = s.db.prepare("SELECT MAX(n) AS n FROM reads WHERE viewer IN (?1, lower(?1)) AND thread = ?2").get(email, thread) as { n: number | null };
  return said.n > (read.n ?? 0);
}

/// What a chat asks of someone now, by its agents' latest turn; null when nothing (and for an archived chat):
/// - `need`: it ended needing a person (need_human). For whoever decides the card the need is about (its assignee),
///   else whoever started the chat; its words the need.
/// - `done`: it ended all done and whoever started it has not read its latest message in the app (a still.fail chat:
///   a Slack or Feishu thread is read there, which the station does not know). Its words what was done.
/// - `failed`: it failed without saying how it ended, for whoever started it; its words the failure's first line.
/// `waitsFor`: the emails of who it is for, as far as known.
function attentionOf(s: Store, thread: store.ThreadRow, latest: Json | null, creator: string | null, email: string | null): Json | null {
  if (latest === null || thread.hiddenAt !== null) return null;
  const said = state(latest);
  const mine = email === null ? [] : [email.toLowerCase()];
  const words = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v.trim() : null);
  if (said === "need_human") {
    const about = latest.about;
    const assignee = about !== undefined && about !== null ? assigneeAt(s, about.thread, about.seq) : null;
    return { kind: "need", waitsFor: assignee !== null ? [assignee] : mine, note: words(latest.need) };
  }
  if (said === "all_done") {
    if (email === null || creator === null || thread.surface !== store.STILLFAIL_SURFACE) return null;
    return unreadBy(s, thread.id, creator, email.toLowerCase()) ? { kind: "done", waitsFor: mine, note: words(latest.need) } : null;
  }
  if (latest.outcome === "failed" && latest.declared === null) {
    const detail = words(latest.detail);
    return { kind: "failed", waitsFor: mine, note: detail === null ? null : words(detail.split("\n")[0]) };
  }
  return null;
}

/// Whether a Comma Router ever wrote in still.fail chat `thread`, by one keyed range of who wrote in it (thread_people,
/// kept by the entries' trigger, so of all its history and gone only with its entries). Its writes are the only
/// person messages of a still.fail chat named `slack:<connect>:<requester>` (comma/chats.ts routerSaysOnce); people
/// write there as their email (lifecycle.ts `say`), and the Router writes in no other chat.
export const ROUTER_WROTE = "SELECT 1 FROM thread_people WHERE thread = ? AND author >= 'slack:' AND author < 'slack;' LIMIT 1";
const routerWrote = (s: Store, thread: store.ThreadRow): boolean =>
  thread.surface === store.STILLFAIL_SURFACE && s.db.prepare(ROUTER_WROTE).get(thread.id) !== undefined;

/// A page of chats: at most `limit`, those after `before` (the `next` of the page before).
export type ChatsPage = { limit: number; before: string | null };
export const OUTFLOW_CHATS_PENDING = "outflow chat order is still being prepared";

/// A scope's next chats: the compound seek starts at the cursor, including when many chats share a timestamp.
export const OUTFLOW_CHAT_PAGE = `SELECT thread, at FROM outflow_chat_order INDEXED BY outflow_chat_scope_order
  WHERE scope = ?1 AND dirty = 0 AND at >= ?2 AND (at, thread) < (?3, ?4) ORDER BY at DESC, thread DESC LIMIT ?5`;
const OUTFLOW_CHAT_FIRST = `SELECT thread, at FROM outflow_chat_order INDEXED BY outflow_chat_scope_order
  WHERE scope = ?1 AND dirty = 0 AND at >= ?2 ORDER BY at DESC, thread DESC LIMIT ?3`;

/// v1 `chats`: the chats with something new since `since` (ms), the latest active first: each one's thread (what
/// `usage` rows name), where it is (`stillfail`, `slack`, `feishu`), title, how it stands, who started it, when, its
/// latest activity, whether it is archived, and its agents' runtimes and models; what it asks of whom now
/// (`attention`, attentionOf: absent when nothing) and, given where this station's pages are (`pages`), its link in the
/// app (`url`, the page of its latest turn's session); `router: true` when a Comma Router ever wrote in it (routerWrote:
/// absent when not). With `page`, at most its `limit`, `more` when there are more and `next` to ask for them with;
/// without, all of them.
export function outflowChats(s: Store, since: number, of: Of = HOME, page: ChatsPage | null = null, pages: PageBase | null = null): Json {
  // The read and this coverage check share the reader's snapshot. A concurrent write is settled before a retry.
  if (!outflowChatIndexReady(s.db, of)) throw new Error(OUTFLOW_CHATS_PENDING);
  const [at, beforeThread] = (page?.before ?? "").split(".").map(Number);
  const cursor = page?.before != null && Number.isFinite(at) && Number.isFinite(beforeThread);
  const limit = page === null ? -1 : page.limit + 1;
  const candidates = new Map<number, { thread: number; at: number }>();
  for (const scope of outflowChatScopes(of)) {
    const rows = (cursor
      ? s.db.prepare(OUTFLOW_CHAT_PAGE).all(scope, since, at!, beforeThread!, limit)
      : s.db.prepare(OUTFLOW_CHAT_FIRST).all(scope, since, limit)) as { thread: number; at: number }[];
    for (const row of rows) candidates.set(row.thread, row);
  }
  const ordered = [...candidates.values()].sort((a, b) => b.at - a.at || b.thread - a.thread);
  const more = page !== null && ordered.length > page.limit;
  const threads = page === null ? ordered : ordered.slice(0, page.limit);
  const sessions = new Map<string, ReturnType<typeof store.getSession>>();
  // Outflow needs no viewer's unread count, people list, letters or message bodies. A sidebar summary computes those
  // from the chat's messages, including an unread count that grows with its history.
  const listed = threads.flatMap(({ thread: id, at: lastActiveAt }) => {
    const thread = store.getThread(s, id);
    if (thread === null) return [];
    const members = store.threadSessions(s, id).filter((m) => {
      if (!sessions.has(m.session)) sessions.set(m.session, store.getSession(s, m.session));
      const session = sessions.get(m.session);
      return session !== null && session !== undefined && sees(of, session.ws ?? null);
    });
    if (members.length === 0) return [];
    return [{ thread, members, lastActiveAt }];
  });
  // Outflow only uses the latest turn. A full session summary also counts pending deliveries, which may be unbounded.
  const turnsBySession = new Map<string, ReturnType<typeof store.lastTurn>>();
  for (const { members } of listed) for (const { session } of members)
    if (!turnsBySession.has(session)) turnsBySession.set(session, store.lastTurn(s, session));
  const chats: Json[] = [];
  for (const { thread, members, lastActiveAt } of listed) {
    const turns = members.map((m) => turnsBySession.get(m.session) ?? null).filter((x): x is NonNullable<typeof x> => x !== null);
    const latest = turns.sort((a, b) => (b.startedAt ?? 0) - (a.startedAt ?? 0))[0] ?? null;
    const creator = thread.createdBy ?? sessions.get(members[0]!.session)?.createdBy ?? null;
    const who = creator === null ? null : { ref: creator, ...person(s, creator) };
    const attention = attentionOf(s, thread, latest, creator, typeof who?.email === "string" && who.email !== "" ? who.email : null);
    const lead = members.find((m) => latest !== null && turnsBySession.get(m.session) === latest)?.session ?? members[0]!.session;
    const url = pages === null ? null : sessionPage(pages, sessions.get(lead)?.ws ?? pages.workspace, lead);
    chats.push({
      thread: thread.id,
      surface: thread.surface === store.STILLFAIL_SURFACE ? "stillfail" : thread.surface,
      title: titleOf(thread, titleNeedsFirstText(thread) ? store.firstText(s, thread.id) : null, null),
      state: state(latest),
      creator: who,
      createdAt: thread.createdAt,
      lastActiveAt,
      archived: thread.hiddenAt !== null,
      agents: members.map((m) => ({ runtime: sessions.get(m.session)!.runtime, model: sessions.get(m.session)!.model })),
      ...(attention === null ? {} : { attention }),
      ...(url === null ? {} : { url }),
      ...(routerWrote(s, thread) ? { router: true } : {}),
    });
  }
  if (page === null) return { since, chats };
  const last = chats.at(-1);
  return { since, chats, more, next: more && last ? `${last.lastActiveAt}.${last.thread}` : null };
}

/// A chat's messages after its message `after` (its `n`), at most `limit`, oldest first, as the Router reads a Task
/// through a Comma connect (`task.read`): each one's `n`, what it is (`message`, `edit`: a later wording of message
/// `target`), who wrote it (`person`, `agent`, and their reference, a person's name and email as far as known), its words
/// and when; `last`, the chat's latest `n`, and `more` when there are more after these. Null for a chat that is not the
/// workspace's. A newer Router asks for messages alone; without that option old peers still receive entries and edits.
export function outflowMessages(s: Store, thread: number, after: number, limit: number, of: Of = HOME, messagesOnly = false): Json {
  if (store.getThread(s, thread) === null || !store.seesThread(s, of, thread)) return null;
  const entries = messagesOnly
    ? store.messageEntriesAfter(s, thread, BigInt(after), limit + 1)
    : store.entriesAfter(s, thread, BigInt(after), limit + 1);
  const page = entries.slice(0, limit);
  const people = new Map<string, Json>();
  const named = (ref: string) => (people.has(ref) ? people.get(ref) : people.set(ref, person(s, ref)).get(ref));
  return {
    thread,
    messages: page.map((e) => ({
      n: e.n, kind: e.kind, target: e.target, authorKind: e.authorKind, author: e.author, text: e.text, at: e.at,
      ...(e.authorKind === "person" && typeof e.author === "string" ? { person: named(e.author) } : {}),
    })),
    last: store.lastEntry(s, thread),
    more: entries.length > page.length,
    ...(messagesOnly ? { messagesOnly: true } : {}),
  };
}
