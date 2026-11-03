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
import { type BatchedUsage, type Json, STILLFAIL_SURFACE, type Store, type UsageGroup, REMOTE_RUNS_PENDING, USAGE_CHATS_PENDING, USAGE_MINUTES_PENDING, remoteRunCount, remoteRunsSince, seenBy, sessionThreads, usageByDay, usageChatTotals, usageChatsReady, usageGroups, usageSince, usageThreads } from "./store.ts";
import { type InWorkspace, sees } from "../store/rows.ts";
import { usageDetailSince } from "../store/usage-detail.ts";
import { compactTotal, hasCompactUsage } from "../store/usage-compact.ts";
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
  queryTime: (ms: number, diagnostics: { parts?: number; candidates?: number; selectedMs?: number; rests?: number; restMs?: number }) => void,
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
type BatchedHistory = { range: { from: bigint; to: bigint }; result: BatchedUsage; all?: boolean };
// A reader says once when its cache actually serves a request. Fast reads otherwise leave no trace in the slow-read
// log, so the absence of that warning alone cannot show whether the cache is used.
let reportedSummaryReuse = false;

/// An indexed existence check is enough to know whether an unbounded history has minutes before a summary.
/// Count even an empty bucket: that can only make us retain the ordinary history query.
export function compactHistoryBeforeQuery(viewer: InWorkspace | null): string {
  return viewer === null
    ? "SELECT 1 FROM usage_compact INDEXED BY usage_compact_time WHERE minute < ?1 LIMIT 1"
    : `SELECT 1 FROM usage_compact INDEXED BY usage_compact_scope_time WHERE ${viewer.home === false ? "scope = ?2" : "scope IN (?2, 'H')"} AND minute < ?1 LIMIT 1`;
}

function summaryCoversHistory(s: Store, from: bigint, to: bigint, viewer: InWorkspace | null): boolean {
  if (from >= to || from % 60_000n !== 0n || to !== 9223372036854775807n || !hasCompactUsage(s.db)) return false;
  const coverage = s.db.prepare("SELECT old_days FROM usage_compact_since WHERE id = 1").get() as { old_days: number };
  if (coverage.old_days !== 0) return false;
  const args: (string | bigint)[] = [from / 60_000n];
  if (viewer !== null) args.push("W" + viewer.workspace);
  return s.db.prepare(compactHistoryBeforeQuery(viewer)).get(...args) === undefined;
}

