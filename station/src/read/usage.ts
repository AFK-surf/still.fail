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
import { type BatchedUsage, type Json, STILLFAIL_SURFACE, type Store, type UsageGroup, REMOTE_RUNS_PENDING, USAGE_CHATS_PENDING, remoteRunCount, remoteRunsSince, seenBy, sessionThreads, usageChatTotals, usageGroups, usageSince, usageThreads } from "./store.ts";
import { usageCardOutcomesComplete } from "../store/usage-chat-stats.ts";
import type { UsageSqlTimings } from "./usage-batched.ts";
import { type InWorkspace, sees } from "../store/rows.ts";
import { usageDetailSince } from "../store/usage-detail.ts";
import { hasCompactUsage } from "../store/usage-compact.ts";
import { HISTORY_AFTER, HISTORY_DAYS, HISTORY_SCOPES, HISTORY_TOTAL, hasUsageHistory, quarter, usageHistorySince } from "../store/usage-history.ts";
import { titleOf } from "./views.ts";
import { profileRuntimes } from "../agents/profiles.ts";
import { facts } from "../accounts/catalog.ts";
import { log } from "../ops/log.ts";
import type { ContextCall } from "../store/usage.ts";
import { key as modelKey, splitAgyTier } from "../../../client/core-ts/src/shapes/model.ts";
import { STILLFAIL_CONNECT } from "../store/rows.ts";

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
  ["claude-fable-5-2", { input: 8.0, output: 40.0, cacheRead: 0.2 }],
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
export { modelKey, splitAgyTier };


/// price: a model's prices, however a profile spells it (anthropic/claude-opus-5-5, claude-opus-5-5[1m],
/// gemini-4-hydrogen-high): the model catalog's, else the station's own table's; none for a model without a list price
/// in either.
export function price(model: string): Price | null {
  const told = facts(model)?.cost;
  if (told !== undefined) return { input: told.input, output: told.output, cacheRead: told.cacheRead ?? told.input };
  const name = modelKey(model);
  const listed = (candidate: string) =>
    PRICES.find(([prefix]) => candidate === prefix || (candidate.startsWith(prefix) && candidate.slice(prefix.length).startsWith("[")))?.[1] ?? null;
  const direct = listed(name);
  if (direct !== null) return direct;
  const at = name.indexOf("[");
  const bare = at >= 0 ? name.slice(0, at) : name;
  const split = splitAgyTier(bare);
  return split === null ? null : listed(at >= 0 ? `${split.model}${name.slice(at)}` : split.model);
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
  savedCompactContext?(session: string): { model: string | null; contextWindow: number | null; lastCallAt: number;
    contextTokens?: number; cacheMs?: number; rereadCost?: number } | null;
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
  if (last !== undefined) {
    if (last.context !== null) out.contextTokens = last.context;
    out.lastCallAt = last.at;
    // A read keeps it for as long again as it was written for: as the latest write asked.
    const wrote = calls.findLast((c) => c.cacheWrite + c.cacheWriteLong > 0);
    if (wrote !== undefined) {
      const long = wrote.cacheWriteLong > 0;
      out.cacheMs = long ? CACHE_LONG_MS : CACHE_SHORT_MS;
      const p = last.model === null ? null : price(last.model);
      if (p !== null && last.context !== null) out.rereadCost = ((last.context * p.input * (long ? 2.0 : 1.25)) / 1e6) * (last.fast ? 2.0 : 1.0);
    }
  }
  const saved = s.savedCompactContext?.(key) ?? null;
  const latest = all.at(-1);
  if (saved !== null && since !== null && saved.lastCallAt >= since && (latest === undefined || saved.lastCallAt > latest.at)) {
    out.model = saved.model;
    out.contextWindow = saved.contextWindow;
    out.lastCallAt = saved.lastCallAt;
    for (const name of ["contextTokens", "cacheMs", "rereadCost"] as const) {
      if (saved[name] !== undefined) out[name] = saved[name];
      else delete out[name];
    }
  }
  return out;
}

