// An agent of a chat in brief, for its card over its avatar (web AgentCard.tsx): how much it has done, and the jobs it
// has at work. What it does now and what is worth a look (`attention`) the card takes from the agent as it is.
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
