// What the agents spent, as the usage page reads it (GET /usage): admin/views.rs `usage` over usage.rs `summary`,
// `price_table`, `price`, `cost` and store/usage.rs, with the same JSON field for field.
//
// The counting itself (src/usage/counter.ts, usage.rs `Usage::read`: the transcripts read into the `usage` table) is
// the running station's, not a read: what was counted is read here as it is in the database. `reading` is what the
// counter has in its memory (`readingAll`), given by the asker; not given, it is true (nothing read yet).
import { knownChannel, slackCreator } from "./slack-known.ts";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { type Lang, tr } from "../ops/i18n.ts";
import { type Json, STILLFAIL_SURFACE, type Store, type UsageGroup, decisionCards, remoteRunCount, remoteRunsReady, remoteRunsSince, seenBy, threadsByPlace, sessionThreads, usageByDay, usageGroups, usageSince, usageThreads } from "./store.ts";
import { type InWorkspace, sees } from "../store/rows.ts";
import { titleOf } from "./views.ts";
import { profileRuntimes } from "../agents/profiles.ts";
import { facts } from "../accounts/catalog.ts";
import { log } from "../ops/log.ts";
import type { ContextCall } from "../store/usage.ts";
import { key as modelKey } from "../../../client/core-ts/src/shapes/model.ts";

// ── prices (usage.rs) ──

/// A model's API prices, in dollars per million tokens. Writing to the cache costs 1.25× input for five minutes, 2× for
/// an hour; fast mode doubles all of it.
type Price = { input: number; output: number; cacheRead: number };

/// Standard short-context API list prices, for a model the model catalog (accounts/catalog.ts) has no price for, or
/// before it has said anything. Longer names first.
const PRICES: [string, Price][] = [
  ["gpt-6-astra", { input: 10.0, output: 50.0, cacheRead: 1.0 }],
  ["gpt-6.1-sol", { input: 2.0, output: 10.0, cacheRead: 0.1 }],
  // OpenAI's standard API prices: https://developers.openai.com/api/docs/models/gpt-6.1-terra (2026-11-01).
  ["gpt-6.1-terra", { input: 1.0, output: 5.0, cacheRead: 0.05 }],
  ["gpt-6-sol", { input: 2.0, output: 10.0, cacheRead: 0.2 }],
  ["gpt-6-luna", { input: 0.1, output: 0.5, cacheRead: 0.01 }],
  ["gpt-5.6-sol", { input: 4.0, output: 20.0, cacheRead: 0.4 }],
  ["claude-fable-5-1", { input: 10.0, output: 50.0, cacheRead: 0.25 }],
  ["claude-mythos-5-1", { input: 10.0, output: 50.0, cacheRead: 0.25 }],
  ["claude-fable-5", { input: 10.0, output: 50.0, cacheRead: 1.0 }],
  ["claude-mythos-5", { input: 10.0, output: 50.0, cacheRead: 1.0 }],
  ["claude-opus-5-5", { input: 4.0, output: 20.0, cacheRead: 0.2 }],
  ["claude-opus-5", { input: 5.0, output: 25.0, cacheRead: 0.5 }],
  ["claude-opus-4-8", { input: 5.0, output: 25.0, cacheRead: 0.5 }],
  ["claude-opus-4-7", { input: 5.0, output: 25.0, cacheRead: 0.5 }],
  ["claude-opus-4-6", { input: 5.0, output: 25.0, cacheRead: 0.5 }],
  ["claude-opus-4-5", { input: 5.0, output: 25.0, cacheRead: 0.5 }],
  ["claude-sonnet-5-5", { input: 2.0, output: 10.0, cacheRead: 0.1 }],
  ["claude-sonnet-5", { input: 2.0, output: 10.0, cacheRead: 0.2 }],
  ["claude-sonnet-4-6", { input: 3.0, output: 15.0, cacheRead: 0.3 }],
  ["claude-sonnet-4-5", { input: 3.0, output: 15.0, cacheRead: 0.3 }],
  ["claude-haiku-4-5", { input: 1.0, output: 5.0, cacheRead: 0.1 }],
];

