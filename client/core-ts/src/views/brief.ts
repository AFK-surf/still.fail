// An agent of a chat in brief, for its card over its avatar (the `agentCard` view, web AgentCard.tsx): how much it has
// done, what that cost and used (its tokens, the cache's hit rate, how full its context is), its jobs at work, and what
// is wrong.
import * as format from "../format.ts";
import { usageOf } from "../history.ts";
import { t } from "../i18n.ts";
import * as jobs from "../jobs.ts";
import { arr as arrU, get as getU } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const MINUTE = 60_000;

/// Its turns, and how long the finished ones took together: 8 轮 · 共 1 小时 12 分. None before its first turn.
export function workText(turns: unknown): string | null {
  const all = arr(turns);
  if (all.length === 0) return null;
  let ms = 0;
  for (const turn of all) {
    const from = get(turn, "startedAt");
    const to = get(turn, "endedAt");
    if (typeof from === "number" && typeof to === "number" && to > from) ms += to - from;
  }
  const n = all.length;
  const minutes = Math.round(ms / MINUTE);
  if (minutes < 1) return t("core-views.agent.turns", { n });
  const time = minutes < 60
    ? t("core-views.agent.minutes", { m: minutes })
    : t("core-views.agent.hours", { h: Math.trunc(minutes / 60), m: minutes % 60 });
  return t("core-views.agent.work", { n, time });
}

/// Its jobs at work now, by what they are: 服务在线：web、api · 在盯着：CI · 1 个任务在跑. None when none is.
export function jobsText(list: unknown): string | null {
  const names = (pick: (job: J) => boolean) => arr(list).filter(pick).map((job) => String(get(job, "name") ?? "")).filter(Boolean);
  const services = names((job) => jobs.tone(job) === "up");
  const watching = names((job) => jobs.isWatch(job) && jobs.tone(job) === "live");
  const running = names((job) => !jobs.isWatch(job) && jobs.tone(job) === "live");
  const parts: string[] = [];
  if (services.length) parts.push(t("core-views.agent.services", { names: services.join(t("core-views.list_separator")) }));
  if (watching.length) parts.push(t("core-views.agent.watching", { names: watching.join(t("core-views.list_separator")) }));
  if (running.length) parts.push(t("core-views.agent.running", { n: running.length }));
  return parts.length ? parts.join(" · ") : null;
}

type Level = "ok" | "amber" | "red";
type Meter = { percent: number; text: string; level: Level };

/// How full a context is that is worth a look, and one about to be compacted.
const CONTEXT_AMBER = 80;
const CONTEXT_RED = 95;

/// The card of `agent` (a chat's agent, ViewsInner `agent`), with its live usage (none before it is read): each part
/// only when it has one. Its account and what is left of it the card takes from the agent as it is.
export function card(agent: J, live: J): J {
  const out: J = { work: workText(get(agent, "turns")), jobs: jobsText(get(agent, "jobs")), attention: [] };
  const u = get(live, "usage");
  const n = (k: string): number => (typeof get(u, k) === "number" ? u[k] : 0);
  if (n("modelCalls") > 0) {
    const { contextPercent, cost } = usageOf(live);
    out.cost = cost;
    out.tokens = t("core-views.agent.tokens", { input: format.compactNumber(n("inputTokens")), output: format.compactNumber(n("outputTokens")) });
    if (n("inputTokens") > 0) {
      const percent = format.round((n("cachedTokens") / n("inputTokens")) * 100);
      out.cache = { percent, text: `${percent}%`, level: "ok" } satisfies Meter;
    }
    if (typeof get(u, "contextTokens") === "number") {
      const used = format.compactNumber(n("contextTokens"));
      out.context = contextPercent !== null
        ? { percent: contextPercent, text: t("core-views.agent.context", { used, window: format.compactNumber(n("contextWindow")) }), level: contextPercent >= CONTEXT_RED ? "red" : contextPercent >= CONTEXT_AMBER ? "amber" : "ok" } satisfies Meter
        : { percent: 0, text: used, level: "ok" } satisfies Meter;
      if (contextPercent === null) out.context.unknown = true;
    }
  }
  // What is wrong, but a quota running out: its account's windows say that.
  for (const a of arr(get(agent, "attention"))) {
    if (get(a, "kind") === "quota") continue;
    out.attention.push({ text: String(get(a, "text") ?? ""), level: get(a, "kind") === "disk" ? "amber" : "red" });
  }
  return out;
}
