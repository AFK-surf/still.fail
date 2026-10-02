// What the agents spent, as the usage page reads it (GET /usage): admin/views.rs `usage` over usage.rs `summary`,
// `price_table`, `price`, `cost` and store/usage.rs, with the same JSON field for field.
//
// The counting itself (src/usage/counter.ts, usage.rs `Usage::read`: the transcripts read into the `usage` table) is
// the running station's, not a read: what was counted is read here as it is in the database. `reading` is what the
// counter has in its memory (`readingAll`), given by the asker; not given, it is true (nothing read yet).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { type Lang, tr } from "../ops/i18n.ts";
import { type Json, type Store, type UsageGroup, usageGroups, usageSince, usageThreads } from "./store.ts";
import { titleOf } from "./views.ts";

// ── prices (usage.rs) ──

/// A model's API prices, in dollars per million tokens. Writing to the cache costs 1.25× input for five minutes, 2× for
/// an hour; fast mode doubles all of it.
type Price = { input: number; output: number; cacheRead: number };

/// usage.rs PRICES: standard short-context API list prices (2026-10-02). Longer names first.
const PRICES: [string, Price][] = [
  ["gpt-6-astra", { input: 10.0, output: 50.0, cacheRead: 1.0 }],
  ["gpt-6.1-sol", { input: 2.0, output: 10.0, cacheRead: 0.1 }],
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
  ["claude-sonnet-5-5", { input: 2.0, output: 10.0, cacheRead: 0.2 }],
  ["claude-sonnet-5", { input: 2.0, output: 10.0, cacheRead: 0.2 }],
  ["claude-sonnet-4-6", { input: 3.0, output: 15.0, cacheRead: 0.3 }],
  ["claude-sonnet-4-5", { input: 3.0, output: 15.0, cacheRead: 0.3 }],
  ["claude-haiku-4-5", { input: 1.0, output: 5.0, cacheRead: 0.1 }],
];

/// price_table: the very same table `cost` uses, for inspecting a station's calculation from the usage page.
export function priceTable(lang: Lang): Json {
  return {
    note: tr(lang, "station.usage.priceNote"),
    rows: PRICES.map(([model, p]) => ({
      model, input: p.input, cacheRead: p.cacheRead,
      cacheWrite: model.startsWith("claude-") ? p.input * 1.25 : null,
      cacheWriteLong: model.startsWith("claude-") ? p.input * 2.0 : null, output: p.output,
    })),
  };
}

/// Bedrock's version stamp after `-v`: `1:0` (not a model's own v4). (shapes model.rs `stamp`)
function stamp(s: string): boolean {
  const colon = s.indexOf(":");
  if (colon < 0) return false;
  const [major, minor] = [s.slice(0, colon), s.slice(colon + 1)];
  return /^[0-9]+$/.test(major) && /^[0-9]+$/.test(minor);
}

/// shapes model.rs `key`: what a model is, however it is spelled: lower case, without its provider's prefix, region,
/// version stamp or date; a `[1m]` context stays.
export function modelKey(spelled: string): string {
  const id = spelled.trim().toLowerCase();
  const bracket = id.indexOf("[");
  const [base, context] = bracket >= 0 ? [id.slice(0, bracket), id.slice(bracket)] : [id, ""];
  // OpenRouter's and other routers' `vendor/model`; Vertex's `model@date`.
  let m = base.slice(base.lastIndexOf("/") + 1);
  m = m.split("@")[0]!;
  // Bedrock's `us.anthropic.model-v1:0`: region and vendor are words and a dot, a version is not (gpt-5.1).
  for (let dot = m.indexOf("."); dot >= 0; dot = m.indexOf(".")) {
    const [head, rest] = [m.slice(0, dot), m.slice(dot + 1)];
    if (head === "" || !/^[A-Za-z]+$/.test(head) || rest === "") break;
    m = rest;
  }
  const v = m.lastIndexOf("-v");
  if (v >= 0 && stamp(m.slice(v + 2))) m = m.slice(0, v);
  // A date: -20251001, or -2024-08-06.
  const parts = m.split("-");
  const digits = (s: string, n: number) => s.length === n && /^[0-9]+$/.test(s);
  const n = parts.length;
  if (n > 1 && digits(parts[n - 1]!, 8)) m = parts.slice(0, n - 1).join("-");
  else if (n > 3 && digits(parts[n - 3]!, 4) && digits(parts[n - 2]!, 2) && digits(parts[n - 1]!, 2)) m = parts.slice(0, n - 3).join("-");
  return m + context;
}