/// price_table: the very same prices `cost` uses, for inspecting a station's calculation from the usage page: those of the
/// station's own table and of the `models` its rows name.
export function priceTable(lang: Lang, models: (string | null)[] = []): Json {
  const keys = [...new Set([...PRICES.map(([model]) => model), ...models.flatMap((m) => (m === null ? [] : [modelKey(m).split("[")[0]!]))])];
  return {
    note: tr(lang, "station.usage.priceNote"),
    rows: keys.flatMap((model) => {
      const p = price(model);
      if (p === null) return [];
      return [{
        model, input: p.input, cacheRead: p.cacheRead,
        cacheWrite: model.startsWith("claude-") ? p.input * 1.25 : null,
        cacheWriteLong: model.startsWith("claude-") ? p.input * 2.0 : null, output: p.output,
      }];
    }),
  };
}

/// What a model is, however it is spelled (the core's, client/core-ts/src/shapes/model.ts `key`).
export { modelKey };


/// price: a model's prices, however a profile spells it (anthropic/claude-opus-5-5, claude-opus-5-5[1m]): the model
/// catalog's, else the station's own table's; none for a model without a list price in either.
export function price(model: string): Price | null {
  const told = facts(model)?.cost;
  if (told !== undefined) return { input: told.input, output: told.output, cacheRead: told.cacheRead ?? told.input };
  const name = modelKey(model);
  return PRICES.find(([prefix]) => name === prefix || (name.startsWith(prefix) && name.slice(prefix.length).startsWith("[")))?.[1] ?? null;
}

/// cost: what a day's calls of one model would cost at its API prices, in dollars (in the Rust's order of operations).
export function cost(g: UsageGroup): number | null {
  if (g.model === null) return null;
  const p = price(g.model);
  if (p === null) return null;
  const tokens = g.input * p.input + g.cacheWrite * p.input * 1.25 + g.cacheWriteLong * p.input * 2.0 + g.cacheRead * p.cacheRead + g.output * p.output;
  return (tokens / 1e6) * (g.fast ? 2.0 : 1.0);
}

/// A session's calls as counted, added up by model (store `usageOfSession`), put together for its execution details:
/// the tokens as a chat shows them (input with what was read from and written to the cache) and what they would cost,
/// those of a model without a price apart.
export function sessionUsage(groups: UsageGroup[]): Counted {
  const out = { modelCalls: 0, inputTokens: 0, cachedTokens: 0, outputTokens: 0, cost: 0, unpricedCalls: 0 };
  for (const g of groups) {
    out.modelCalls += g.calls;
    out.inputTokens += g.input + g.cacheRead + g.cacheWrite + g.cacheWriteLong;
    out.cachedTokens += g.cacheRead;
    out.outputTokens += g.output;
    const c = cost(g);
    if (c === null) out.unpricedCalls += g.calls;
    else out.cost += c;
  }
  return out;
}

/// A session's calls added up (`sessionUsage`).
export type Counted = { modelCalls: number; inputTokens: number; cachedTokens: number; outputTokens: number; cost: number; unpricedCalls: number };

/// What a session's calls used, as its chat shows it while it works and at rest (the clients' TranscriptUsage): its
/// calls as the usage counter recorded them, added up, with what they would cost (`sessionUsage`: the same count as the
/// usage page's), and of its last main-thread call the model, the context it left and the model's window, where told;
/// when it was made and how long what it left in the cache is kept there (`cacheMs`, where its runtime tells what it
/// wrote: Claude's), and what sending its context again once that is over would cost (`rereadCost`, dollars: all of it
/// written to the cache again, where its model has a price).
export type SessionUsage = Counted & {
  model: string | null; contextTokens?: number; contextWindow: number | null; lastCallAt?: number; cacheMs?: number; rereadCost?: number;
};