export function usage(s: Store, lang: Lang, from: bigint, to: bigint, utcOffsetMin: bigint, reading = true, viewer: InWorkspace | null = null, history = false,
  options: { remoteRuns?: boolean; historyRange?: { from: bigint; to: bigint }; batched?: BatchedUsage; batchedHistory?: BatchedHistory; historyPrepassMs?: number } = {}): Json {
  const includeRemoteRuns = options.remoteRuns !== false;
  // Keep the stages of a slow read: a reader has only one request at a time, and a slow aggregate can hold up other
  // reads. Only durations are logged, never the request's arguments or the rows it reads.
  const historyPrepass = options.historyPrepassMs ?? options.batchedHistory?.result.ms ?? 0;
  const started = performance.now() - (options.batched?.ms ?? 0) - historyPrepass;
  let last = started + historyPrepass;
  const stages: Record<string, number> = {};
  if (options.historyPrepassMs !== undefined || options.batchedHistory !== undefined) stages.historyQuery = historyPrepass;
  const mark = (stage: string) => {
    const now = performance.now();
    stages[stage] = Math.round(now - last);
    last = now;
  };
  let summaryParts: number | undefined;
  let summaryCandidates: number | undefined;
  const groups = summary(s, from, to, utcOffsetMin, viewer, (ms, diagnostics) => {
    stages.summaryQuery = ms;
    if (diagnostics.selectedMs !== undefined) stages.summarySelected = diagnostics.selectedMs;
    if (diagnostics.rests !== undefined) stages.summaryRests = diagnostics.rests;
    if (diagnostics.restMs !== undefined) stages.summaryRestMs = diagnostics.restMs;
    summaryParts = diagnostics.parts;
    summaryCandidates = diagnostics.candidates;
  }, options.batched);
  mark("summary");
  // Compact groups have already checked each session's current workspace in the same read snapshot. Looking them
  // up again here needlessly rereads the sessions index for every usage page, including on a cold database.
  const seen = viewer === null || hasCompactUsage(s.db) ? null : seenBy(s, viewer, groups.map((r) => r.session));
  const rows = seen === null ? groups : groups.filter((r) => seen(r.session));
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
  const detailSince = usageDetailSince(s.db);
  const prices = priceTable(lang, rows.map((r) => r.model));
  const profiles = configProfiles(s.dataDir);
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
  let historyResult: Json | undefined;
  let partialHistory: Json | undefined;
  let historyPending = false;
  if (history) {
    try { historyResult = usageHistory(s, utcOffsetMin, viewer, mark, false, options.historyRange); }
    catch (error) {
      if (!(error instanceof Error) || ![REMOTE_RUNS_PENDING, USAGE_CHATS_PENDING, USAGE_MINUTES_PENDING].includes(error.message)) throw error;
      // Old clients continue to see history as unavailable; newer clients can use the separately named, explicitly
      // incomplete history without treating missing earlier calls as zero.
      if (error.message === USAGE_MINUTES_PENDING) {
        let batchedHistory = options.batchedHistory;
        if (batchedHistory === undefined && options.historyRange === undefined && options.batched !== undefined && summaryCoversHistory(s, from, to, viewer)) {
          batchedHistory = { range: { from, to }, result: options.batched, all: true };
        }
        try { partialHistory = usageHistory(s, utcOffsetMin, viewer, mark, true, options.historyRange, batchedHistory); }
        catch (partialError) {
          if (!(partialError instanceof Error) || ![REMOTE_RUNS_PENDING, USAGE_CHATS_PENDING, USAGE_MINUTES_PENDING].includes(partialError.message)) throw partialError;
          historyPending = partialError.message === USAGE_MINUTES_PENDING && options.historyRange !== undefined && hasCompactUsage(s.db);
        }
      }
    }
  }
  mark("details");
  const answer = {
    from: i64(from),
    to: i64(to),
    since,
    ...(detailSince !== null ? { detailSince } : {}),
    reading,
    prices,
    rows,
    threads,
    people,
    profiles,
    // the tasks the viewer's workspace's chats on other stations ran here since `from` (the card's 跨设备执行): the
    // workspace their key names (`remote:<workspace>:…`)
    ...(remoteRuns !== undefined ? { remoteRuns } : {}),
    ...(historyResult !== undefined ? { history: historyResult } : {}),
    ...(history && historyResult === undefined ? { historyUnavailable: true } : {}),
    ...(partialHistory !== undefined ? { partialHistory } : {}),
    ...(historyPending ? { historyPending: true } : {}),
  };
  mark("other");
  const ms = Math.round(performance.now() - started);
  if (!reportedSummaryReuse && options.batched?.diagnostics.cache === "reused") {
    reportedSummaryReuse = true;
    log.info("readers", "a usage read reused its summary", { ms, summaryQuery: stages.summaryQuery, summaryCandidates, summaryParts,
      ...(stages.historyQuery === undefined ? {} : { historyQuery: stages.historyQuery }) });
  }
  if (ms >= 1_000) {
    const partialMinute = from < to && (from % 60_000n !== 0n || (to !== 9223372036854775807n && to % 60_000n !== 0n));
    log.warn("readers", "a usage read's stages", { ms, ...stages, summaryGroups: groups.length,
      ...(options.batched === undefined ? {} : { summaryCache: options.batched.diagnostics.cache }),
      ...(summaryCandidates !== undefined ? { summaryCandidates } : {}), historyPending,
      ...(summaryParts !== undefined ? { summaryParts, summaryEdges: partialMinute } : {}) });
  }
  return answer;
}

/// What the viewer's chats did on this station since it began counting (the usage page's summary): the tokens by day
/// in the asker's time zone, runtime and model (the year, as Codex's usage summary has it); the chats of each place
/// (still.fail's, Slack, Feishu) and how many were archived; the tasks other stations' chats ran here (one device's chat
/// working on another); the decision cards asked and those answered by an option pressed. GET /usage?history=1.
export function validHistoryRange(requested: { from: bigint; to: bigint } | undefined, utcOffsetMin: bigint): boolean {
  const day = 86_400_000n;
  return requested !== undefined && requested.from <= requested.to && requested.to - requested.from <= 370n * day
    && requested.from % 60_000n === 0n && requested.to % 60_000n === 0n
    && (requested.to + utcOffsetMin * 60_000n) % day === 0n
    && requested.to + utcOffsetMin * 60_000n >= -8_640_000_000_000_000n
    && requested.to + utcOffsetMin * 60_000n <= 8_640_000_000_000_000n;
}

