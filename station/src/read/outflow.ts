// What a program granted data outflow reads (docs/data-outflow.md), in the shape of its version (`/v1`): written out
// field by field here, so that what the station keeps changing never changes what such a program is answered. The
// station's home workspace's chats only, never a message.
import type { Json, Store } from "./store.ts";
import * as store from "./store.ts";
import { ending, sees } from "../store/rows.ts";
import { chatTitle } from "./views.ts";
import { slackCreator } from "./slack-known.ts";
import { usage } from "./usage.ts";
import type { Lang } from "../ops/i18n.ts";

/// The home workspace, as `sees` takes a viewer: its chats are those of no other workspace.
const HOME = { workspace: "\u0000home", home: true };

/// Who a person reference is, as far as known: their email.
function person(s: Store, ref: string): Json {
  const slack = slackCreator(s, ref);
  if (slack !== null) return { email: slack.email, via: "slack" };
  if (ref === "local") return { email: null, via: "local" };
  return { email: ref, via: "cloud" };
}

/// v1 `usage`: the model calls from `from` until `to` (ms), added up by day in UTC+`tz` minutes, chat, session, person,
/// account and model, with what they cost at list prices (null for a model without one); `people` the rows' persons.
export function outflowUsage(s: Store, lang: Lang, from: number, to: number, tz: number): Json {
  const read = usage(s, lang, BigInt(from), BigInt(to), BigInt(tz), false, HOME) as Json;
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

/// v1 `chats`: the chats with something new since `since` (ms): each one's thread (what `usage` rows name), where it
/// is (`stillfail`, `slack`, `feishu`), title, how it stands, who started it, when, its latest activity, whether it is
/// archived, and its agents' runtimes and models.
export function outflowChats(s: Store, since: number): Json {
  const sessions = new Map(store.listSessions(s).filter((x) => sees(HOME, x.ws ?? null)).map((x) => [x.key, x]));
  const stats = store.sessionStats(s, [...sessions.keys()]);
  const chats: Json[] = [];
  for (const t of store.listThreads(s, "", null, null)) {
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
  chats.sort((a, b) => b.lastActiveAt - a.lastActiveAt);
  return { since, chats };
}