/// Usage::summary: every day's calls from `from` until `to`, by thread, person, profile and model (UsageRow).
function summary(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint, viewer: InWorkspace | null,
  queryTime: (ms: number, diagnostics: { parts?: number; candidates?: number; selectedMs?: number; selectedRestMs?: number;
    selectedCpuMs?: number; cpuMs?: number; rests?: number; restMs?: number; sql?: UsageSqlTimings }) => void,
  batched?: BatchedUsage): Json[] {
  const started = performance.now();
  const diagnostics: { parts?: number; candidates?: number; selectedMs?: number } = {};
  const groups = batched?.groups ?? usageGroups(s, from, to, utcOffsetMin, viewer, diagnostics);
  queryTime(batched?.ms ?? Math.round(performance.now() - started), batched?.diagnostics ?? diagnostics);
  return groups.map((g) => ({
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

// ── people (as views.ts has it) ──

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
/// only the calls of their workspace's chats (those of sessions gone, the home one's); all of
/// them for a read made for no one.
// A reader says once when its cache actually serves a request. Fast reads otherwise leave no trace in the slow-read
// log, so the absence of that warning alone cannot show whether the cache is used.
let reportedSummaryReuse = false;
let reportedCleanSummaryReuse = false;

export function usage(s: Store, lang: Lang, from: bigint, to: bigint, utcOffsetMin: bigint, reading = true, viewer: InWorkspace | null = null, history = false,
  options: { remoteRuns?: boolean; historyRange?: { from: bigint; to: bigint }; batched?: BatchedUsage; detailsPreparing?: boolean; metadata?: boolean } = {}): Json {
  const includeRemoteRuns = options.remoteRuns !== false;
  // A program's usage export needs the rows and their costs, but constructs its own people and does not send the
  // usage page's chat titles, price table or profile details.
  const includeMetadata = options.metadata !== false;
  // Keep the stages of a slow read: a reader has only one request at a time, and a slow aggregate can hold up other
  // reads. Only durations are logged, never the request's arguments or the rows it reads.
  const started = performance.now() - (options.batched?.ms ?? 0);
  let last = started;
  const stages: Record<string, number> = {};
  const mark = (stage: string) => {
    const now = performance.now();
    stages[stage] = Math.round(now - last);
    last = now;
  };
  let summaryParts: number | undefined;
  let summaryCandidates: number | undefined;
  let summarySqlSlowOp: string | undefined;
  const groups = options.detailsPreparing ? [] : summary(s, from, to, utcOffsetMin, viewer, (ms, diagnostics) => {
    stages.summaryQuery = ms;
    if (diagnostics.selectedMs !== undefined) stages.summarySelected = diagnostics.selectedMs;
    if (diagnostics.selectedRestMs !== undefined) stages.summarySelectedRestMs = diagnostics.selectedRestMs;
    if (diagnostics.selectedCpuMs !== undefined) stages.summarySelectedCpuMs = diagnostics.selectedCpuMs;
    if (diagnostics.cpuMs !== undefined) stages.summaryCpuMs = diagnostics.cpuMs;
    if (diagnostics.rests !== undefined) stages.summaryRests = diagnostics.rests;
    if (diagnostics.restMs !== undefined) stages.summaryRestMs = diagnostics.restMs;
    if (diagnostics.sql !== undefined) {
      stages.summarySqlJournalMs = diagnostics.sql.journal;
      stages.summarySqlChangesMs = diagnostics.sql.changes;
      stages.summarySqlPendingMs = diagnostics.sql.pending;
      stages.summarySqlSelectedMs = diagnostics.sql.selected;
      stages.summarySqlOwnerMs = diagnostics.sql.owner;
      stages.summarySqlBucketsMs = diagnostics.sql.buckets;
      stages.summarySqlSlowMs = diagnostics.sql.slowMs;
      summarySqlSlowOp = diagnostics.sql.slowOp;
    }
    summaryParts = diagnostics.parts;
    summaryCandidates = diagnostics.candidates;
  }, options.batched);
  mark("summary");
  // Compact groups have already checked each session's current workspace in the same read snapshot. Looking them
  // up again here needlessly rereads the sessions index for every usage page, including on a cold database.
  const seen = viewer === null || hasCompactUsage(s.db) ? null : seenBy(s, viewer, groups.map((r) => r.session));
  const rows = seen === null ? groups : groups.filter((r) => seen(r.session));
  mark("visibility");
  const wanted = includeMetadata ? [...new Set(rows.map((r) => r.thread).filter((t): t is number => t !== null))] : [];
  const threads: Record<string, Json> = {};
  for (const [t, first] of usageThreads(s, wanted)) {
    // A Slack channel's name, as far as known (`known_channel`).
    const title = titleOf(t, first, t.surface === STILLFAIL_SURFACE ? null : knownChannel(s, threadConnect(s, t.id), t.channel));
    threads[String(t.id)] = { title, surface: t.surface, home: t.home, archived: t.hiddenAt !== null };
  }
  mark("threads");
  const refs = includeMetadata ? [...new Set(rows.map((r) => r.person).filter((p): p is string => p !== null))].sort(byBytes) : [];
  const people: Record<string, Json> = {};
  for (const r of refs) people[r] = creator(s, lang, r);
  mark("people");
  const i64 = (n: bigint) => (JSON as any).rawJSON(String(n));
  const since = usageSince(s);
  const detailSince = includeMetadata ? usageDetailSince(s.db) : null;
  const prices = includeMetadata ? priceTable(lang, rows.map((r) => r.model)) : undefined;
  const profiles = includeMetadata ? configProfiles(s.dataDir) : undefined;
  // An older station may not have complete historical statistics. Leave the unavailable part absent so clients can
  // still show the complete details and distinguish missing history from an actual zero.
  let remoteRuns: Json | undefined = [];
  if (includeRemoteRuns) {
    try { remoteRuns = remoteRunsSince(s, from, viewer); }
    catch (error) {
      if (!(error instanceof Error) || error.message !== REMOTE_RUNS_PENDING) throw error;
      remoteRuns = undefined;
    }
  }
  const historyResult = history ? usageHistory(s, utcOffsetMin, viewer, mark, options.historyRange) : null;
  mark("details");
  const answer = {
    from: i64(from),
    to: i64(to),
    since,
    ...(detailSince !== null ? { detailSince } : {}),
    reading,
    ...(options.detailsPreparing ? { detailsPreparing: true } : {}),
    ...(includeMetadata ? { prices } : {}),
    rows,
    ...(includeMetadata ? { threads, people, profiles } : {}),
    // the tasks the viewer's workspace's chats on other stations ran here since `from` (the card's 跨设备执行): the
    // workspace their key names (`remote:<workspace>:…`)
    ...(remoteRuns !== undefined ? { remoteRuns } : {}),
    ...(historyResult !== null ? { history: historyResult } : {}),
    ...(history && historyResult === null ? { historyUnavailable: true } : {}),
  };
  mark("other");
  const ms = Math.round(performance.now() - started);
  const cleanSummaryReuse = summaryCandidates === 0 && summaryParts === 0;
  if (options.batched?.diagnostics.cache === "reused" && (!reportedSummaryReuse || (cleanSummaryReuse && !reportedCleanSummaryReuse))) {
    reportedSummaryReuse = true;
    if (cleanSummaryReuse) reportedCleanSummaryReuse = true;
    log.info("readers", "a usage read reused its summary", { ms, summaryQuery: stages.summaryQuery, summaryCandidates, summaryParts, summaryClean: cleanSummaryReuse });
  }
  if (ms >= 1_000) {
    const partialMinute = from < to && (from % 60_000n !== 0n || (to !== 9223372036854775807n && to % 60_000n !== 0n));
    log.warn("readers", "a usage read's stages", { ms, ...stages, summaryGroups: groups.length,
      ...(summarySqlSlowOp === undefined ? {} : { summarySqlSlowOp }),
      ...(options.batched === undefined ? {} : { summaryCache: options.batched.diagnostics.cache }),
      ...(summaryCandidates !== undefined ? { summaryCandidates } : {}),
      ...(summaryParts !== undefined ? { summaryParts, summaryEdges: partialMinute } : {}) });
  }
  return answer;
}

/// What the viewer's chats did on this station since it began counting (the usage page's summary): the tokens by day
/// in the asker's time zone (`utcOffsetMin`) over the page's year (`requested`, ms: its first local midnight until the
/// one after today; absent, an older client's: every day), and in all before the year's end; the chats of each place
/// (still.fail's, Slack, Feishu) and how many were archived; the tasks other stations' chats ran here (one device's
/// chat working on another); the decision cards asked and those answered by an option pressed. GET /usage?history=1.
/// The tokens are read from the history's quarters (store/usage-history.ts): those of the year's days and no more.
/// `since`: from when the station counted every call (ms; absent, from its first). Null where the history is not
/// installed yet (just after an update, until the station before has gone).
export function validHistoryRange(requested: { from: bigint; to: bigint } | undefined, utcOffsetMin: bigint): boolean {
  const day = 86_400_000n;
  return requested !== undefined && requested.from <= requested.to && requested.to - requested.from <= 370n * day
    && requested.from % 60_000n === 0n && requested.to % 60_000n === 0n
    && (requested.to + utcOffsetMin * 60_000n) % day === 0n
    && requested.to + utcOffsetMin * 60_000n >= -8_640_000_000_000_000n
    && requested.to + utcOffsetMin * 60_000n <= 8_640_000_000_000_000n;
}

export function usageHistory(s: Store, utcOffsetMin: bigint, viewer: InWorkspace | null, mark: (stage: string) => void = () => {},
  requested?: { from: bigint; to: bigint }): Json | null {
  if (!hasUsageHistory(s.db)) return null;
  const range = validHistoryRange(requested, utcOffsetMin) ? requested! : undefined;
  // Whose quarters the viewer sees (rows.ts `sees`): their workspace's, and the home one's ('') where it is theirs.
  const scopes = viewer === null ? (s.db.prepare(HISTORY_SCOPES).all() as Json[]).map((r) => String(r.scope))
    : viewer.home !== false ? [viewer.workspace, ""] : [viewer.workspace];
  const from = range === undefined ? -(2n ** 62n) : quarter(range.from);
  const to = range === undefined ? 2n ** 62n : quarter(range.to);
  const days = new Map<string, { day: string; runtime: string; model: null; tokens: number; calls: number }>();
  let tokens = 0;
  for (const scope of scopes) {
    for (const r of s.db.prepare(HISTORY_DAYS).all(scope, from, to, utcOffsetMin) as Json[]) {
      const d = days.get(r.day) ?? { day: r.day, runtime: "", model: null, tokens: 0, calls: 0 };
      d.tokens += Number(r.tokens);
      d.calls += Number(r.calls);
      days.set(r.day, d);
    }
    // In all before the year's end: the workspace's total, less what came after (a clock ahead; none, as a rule).
    if (range !== undefined) tokens += Number((s.db.prepare(HISTORY_TOTAL).get(scope) as Json)?.tokens ?? 0) - Number((s.db.prepare(HISTORY_AFTER).get(scope, to) as Json)?.tokens ?? 0);
  }
  mark("historyDays");
  const since = usageHistorySince(s.db);
  // the chats of each place (still.fail's own, a Slack workspace's, a Feishu one's), those archived and the decision
  // cards, as their own statistics hold them (none said while those are still being filled)
  let chats: ReturnType<typeof usageChatTotals> | null = null;
  try { chats = usageChatTotals(s, viewer, { allowIncompleteCards: true }); }
  catch (error) { if (!(error instanceof Error) || error.message !== USAGE_CHATS_PENDING) throw error; }
  mark("historyPlaces");
  // the tasks the viewer's chats on other stations ran here, as long as they are kept (remote_runs: 90 days)
  let remoteRuns: number | null = null;
  try { remoteRuns = remoteRunCount(s, viewer); }
  catch (error) { if (!(error instanceof Error) || error.message !== REMOTE_RUNS_PENDING) throw error; }
  mark("historyRemoteRuns");
  return {
    days: [...days.values()].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0)),
    ...(range !== undefined ? { tokens, beforeDay: new Date(Number(range.to + utcOffsetMin * 60_000n)).toISOString().slice(0, 10) } : {}),
    ...(since !== null ? { since } : {}),
    ...(chats === null || !usageCardOutcomesComplete(s.db) ? { cardsIncomplete: true } : { cards: chats.cards, picked: chats.picked }),
    ...(chats === null ? { chatsIncomplete: true, places: {} } : { places: chats.places, archived: chats.archived }),
    ...(remoteRuns === null ? {} : { remoteRuns }),
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
    const thread = sessionThreads(s, key, null, 1)[0] ?? null;
    const [, first] = thread !== null ? (usageThreads(s, [thread.id])[0] ?? [thread, null]) : [null, null];
    const title = thread !== null ? titleOf(thread, first, thread.surface === STILLFAIL_SURFACE ? null : knownChannel(s, threadConnect(s, thread.id), thread.channel)) : null;
    out[key] = { thread: thread?.id ?? null, title };
  }
  return out;
}

/// The connect a Slack thread came in through: the first of its sessions' that is not the station's own.
function threadConnect(s: Store, thread: number): string | null {
  const row = s.db.prepare(`SELECT connect FROM thread_sessions WHERE thread = ? AND connect != '${STILLFAIL_CONNECT}' ORDER BY joined_at, rowid LIMIT 1`).get(thread) as { connect: string } | undefined;
  return row?.connect ?? null;
}
