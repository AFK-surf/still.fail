// What a program granted data outflow reads (docs/data-outflow.md), in the shape of its version (`/v1`): written out
// field by field here, so that what the station keeps changing never changes what such a program is answered. The
// chats of one workspace of the station's (its home one, unless another station of a workspace it joined asks),
// a message only when asked for.
import type { Json, Store } from "./store.ts";
import * as store from "./store.ts";
import { ending, sees } from "../store/rows.ts";
import { chatTitle } from "./views.ts";
import { slackCreator } from "./slack-known.ts";
import { usage } from "./usage.ts";
import type { Lang } from "../ops/i18n.ts";

/// Which workspace's chats are read, as `sees` takes a viewer.
export type Of = { workspace: string; home: boolean };

/// The home workspace: its chats are those of no other workspace.
export const HOME: Of = { workspace: "\u0000home", home: true };

/// Who a person reference is, as far as known: their email.
function person(s: Store, ref: string): Json {
  const slack = slackCreator(s, ref);
  if (slack !== null) return { email: slack.email, via: "slack" };
  if (ref === "local") return { email: null, via: "local" };
  return { email: ref, via: "cloud" };
}

/// v1 `usage`: the model calls from `from` until `to` (ms), added up by day in UTC+`tz` minutes, chat, session, person,
/// account and model, with what they cost at list prices (null for a model without one); `people` the rows' persons.
export function outflowUsage(s: Store, lang: Lang, from: number, to: number, tz: number, of: Of = HOME): Json {
  const read = usage(s, lang, BigInt(from), BigInt(to), BigInt(tz), false, of) as Json;
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

/// v1 `chats`: the chats with something new since `since` (ms), the latest active first: each one's thread (what
/// `usage` rows name), where it is (`stillfail`, `slack`, `feishu`), title, how it stands, who started it, when, its
/// latest activity, whether it is archived, and its agents' runtimes and models. With `page`, at most its `limit`,
/// `more` when there are more and `next` to ask for them with; without, all of them.
export function outflowChats(s: Store, since: number, of: Of = HOME, page: ChatsPage | null = null): Json {
  const sessions = new Map(store.listSessions(s).filter((x) => sees(of, x.ws ?? null)).map((x) => [x.key, x]));
  // Only the workspace's threads with something new are summed up: the others cost nothing.
  const threads = store.threadsActiveSince(s, store.threadsOfSessions(s, [...sessions.keys()]), since);
  const listed = store.listThreads(s, "", null, threads);
  const stats = store.sessionStats(s, [...new Set(listed.flatMap((t) => t.sessions.map((m) => m.session)).filter((k) => sessions.has(k)))]);
  const chats: Json[] = [];
  for (const t of listed) {
    const members = t.sessions.filter((m) => sessions.has(m.session));
    if (members.length === 0) continue;
    const lastActiveAt = Math.max(t.thread.createdAt, t.lastMessage?.createdAt ?? 0);
    if (lastActiveAt < since) continue;
    const turns = members.map((m) => stats.get(m.session)?.lastTurn ?? null).filter((x): x is Json => x !== null);
    const latest = turns.sort((a, b) => (b.startedAt ?? 0) - (a.startedAt ?? 0))[0] ?? null;
    const creator = t.thread.createdBy ?? sessions.get(members[0]!.session)?.createdBy ?? null;
    chats.push({
      thread: t.thread.id,
      surface: t.thread.surface === store.STILLFAIL_SURFACE ? "stillfail" : t.thread.surface,
      title: chatTitle(t, null),
      state: state(latest),
      creator: creator === null ? null : { ref: creator, ...person(s, creator) },
      createdAt: t.thread.createdAt,
      lastActiveAt,
      archived: t.thread.hiddenAt !== null,
      agents: members.map((m) => ({ runtime: sessions.get(m.session)!.runtime, model: sessions.get(m.session)!.model })),
    });
  }
  chats.sort((a, b) => b.lastActiveAt - a.lastActiveAt || b.thread - a.thread);
  if (page === null) return { since, chats };
  const [at, thread] = (page.before ?? "").split(".").map(Number);
  const rest = page.before === null || !Number.isFinite(at) || !Number.isFinite(thread)
    ? chats
    : chats.filter((c) => c.lastActiveAt < at! || (c.lastActiveAt === at && c.thread < thread!));
  const shown = rest.slice(0, page.limit);
  const last = shown.at(-1);
  const more = rest.length > shown.length;
  return { since, chats: shown, more, next: more && last ? `${last.lastActiveAt}.${last.thread}` : null };
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
  const entries = store.entriesAfter(s, thread, BigInt(after));
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