/// A session's usage before a call of it is recorded.
export const noUsage = (): SessionUsage => ({ modelCalls: 0, inputTokens: 0, cachedTokens: 0, outputTokens: 0, cost: 0, unpricedCalls: 0, model: null, contextWindow: null });

/// What usage reads of a session's calls (store.ts `usageOfSession`, `lastContexts`, `conversationSince`).
type SessionCalls = {
  usageOfSession(session: string): UsageGroup[];
  lastContexts(session: string, limit: number): ContextCall[];
  conversationSince(session: string): number | null;
};

/// How long a prompt cache keeps what was written to it: five minutes, or an hour where it was asked to.
const CACHE_SHORT_MS = 5 * 60_000;
const CACHE_LONG_MS = 60 * 60_000;

/// The calls looked back on for what was last written to the cache (one may write nothing: all of it read).
const CACHE_CALLS = 5;

/// A session's usage now (SessionUsage), from what is recorded of its calls; none before one is. Where its context
/// stands (what it holds, when its cache is over, what reading it again costs) is of the conversation it goes on with
/// (store.ts `conversationSince`): none once its context is cleared, until that conversation's first call.
export function usageNow(s: SessionCalls, key: string): SessionUsage | null {
  const counted = sessionUsage(s.usageOfSession(key));
  if (counted.modelCalls === 0) return null;
  const all = s.lastContexts(key, CACHE_CALLS);
  const out: SessionUsage = { ...counted, model: all.at(-1)?.model ?? null, contextWindow: all.at(-1)?.window ?? null };
  const since = s.conversationSince(key);
  const calls = since === null ? [] : all.filter((c) => c.at >= since);
  const last = calls.at(-1);
  if (last === undefined) return out;
  if (last.context !== null) out.contextTokens = last.context;
  out.lastCallAt = last.at;
  // A read keeps it for as long again as it was written for: as the latest write asked.
  const wrote = calls.findLast((c) => c.cacheWrite + c.cacheWriteLong > 0);
  if (wrote === undefined) return out;
  const long = wrote.cacheWriteLong > 0;
  out.cacheMs = long ? CACHE_LONG_MS : CACHE_SHORT_MS;
  const p = last.model === null ? null : price(last.model);
  if (p !== null && last.context !== null) out.rereadCost = ((last.context * p.input * (long ? 2.0 : 1.25)) / 1e6) * (last.fast ? 2.0 : 1.0);
  return out;
}

/// Usage::summary: every day's calls from `from` until `to`, by thread, person, profile and model (UsageRow).
function summary(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint): Json[] {
  return usageGroups(s, from, to, utcOffsetMin).map((g) => ({
    day: g.day, session: g.session, thread: g.thread, person: g.person, profile: g.profile, runtime: g.runtime, model: g.model,
    calls: g.calls, input: g.input, cacheRead: g.cacheRead, cacheWrite: g.cacheWrite + g.cacheWriteLong, output: g.output, cost: cost(g),
  }));
}

// ── the config's profiles (config.rs parse_config, what usage shows of them) ──

/// config.rs parse_config, the profiles' ids, names and runtimes: a name is trimmed (else the id); the runtime is the
/// first the account runs (runtimes_for), Claude's in name for one that runs neither. No config: none.
export function configProfiles(dataDir: string): Record<string, Json> {
  const out: Record<string, Json> = {};
  let raw: Json;
  try {
    raw = JSON.parse(readFileSync(join(dataDir, "config.json"), "utf8"));
  } catch {
    return out;
  }
  for (const p of Array.isArray(raw?.profiles) ? raw.profiles : []) {
    if (typeof p?.id !== "string") continue;
    const runtimes = profileRuntimes({ id: p.id, home: "", runtime: p.runtime, access: p.access });
    const name = typeof p.name === "string" && p.name.trim() !== "" ? p.name.trim() : p.id;
    out[p.id] = { name, runtime: runtimes[0] ?? "claude" };
  }
  return out;
}

