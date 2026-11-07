// What a program granted data outflow reads, in the shape of its version (`/v1`): written out
// field by field here, so that what the station keeps changing never changes what such a program is answered. The
// chats of one workspace of the station's (its home one, unless another station of a workspace it joined asks),
// a message only when asked for.
import type { Json, Store } from "./store.ts";
import * as store from "./store.ts";
import { ending, sees } from "../store/rows.ts";
import { outflowChatIndexReady, outflowChatScopes } from "../store/outflow-index.ts";
import { titleOf } from "./views.ts";
import { slackCreator } from "./slack-known.ts";
import { usage } from "./usage.ts";
import type { Lang } from "../ops/i18n.ts";

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
  const read = usage(s, lang, BigInt(from), BigInt(to), BigInt(tz), false, of, false, { remoteRuns: false }) as Json;
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
/// latest activity, whether it is archived, and its agents' runtimes and models. With `page`, at most its `limit`,
/// `more` when there are more and `next` to ask for them with; without, all of them.
export function outflowChats(s: Store, since: number, of: Of = HOME, page: ChatsPage | null = null): Json {
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
    chats.push({
      thread: thread.id,
      surface: thread.surface === store.STILLFAIL_SURFACE ? "stillfail" : thread.surface,
      title: titleOf(thread, store.firstText(s, thread.id), null),
      state: state(latest),
      creator: creator === null ? null : { ref: creator, ...person(s, creator) },
      createdAt: thread.createdAt,
      lastActiveAt,
      archived: thread.hiddenAt !== null,
      agents: members.map((m) => ({ runtime: sessions.get(m.session)!.runtime, model: sessions.get(m.session)!.model })),
    });
  }
  if (page === null) return { since, chats };
  const last = chats.at(-1);
  return { since, chats, more, next: more && last ? `${last.lastActiveAt}.${last.thread}` : null };
}

/// Which chat a program names for its messages: its `thread` (as `chats` and `usage` say it), a `session` of it (as
/// `usage` rows name it), or a chat app's address (`channel` and `ts`). Null when none of them is a chat here.
export function outflowThread(s: Store, by: { thread?: number | null; session?: string | null; channel?: string | null; ts?: string | null }): number | null {
  if (typeof by.thread === "number" && Number.isSafeInteger(by.thread)) return by.thread;
  if (typeof by.session === "string" && by.session !== "") return store.threadOfSession(s, by.session);
  if (typeof by.channel === "string" && by.channel !== "" && typeof by.ts === "string" && by.ts !== "") return store.threadAt(s, by.channel, by.ts);
  return null;
}

/// v1 `messages`: a chat's messages after its message `after` (its `n`), at most `limit`, oldest first: each one's
/// `n`, what it is (`message`, `edit`: a later wording of message `target`), who wrote it (`person`, `agent`, and
/// their reference), its words and when; `last`, the chat's latest `n`, and `more` when there are more after these.
/// Null for a chat that is not the workspace's.
export function outflowMessages(s: Store, thread: number, after: number, limit: number, of: Of = HOME): Json {
  if (store.getThread(s, thread) === null || !store.seesThread(s, of, thread)) return null;
  const entries = store.entriesAfter(s, thread, BigInt(after), limit + 1);
  const page = entries.slice(0, limit);
  return {
    thread,
    messages: page.map((e) => ({
      n: e.n, kind: e.kind, target: e.target, authorKind: e.authorKind, author: e.author, text: e.text, at: e.at,
    })),
    last: store.lastEntry(s, thread),
    more: entries.length > page.length,
  };
}