/// price: a model's prices, however a profile spells it (anthropic/claude-opus-5-5, claude-opus-5-5[1m]); none for a
/// model without a list price here.
export function price(model: string): Price | null {
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

/// Usage::summary: every day's calls from `from` until `to`, by thread, person, profile and model (UsageRow).
function summary(s: Store, from: bigint, to: bigint, utcOffsetMin: bigint): Json[] {
  return usageGroups(s, from, to, utcOffsetMin).map((g) => ({
    day: g.day, session: g.session, thread: g.thread, person: g.person, profile: g.profile, runtime: g.runtime, model: g.model,
    calls: g.calls, input: g.input, cacheRead: g.cacheRead, cacheWrite: g.cacheWrite + g.cacheWriteLong, output: g.output, cost: cost(g),
  }));
}

// ── the config's profiles (config.rs parse_config, what usage shows of them) ──

/// The runtimes an API provider's profile runs, from where its provider speaks (shapes providers.rs `endpoints` and
/// `uses`, profiles.rs `runtimes_for`): Anthropic's protocol is Claude Code's, Responses Codex's.
function providerRuntimes(provider: string | undefined, endpoint: string | undefined, protocol: string | undefined): string[] {
  // Sources at their own address that speak Anthropic's protocol and/or Responses (the rest speak chat completions only).
  const fixed: Record<string, string[]> = {
    openai: ["codex"], anthropic: ["claude"], xai: ["codex"], minimax: ["claude"], "minimax-cn": ["claude"], openrouter: ["claude"],
    "vercel-ai-gateway": ["claude"], opencode: ["claude", "codex"], "opencode-go": ["claude", "codex"], fireworks: ["claude"],
    "azure-openai": ["codex"],
  };
  if (provider === undefined) return [];
  if (provider in fixed) return fixed[provider]!;
  const chosen = protocol === "chat_completions" || protocol === "responses" || protocol === "anthropic" ? protocol : undefined;
  const one = (p: string) => (p === "anthropic" ? ["claude"] : p === "responses" ? ["codex"] : []);
  if (provider === "cloudflare-ai-gateway") return chosen ? one(chosen) : ["claude", "codex"];
  if (provider === "custom") {
    // clean_endpoint: trimmed, without trailing slashes; Anthropic's protocol at the root above a /v1.
    const base = (endpoint ?? "").trim().replace(/\/+$/, "");
    return chosen ? one(chosen) : base.endsWith("/v1") ? ["claude", "codex"] : ["codex"];
  }
  return [];
}

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
    const kind: string = p.access?.kind ?? "env";
    const runtimes =
      kind === "api-provider"
        ? providerRuntimes(p.access?.provider || undefined, p.access?.endpoint, p.access?.protocol || undefined)
        : kind === "opencode-go"
          ? ["claude", "codex"]
          : kind === "anthropic-api"
            ? ["claude"]
            : p.runtime === "claude" || p.runtime === "codex"
              ? [p.runtime]
              : [];
    const name = typeof p.name === "string" && p.name.trim() !== "" ? p.name.trim() : p.id;
    out[p.id] = { name, runtime: runtimes[0] ?? "claude" };
  }
  return out;
}

// ── people (views.rs `creator`, as views.ts has it) ──

/// A creator reference in words. No Slack connection knows anyone: a Slack user goes by their id, with no email.
function creator(s: Store, lang: Lang, reference: string): Json {
  if (reference === "local") return { id: "local", name: tr(lang, "station.creator.localPage"), email: null, via: "local" };
  if (reference.startsWith("slack:")) {
    const rest = reference.slice("slack:".length);
    const colon = rest.indexOf(":");
    if (colon > 0 && colon < rest.length - 1) return { id: reference, name: rest.slice(colon + 1), email: null, via: "slack" };
  }
  return { id: reference, name: s.names.get(reference) ?? reference, email: reference, via: "cloud" };
}

/// Rust's String order (bytes of UTF-8), for a BTreeSet's.
const byBytes = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));

/// admin/views.rs `usage`: what the agents spent from `from` until `to` (ms), by day in the asker's time zone
/// (`utcOffsetMin`), with the threads, people and profiles the rows name. `from`/`to` are i64s, written as such.
/// `reading`: whether the counter is still reading everything for the first time (UsageCounter.readingAll).
export function usage(s: Store, lang: Lang, from: bigint, to: bigint, utcOffsetMin: bigint, reading = true): Json {
  const rows = summary(s, from, to, utcOffsetMin);
  const wanted = [...new Set(rows.map((r) => r.thread).filter((t): t is number => t !== null))];
  const threads: Record<string, Json> = {};
  for (const [t, first] of usageThreads(s, wanted)) {
    // No Slack connection knows a channel's name (`known_channel`): none.
    const title = titleOf(t, first, null);
    threads[String(t.id)] = { title, surface: t.surface, home: t.home, archived: t.hiddenAt !== null };
  }
  const refs = [...new Set(rows.map((r) => r.person).filter((p): p is string => p !== null))].sort(byBytes);
  const people: Record<string, Json> = {};
  for (const r of refs) people[r] = creator(s, lang, r);
  const i64 = (n: bigint) => (JSON as any).rawJSON(String(n));
  return {
    from: i64(from),
    to: i64(to),
    since: usageSince(s),
    reading,
    prices: priceTable(lang),
    rows,
    threads,
    people,
    profiles: configProfiles(s.dataDir),
  };
}