// ── people (views.rs `creator`, as views.ts has it) ──

/// A creator reference in words. No Slack connection knows anyone: a Slack user goes by their id, with no email.
function creator(s: Store, lang: Lang, reference: string): Json {
  if (reference === "local") return { id: "local", name: tr(lang, "station.creator.localPage"), email: null, via: "local" };
  const slack = slackCreator(s, reference);
  if (slack !== null) return slack;
  return { id: reference, name: s.names.get(reference) ?? reference, email: reference, via: "cloud" };
}

/// Rust's String order (bytes of UTF-8), for a BTreeSet's.
const byBytes = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/// admin/views.rs `usage`: what the agents spent from `from` until `to` (ms), by day in the asker's time zone
/// (`utcOffsetMin`), with the threads, people and profiles the rows name. `from`/`to` are i64s, written as such.
/// `reading`: whether the counter is still reading everything for the first time (UsageCounter.readingAll). `viewer`:
/// only the calls of their workspace's chats (docs/multi-workspace.md; those of sessions gone, the home one's); all of
/// them for a read made for no one.
export function usage(s: Store, lang: Lang, from: bigint, to: bigint, utcOffsetMin: bigint, reading = true, viewer: InWorkspace | null = null, history = false, options: { remoteRuns?: boolean } = {}): Json {
  // A not-yet-complete remote summary is retried once it is ready; do not do the other work twice in the meantime.
  const includeRemoteRuns = options.remoteRuns !== false;
  if (includeRemoteRuns || history) remoteRunsReady(s);
  // Keep the stages of a slow read: a reader has only one request at a time, and a slow aggregate can hold up other
  // reads. Only durations are logged, never the request's arguments or the rows it reads.
  const started = performance.now();
  let last = started;
  const stages: Record<string, number> = {};
  const mark = (stage: string) => {
    const now = performance.now();
    stages[stage] = Math.round(now - last);
    last = now;
  };
  const groups = summary(s, from, to, utcOffsetMin);
  mark("summary");
  const seen = seenBy(s, viewer, groups.map((r) => r.session));
  const rows = groups.filter((r) => seen(r.session));
  mark("visibility");
  const wanted = [...new Set(rows.map((r) => r.thread).filter((t): t is number => t !== null))];
  const threads: Record<string, Json> = {};
  for (const [t, first] of usageThreads(s, wanted)) {
    // A Slack channel's name, as far as known (`known_channel`).
    const title = titleOf(t, first, t.surface === STILLFAIL_SURFACE ? null : knownChannel(s, threadConnect(s, t.id), t.channel));
    threads[String(t.id)] = { title, surface: t.surface, home: t.home, archived: t.hiddenAt !== null };
  }
  mark("threads");
  const refs = [...new Set(rows.map((r) => r.person).filter((p): p is string => p !== null))].sort(byBytes);
  const people: Record<string, Json> = {};
  for (const r of refs) people[r] = creator(s, lang, r);
  mark("people");
  const i64 = (n: bigint) => (JSON as any).rawJSON(String(n));
  const since = usageSince(s);
  const prices = priceTable(lang, rows.map((r) => r.model));
  const profiles = configProfiles(s.dataDir);
  const remoteRuns = includeRemoteRuns ? remoteRunsSince(s, from, viewer) : [];
  mark("details");
  const answer = {
    from: i64(from),
    to: i64(to),
    since,
    reading,
    prices,
    rows,
    threads,
    people,
    profiles,
    // the tasks the viewer's workspace's chats on other stations ran here since `from` (the card's 跨设备执行): the
    // workspace their key names (`remote:<workspace>:…`)
    remoteRuns,
    ...(history ? { history: usageHistory(s, utcOffsetMin, viewer, mark) } : {}),
  };
  mark("other");
  const ms = Math.round(performance.now() - started);
  if (ms >= 2_000) log.warn("readers", "a usage read's stages", { ms, ...stages });
  return answer;
}