/// A cached detail summary contains the same new minutes as an incomplete compact history. Group it in the same
/// order as SQLite and keep integer arithmetic exact until each session/model total is converted.
function historyFromSummary(groups: UsageGroup[]): ReturnType<typeof usageByDay> | null {
  if (groups.some((g) => g.day === "")) return null;
  type History = { day: string; session: string; runtime: string; model: string | null; tokens: bigint; calls: bigint };
  const grouped = new Map<string, History>();
  for (const g of groups) {
    const key = JSON.stringify([g.day, g.session, g.runtime, g.model]);
    let row = grouped.get(key);
    if (!row) { row = { day: g.day, session: g.session, runtime: g.runtime, model: g.model, tokens: 0n, calls: 0n }; grouped.set(key, row); }
    row.tokens += BigInt(g.input) + BigInt(g.cacheRead) + BigInt(g.cacheWrite) + BigInt(g.cacheWriteLong) + BigInt(g.output);
    row.calls += BigInt(g.calls);
  }
  const cmp = (a: string | null, b: string | null) => a === b ? 0 : a === null ? -1 : b === null ? 1 : byBytes(a, b);
  const safe = (n: bigint) => {
    if (n > BigInt(Number.MAX_SAFE_INTEGER) || n < BigInt(Number.MIN_SAFE_INTEGER)) throw new RangeError("integer is too large to be represented as a JavaScript number");
    return Number(n);
  };
  return [...grouped.values()].sort((a, b) => cmp(a.day, b.day) || cmp(a.session, b.session) || cmp(a.runtime, b.runtime) || cmp(a.model, b.model))
    .map((r) => ({ ...r, tokens: safe(r.tokens), calls: safe(r.calls) }));
}

export function usageHistory(s: Store, utcOffsetMin: bigint, viewer: InWorkspace | null, mark: (stage: string) => void = () => {}, partial = false,
  requested?: { from: bigint; to: bigint }, batched?: BatchedHistory): Json {
  usageChatsReady(s, viewer);
  mark("historyVisibility");
  const valid = validHistoryRange(requested, utcOffsetMin);
  // Preserve a complete pre-existing history until it has its own bounded source. Incomplete history has only the
  // new compact buckets; a fresh database has no older daily rows to consult.
  const bounded = valid && hasCompactUsage(s.db) && (partial ||
    s.db.prepare("SELECT 1 FROM usage_day_quarters LIMIT 1").get() === undefined);
  const range = bounded && requested !== undefined ? { from: requested.from / 60_000n, to: requested.to / 60_000n } : undefined;
  const total = range === undefined ? null : compactTotal(s.db, viewer, range.to);
  if (range !== undefined && total === null) throw new Error(USAGE_MINUTES_PENDING);
  const days = new Map<string, { day: string; runtime: string; model: string | null; tokens: number; calls: number }>();
  // Old complete totals have a separate source. Only substitute when the stored coverage says there are none.
  const compactOnly = partial && batched !== undefined &&
    (batched.all === true ? requested === undefined : range !== undefined && requested !== undefined &&
      batched.range.from === requested.from && batched.range.to === requested.to) &&
    (s.db.prepare("SELECT old_days FROM usage_compact_since WHERE id = 1").get() as { old_days: number }).old_days === 0;
  const cachedDays = compactOnly ? historyFromSummary(batched!.result.groups) : null;
  for (const r of cachedDays ?? usageByDay(s, utcOffsetMin, viewer, partial, range)) {
    const key = `${r.day}\n${r.runtime}\n${r.model ?? ""}`;
    const d = days.get(key) ?? { day: r.day, runtime: r.runtime, model: r.model, tokens: 0, calls: 0 };
    d.tokens += r.tokens;
    d.calls += r.calls;
    days.set(key, d);
  }
  mark("historyDays");
  // the chats of each place (still.fail's own, a Slack workspace's, a Feishu one's), and those archived
  const chats = usageChatTotals(s, viewer);
  mark("historyPlaces");
  // the tasks the viewer's chats on other stations ran here, as long as they are kept (remote_runs: 90 days)
  const remoteRuns = remoteRunCount(s, viewer);
  mark("historyRemoteRuns");
  // the decision cards the viewer's chats were asked with, and those answered by an option pressed
  mark("historyCards");
  return {
    days: [...days.values()].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0)),
    ...(total !== null && requested !== undefined ? {
      tokens: total.tokens, beforeDay: new Date(Number(requested.to + utcOffsetMin * 60_000n)).toISOString().slice(0, 10),
    } : {}),
    cards: chats.cards,
    picked: chats.picked,
    places: chats.places,
    archived: chats.archived,
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
