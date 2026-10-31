// An agent of a chat in brief, for its card (the `agentCard` view: over its avatar on the wide screen, web AgentCard.tsx;
// a sheet on the phone, mobile/AgentSheet.tsx and the Android app's AgentSheet.kt): how much it has done, what that cost
// and used (its tokens, the cache's hit rate, how full its context is), the latest of what it did and what it does now,
// its jobs at work, and what is wrong.
import { args, doing, type Known, tasksOf, toolName } from "../activity.ts";
import { coldAfresh, coldWorth } from "../cache-policy.ts";
import * as format from "../format.ts";
import { usageOf } from "../history.ts";
import { t } from "../i18n.ts";
import * as jobs from "../jobs.ts";
import { shownStatus } from "../present.ts";
import { arr as arrU, get as getU } from "../util.ts";
import { money } from "./usage.ts";

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

/// How many of the latest things it did its card says.
const RECENT = 3;
const firstLine = (s: string) => (s.split(/\r?\n/).find((l) => l.trim() !== "") ?? "").trim();

/// The latest things it did (its own, not its subagents'), oldest first, three at most, each in a line as its
/// execution history would name it: a call by what it does, a message by what it posts, what it wrote or thought by
/// its first line. Each is keyed by its entry's place in the transcript, which stays its own as newer ones come.
/// From its live transcript: none before that is read. `stations`: the workspace's stations' names by id.
export function recentOf(live: unknown, stations?: ReadonlyMap<string, string>): { key: string; text: string }[] {
  const out: { key: string; text: string }[] = [];
  const timeline = arr(get(live, "timeline"));
  const known: Known = { stations, tasks: tasksOf(timeline) };
  const base = typeof get(live, "first") === "number" ? (get(live, "first") as number) : 0;
  for (let i = timeline.length - 1; i >= 0 && out.length < RECENT; i--) {
    const e = timeline[i];
    if (get(e, "subagent") === true) continue;
    const kind = get(e, "kind");
    const text = typeof get(e, "text") === "string" ? (get(e, "text") as string) : "";
    let line = "";
    if (kind === "tool_call") {
      const tool = typeof get(e, "tool") === "string" ? (get(e, "tool") as string) : "";
      const name = toolName(tool);
      if (name === "chat_state") continue;
      const posted = name === "chat_post" ? args(text)?.text : null;
      line = typeof posted === "string" ? firstLine(posted) : doing(tool, text, known);
    } else if (kind === "assistant" || kind === "thinking") line = firstLine(text);
    if (line) out.unshift({ key: String(base + i), text: line });
  }
  return out;
}

/// Its latest lines, three at most, oldest first: what it did, then while it works what it does now (unless that is
/// the last of them already), marked `now` and keyed so (it stays the one line while its words change).
export function latestOf(agent: unknown, live: unknown, stations?: ReadonlyMap<string, string>): { key: string; text: string; now?: boolean }[] {
  const recent: { key: string; text: string; now?: boolean }[] = recentOf(live, stations);
  const status = get(agent, "status");
  const now = get(get(get(live, "activity"), "now"), "text");
  if ((status === "running" || status === "queued") && typeof now === "string" && now !== "" && now !== recent.at(-1)?.text) recent.push({ key: "now", text: now, now: true });
  return recent.slice(-RECENT);
}

type Level = "ok" | "amber" | "red";
type Meter = { percent: number; text: string; level: Level };

/// How full a context is that is worth a look, and one about to be compacted.
const CONTEXT_AMBER = 80;
const CONTEXT_RED = 95;

/// What a session's calls used as known now (the station's read/usage.ts SessionUsage: its calls as its usage counter
/// recorded them, the usage page's count too): while it works, as its station's stream tells it as more are recorded
/// (`live`); at rest, as its summary says it, which the device holds of every session (told again as the count of its
/// last turn comes in after it ended); either where the other says none (a station from before says it in no summary,
/// and on its stream only of a session named there). None before a call.
export function usageNow(session: unknown, live: unknown): J {
  const told = get(live, "usage");
  const said = get(session, "usage");
  const has = (u: unknown) => u !== null && typeof u === "object" && !Array.isArray(u);
  const status = shownStatus(session);
  const [first, then] = status === "running" || status === "queued" ? [told, said] : [said, told];
  return has(first) ? first : has(then) ? then : null;
}