/// What the viewer's chats did on this station since it began counting (the usage page's summary): the tokens by day
/// in the asker's time zone, runtime and model (the year, as Codex's usage summary has it); the chats of each place
/// (still.fail's, Slack, Feishu) and how many were archived; the tasks other stations' chats ran here (one device's chat
/// working on another); the decision cards asked and those answered by an option pressed. GET /usage?history=1.
export function usageHistory(s: Store, utcOffsetMin: bigint, viewer: InWorkspace | null, mark: (stage: string) => void = () => {}): Json {
  mark("historyVisibility");
  const days = new Map<string, { day: string; runtime: string; model: string | null; tokens: number; calls: number }>();
  for (const r of usageByDay(s, utcOffsetMin, viewer)) {
    const key = `${r.day}\n${r.runtime}\n${r.model ?? ""}`;
    const d = days.get(key) ?? { day: r.day, runtime: r.runtime, model: r.model, tokens: 0, calls: 0 };
    d.tokens += r.tokens;
    d.calls += r.calls;
    days.set(key, d);
  }
  mark("historyDays");
  // the chats of each place (still.fail's own, a Slack workspace's, a Feishu one's), and those archived
  const places: Record<string, number> = {};
  let archived = 0;
  for (const t of threadsByPlace(s, viewer)) {
    const place = t.surface.split(":")[0] ?? t.surface;
    places[place] = (places[place] ?? 0) + 1;
    if (t.archived) archived++;
  }
  mark("historyPlaces");
  // the tasks the viewer's chats on other stations ran here, as long as they are kept (remote_runs: 90 days)
  const remoteRuns = remoteRunCount(s, viewer);
  mark("historyRemoteRuns");
  // the decision cards the viewer's chats were asked with, and those answered by an option pressed
  const cards = decisionCards(s, viewer);
  mark("historyCards");
  return {
    days: [...days.values()].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0)),
    cards: cards.length,
    picked: cards.filter((c) => c.picked).length,
    places,
    archived,
    remoteRuns,
  };
}

/// The chats of the resources page (GET /resources): each session's latest thread and its title; null for one `viewer` does
/// not see (another workspace's).
export function resourceChats(s: Store, sessions: string[], viewer: InWorkspace | null): Record<string, Json> {
  // A resource snapshot names a few running chats, not the station's entire history. Check each one's workspace by
  // its key rather than loading every session for each snapshot (which is refreshed repeatedly).
  const workspace = viewer === null ? null : s.db.prepare("SELECT ws FROM sessions WHERE key = ?");
  const out: Record<string, Json> = {};
  for (const key of sessions) {
    const ws = workspace?.get(key) as { ws: string | null } | undefined;
    if (viewer !== null && !sees(viewer, ws?.ws ?? null)) {
      out[key] = null;
      continue;
    }
    const thread = sessionThreads(s, key)[0] ?? null;
    const [, first] = thread !== null ? (usageThreads(s, [thread.id])[0] ?? [thread, null]) : [null, null];
    const title = thread !== null ? titleOf(thread, first, thread.surface === STILLFAIL_SURFACE ? null : knownChannel(s, threadConnect(s, thread.id), thread.channel)) : null;
    out[key] = { thread: thread?.id ?? null, title };
  }
  return out;
}

/// The connect a Slack thread came in through: the first of its sessions' that is not the station's own.
function threadConnect(s: Store, thread: number): string | null {
  const row = s.db.prepare("SELECT connect FROM thread_sessions WHERE thread = ? AND connect != 'ember' ORDER BY joined_at, rowid LIMIT 1").get(thread) as { connect: string } | undefined;
  return row?.connect ?? null;
}
