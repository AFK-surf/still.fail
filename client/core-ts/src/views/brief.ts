// An agent of a chat in brief, for its card over its avatar (the `agentCard` view, web AgentCard.tsx): a row for each
// thing worth knowing of it that it has, labelled: how much it has done, what that cost and used (cache hits, how full
// its context is), the account it runs on and what is left of it, its jobs at work, and what is wrong.
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
  if (services.length) parts.push(t("core-views.agent.services", { names: services.join("、") }));
  if (watching.length) parts.push(t("core-views.agent.watching", { names: watching.join("、") }));
  if (running.length) parts.push(t("core-views.agent.running", { n: running.length }));
  return parts.length ? parts.join(" · ") : null;
}

type Row = { label: string; value: string; level?: "amber" | "red" };

/// How full a context is that is worth a look, and one about to be compacted.
const CONTEXT_AMBER = 80;
const CONTEXT_RED = 95;

/// The card of `agent` (a chat's agent, ViewsInner `agent`), with its live usage (none before it is read).
export function card(agent: J, live: J): { rows: Row[] } {
  const rows: Row[] = [];
  const work = workText(get(agent, "turns"));
  if (work !== null) rows.push({ label: t("core-views.agent.label.work"), value: work });
  const u = get(live, "usage");
  const calls = typeof get(u, "modelCalls") === "number" ? u.modelCalls : 0;
  if (calls > 0) {
    const { context, contextPercent, cost } = usageOf(live);
    if (cost !== null) rows.push({ label: t("core-logic.history.usage.cost"), value: cost });
    const input = typeof u.inputTokens === "number" ? u.inputTokens : 0;
    const output = typeof u.outputTokens === "number" ? u.outputTokens : 0;
    rows.push({ label: t("core-views.agent.label.tokens"), value: t("core-views.agent.tokens", { input: format.compactNumber(input), output: format.compactNumber(output) }) });
    if (input > 0) rows.push({ label: t("core-logic.history.usage.hit_rate"), value: `${format.round(((typeof u.cachedTokens === "number" ? u.cachedTokens : 0) / input) * 100)}%` });
    if (context !== null) {
      const level = contextPercent === null ? null : contextPercent >= CONTEXT_RED ? "red" : contextPercent >= CONTEXT_AMBER ? "amber" : null;
      rows.push({ label: t("core-logic.history.usage.context"), value: context, ...(level ? { level } : {}) });
    }
  }
  const account = get(agent, "account") ?? get(agent, "profile");
  const name = get(account, "name");
  if (typeof name === "string" && name) rows.push({ label: t("core-views.agent.label.account"), value: name });
  const attention = arr(get(agent, "attention"));
  const quota = get(get(agent, "account"), "quotaLine");
  if (typeof get(quota, "text") === "string") {
    // When a window runs low, when it fills again (its attention says).
    const refills = attention.filter((a) => get(a, "kind") === "quota" && typeof get(a, "more") === "string").map((a) => a.more as string);
    const level = get(quota, "level");
    rows.push({ label: t("core-views.agent.label.quota"), value: [quota.text, ...refills].join(" · "), ...(level === "amber" || level === "red" ? { level } : {}) });
  }
  const jobsNow = jobsText(get(agent, "jobs"));
  if (jobsNow !== null) rows.push({ label: t("core-views.agent.label.jobs"), value: jobsNow });
  for (const a of attention) {
    // A quota running out is in its row already.
    if (get(a, "kind") === "quota" && typeof get(quota, "text") === "string") continue;
    const level = get(get(a, "quota"), "level") ?? (get(a, "kind") === "disk" ? "amber" : "red");
    rows.push({ label: t("core-views.agent.label.attention"), value: String(get(a, "text") ?? ""), level });
  }
  return { rows };
}