/// Of a chat's agents (ViewsInner `agent`), the one at rest whose prompt cache is over, with a context worth going on
/// afresh with (the largest of those): the line over the composer that says what going on would read again
/// (ChatCacheCold); and in how long, at `now`, another's is over (Infinity: none's to come). None at work, with no
/// runtime session to go on in, or of a station that does not tell how long its cache lasts. One waiting on work of its
/// own is said too: what it waits on starts it again. Whether it goes on afresh as it is next started (by a message or
/// a notice): as chosen in its chat (its session's `afresh`), or else as its station is set (`station`).
export function cacheCold(agents: unknown, now: number, station = false, threshold?: number): [J, number] {
  let cold: { session: string; context: number; cost: number | null; afresh: boolean } | null = null;
  let next = Infinity;
  for (const a of arr(agents)) {
    const status = get(a, "status");
    if (status === "running" || status === "queued") continue;
    const session = get(a, "session");
    const key = get(session, "key");
    if (typeof key !== "string" || typeof get(session, "runtimeSessionId") !== "string") continue;
    const u = usageNow(session, null);
    const [at, ms, context] = [get(u, "lastCallAt"), get(u, "cacheMs"), get(u, "contextTokens")];
    const chosen = get(session, "afresh");
    const cost = typeof get(u, "rereadCost") === "number" ? u.rereadCost as number : undefined;
    // The price makes a small context worth mentioning even when automatic replacement is off: the person can still
    // choose what to do with it. An older station gives no threshold and keeps its former 50K-token rule.
    if (typeof at !== "number" || typeof ms !== "number" || typeof context !== "number" ||
      !coldWorth(context, cost, threshold, chosen)) continue;
    if (at + ms > now) {
      next = Math.min(next, at + ms - now);
      continue;
    }
    const afresh = coldAfresh(chosen, station, threshold, cost);
    if (cold === null || context > cold.context) cold = { session: key, context, cost: cost ?? null, afresh };
  }
  if (cold === null) return [null, next];
  const tokens = format.compactNumber(cold.context);
  const status = t("core-views.agent.cacheColdStatus");
  const detail = cold.cost !== null ? t("core-views.agent.cacheColdCostDetail", { cost: money(cold.cost) }) : t("core-views.agent.cacheColdTokensDetail", { tokens });
  return [{ session: cold.session, status, detail, afresh: cold.afresh }, next];
}

/// What it has going in the background past its turns (its live view's `tasks`, as its station says them), each with
/// what it is in words and since when (on this device's clock): its subagents and its commands.
export function backgroundOf(live: unknown): J[] {
  return arr(get(live, "tasks")).flatMap((task) => {
    const id = get(task, "id");
    if (typeof id !== "string") return [];
    const kind = get(task, "kind") === "agent" ? "agent" : "command";
    const description = get(task, "description");
    const kindText = t(kind === "agent" ? "core-views.agent.task.agent" : "core-views.agent.task.command");
    const since = get(task, "since");
    return [{ id, kind, text: typeof description === "string" && description.trim() !== "" ? firstLine(description) : kindText, kindText, since: typeof since === "number" ? since : 0 }];
  });
}

/// Its checklist as it said it last (its live view's `plan`): each item's words and where it stands (completed,
/// in_progress, else still to do).
export function planOf(live: unknown): { text: string; status: string }[] {
  return arr(get(live, "plan")).flatMap((item) => {
    const text = get(item, "text");
    const status = get(item, "status");
    return typeof text === "string" && text !== "" ? [{ text, status: typeof status === "string" ? status : "pending" }] : [];
  });
}

/// What its card and its history's details say of its work past its turns and its checklist: the tasks, the items,
/// how many of them are done (已完成 2/5), and all of it in one line (`workLine`: 后台 4 · 清单 2/6：<the item under way,
/// else the next>, each part only where it has one), what its card shows; and shorter (`workMark`: 后台 4 · 2/6), its
/// execution history's mark, which opens all of it. Neither when it has neither.
export function workOf(live: unknown): J {
  const tasks = backgroundOf(live);
  const plan = planOf(live);
  const out: J = { tasks, plan };
  const parts: string[] = [];
  if (tasks.length > 0) parts.push(t("core-views.agent.going.tasks", { n: tasks.length }));
  if (plan.length > 0) {
    const done = plan.filter((p) => p.status === "completed").length;
    out.planText = t("core-views.agent.plan.done", { done, n: plan.length });
    const now = plan.find((p) => p.status === "in_progress") ?? plan.find((p) => p.status !== "completed");
    const counted = t("core-views.agent.going.plan", { done, n: plan.length });
    parts.push(now ? t("core-views.agent.going.planNow", { plan: counted, item: firstLine(now.text) }) : counted);
  }
  if (parts.length > 0) out.workLine = parts.join(" · ");
  // Its history's mark, shorter: 后台 4 · 2/6, 后台 4, 清单 2/6; with less room, 4 · 2/6.
  if (plan.length > 0 || tasks.length > 0) {
    const done = plan.filter((p) => p.status === "completed").length;
    out.workMark = tasks.length === 0 ? t("core-views.agent.going.plan", { done, n: plan.length })
      : plan.length === 0 ? t("core-views.agent.going.tasks", { n: tasks.length })
      : `${t("core-views.agent.going.tasks", { n: tasks.length })} · ${done}/${plan.length}`;
    // (where its row has less room: the counts alone)
    out.workMarkShort = [...(tasks.length > 0 ? [`${tasks.length}`] : []), ...(plan.length > 0 ? [`${done}/${plan.length}`] : [])].join(" · ");
    // (with less still: beside an icon, how many tasks, else how much of the checklist is done)
    out.workMarkCount = tasks.length > 0 ? `${tasks.length}` : `${done}/${plan.length}`;
  }
  return out;
}

/// The card of `agent` (a chat's agent, ViewsInner `agent`), with its live view (none before it is read): each part
/// only when it has one. Its account and what is left of it the card takes from the agent as it is.
export function card(agent: J, live: J, stations?: ReadonlyMap<string, string>): J {
  const out: J = { work: workText(get(agent, "turns")), jobs: jobsText(get(agent, "jobs")), latest: latestOf(agent, live, stations), attention: [], ...workOf(live) };
  const u = usageNow(get(agent, "session"), live);
  const n = (k: string): number => (typeof get(u, k) === "number" ? u[k] : 0);
  if (n("modelCalls") > 0) {
    const { contextPercent, cost } = usageOf(u);
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
