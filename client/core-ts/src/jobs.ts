// Background jobs and web services as the clients show them (jobs.rs): each job's dot, its state in a word and the
// line under its name (`shown`), a chat's all together (`chatJobs`), those left up a long while (`longJobs`). Times in
// words here count in seconds, so what shows them is computed again when the next of them changes (`nextChange`).
import * as format from "./format.ts";
import { said } from "./format.ts";
import { t } from "./i18n.ts";
import type { Clock } from "./present.ts";
import { arr as arrU, get as getU } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

/// A job that ended or failed this long ago is no longer news.
const NEWS = 24 * 3_600_000;
/// Up this long, a service or job is worth a reminder.
export const LONG = 3_600_000;

const strOf = (job: J, field: string): string => (typeof get(job, field) === "string" ? job[field] : "");
const msOf = (job: J, field: string): number | null => (typeof get(job, field) === "number" && job[field] > 0 ? job[field] : null);
const intOf = (v: J): number | null => (typeof v === "number" && Number.isInteger(v) ? v : null);

export function isService(job: J): boolean {
  const p = get(job, "port");
  return p !== undefined && p !== null;
}

export function tone(job: J): string {
  const state = strOf(job, "state");
  if (state === "failed") return "fail";
  if (state === "stopped") return "off";
  if (isService(job)) return state === "running" ? "up" : "restart";
  if (state === "running") return "live";
  return intOf(get(job, "exitCode")) === 0 ? "off" : "fail";
}

export function isWatch(job: J): boolean {
  return get(job, "watch") === true;
}

export function isEnded(job: J): boolean {
  const state = strOf(job, "state");
  return state === "stopped" || state === "failed" || (state === "exited" && !isService(job));
}

function isCurrent(job: J, now: number): boolean {
  const tn = tone(job);
  if (tn === "off") return false;
  if (tn === "fail") return now - (msOf(job, "endedAt") ?? msOf(job, "startedAt") ?? 0) < NEWS;
  return true;
}

function rank(tn: string): number {
  return tn === "fail" ? 0 : tn === "restart" ? 1 : tn === "off" ? 3 : 2;
}

function word(job: J): string {
  const tn = tone(job);
  const state = strOf(job, "state");
  if (isService(job)) {
    return tn === "up"
      ? said("core-logic.jobs.word.up")
      : tn === "restart"
        ? said("core-logic.jobs.word.restarting")
        : tn === "fail"
          ? said("core-logic.jobs.word.failed")
          : said("core-logic.jobs.word.stopped");
  }
  if (tn === "live") return isWatch(job) ? said("core-logic.jobs.word.watching") : said("core-logic.jobs.word.live");
  if (tn === "fail") return state === "failed" ? said("core-logic.jobs.word.failed") : said("core-logic.jobs.word.crashed");
  return state === "stopped" ? said("core-logic.jobs.word.stopped") : said("core-logic.jobs.word.ended");
}

/// A time span in words: 12 秒, 4 分钟, 3 小时, 2 天.
export function span(ms: number): string {
  const s = Math.max(format.round(ms / 1000), 0);
  if (s < 60) return t("core-logic.jobs.span.seconds", { n: s });
  if (s < 3600) return t("core-logic.jobs.span.minutes", { n: Math.trunc(s / 60) });
  if (s < 86_400) return t("core-logic.jobs.span.hours", { n: Math.trunc(s / 3600) });
  return t("core-logic.jobs.span.days", { n: Math.trunc(s / 86_400) });
}

/// How long ago: 刚刚, 12 秒前, 4 分钟前, 3 小时前, 昨天, 2 天前.
export function ago(at: number, now: number): string {
  const s = format.round((now - at) / 1000);
  if (s < 5) return t("core-logic.jobs.ago.now");
  if (s >= 86_400 && s < 2 * 86_400) return t("core-logic.jobs.ago.yesterday");
  return t("core-logic.jobs.ago", { span: span(now - at) });
}

/// How long until `span` (and so `ago`) of a time `ms` ago says something else.
export function nextChange(ms: number): number {
  const s = Math.max(format.round(ms / 1000), 0);
  const unit = s < 60 ? 1 : s < 3600 ? 60 : s < 86_400 ? 3600 : 86_400;
  const next = (Math.floor(s / unit) + 1) * unit;
  return Math.max((next - 0.5) * 1000 - ms, 100);
}

/// When what `shown` says of a job next changes, from `now`.
export function jobChanges(job: J, now: number): number {
  const times = ["startedAt", "endedAt", "outputAt"].map((f) => msOf(job, f)).filter((x): x is number => x !== null);
  for (const n of arr(get(job, "notices"))) if (typeof get(n, "at") === "number") times.push(n.at);
  let next = times.reduce((m, at) => Math.min(m, nextChange(now - at)), Infinity);
  if (tone(job) === "fail") {
    const until = (msOf(job, "endedAt") ?? msOf(job, "startedAt") ?? 0) + NEWS - now;
    if (until > 0) next = Math.min(next, until);
  }
  return next;
}

/// A job with what the clients show of it put in.
export function shown(input: J, c: Clock): J {
  if (input === null || typeof input !== "object" || Array.isArray(input)) return structuredClone(input);
  const job = structuredClone(input);
  const now = c.now;
  const tn = tone(job);
  const w = word(job);
  const service = isService(job);
  const state = strOf(job, "state");
  const started = msOf(job, "startedAt") ?? now;
  const endedAt = msOf(job, "endedAt");
  const ended = endedAt !== null ? ago(endedAt, now) : null;
  const saidWord = () => ({ text: w, kind: "word" });
  const plain = (text: string) => ({ text });
  const then = (parts: J[], text: string | null) => {
    if (text !== null) parts.push(plain(` · ${text}`));
  };
  const meta: J[] = [];
  const notices = arr(get(job, "notices"));
  if (service) {
    meta.push(saidWord());
    if (tn === "up") then(meta, span(now - started));
    else if (tn === "restart") {
      const r = intOf(get(job, "restarts"));
      then(meta, r !== null && r > 0 ? t("core-logic.jobs.restart_count", { n: r }) : null);
    } else then(meta, ended);
  } else if (tn === "live") {
    const last = notices[0];
    const outputAt = msOf(job, "outputAt");
    if (last !== undefined) {
      meta.push({ text: strOf(last, "text"), kind: "notice" });
      then(meta, ago(typeof get(last, "at") === "number" ? last.at : now, now));
    } else if (outputAt !== null) meta.push(plain(t("core-logic.jobs.no_notice", { ago: ago(outputAt, now) })));
    else {
      meta.push(saidWord());
      then(meta, span(now - started));
    }
  } else if (tn === "fail" && state !== "failed") {
    meta.push(saidWord());
    const code = intOf(get(job, "exitCode"));
    then(meta, code !== null ? t("core-logic.jobs.exit_code", { code }) : t("core-logic.jobs.signalled"));
    then(meta, ended);
  } else {
    meta.push(saidWord());
    then(meta, ended);
  }
  const when = state === "running" ? span(now - started) : (ended ?? "");
  const told = notices.length === 0 ? "" : ` · ${t("core-logic.jobs.notices", { n: notices.length })}`;
  job.tone = tn;
  job.service = service;
  job.open = service && (state === "running" || state === "exited");
  job.ended = isEnded(job);
  job.current = isCurrent(job, now);
  job.word = w;
  job.meta = meta;
  job.detail = `${w} · ${when}${told}`;
  const outputAt = msOf(job, "outputAt");
  job.outputSaid = outputAt !== null ? t("core-logic.jobs.output_at", { ago: ago(outputAt, now) }) : null;
  job.age = span(now - started);
  if (Array.isArray(job.notices)) {
    for (const n of job.notices) {
      if (n === null || typeof n !== "object") continue;
      const at = typeof n.at === "number" ? n.at : now;
      n.ago = ago(at, now);
      n.clock = format.dayClock(at, now, c.offsetMin);
    }
  }
  return job;
}

/// A chat's services and jobs as its pages show them (`ChatJobsView`), and in how many ms what it says changes.
export function chatJobs(chat: J, c: Clock): [J, number] {
  const jobs: J[] = arr(get(chat, "agents")).flatMap((a) => arr(get(a, "jobs")));
  const next = jobs.reduce((m, j) => Math.min(m, jobChanges(j, c.now)), Infinity);
  jobs.sort((a, b) => rank(tone(a)) - rank(tone(b)) || (msOf(b, "startedAt") ?? 0) - (msOf(a, "startedAt") ?? 0));
  const current = jobs.filter((j) => isCurrent(j, c.now));
  const count = (service: boolean, tn: string) => current.filter((j) => isService(j) === service && tone(j) === tn).length;
  const alarm = current.some((j) => tone(j) === "fail") ? "fail" : current.some((j) => tone(j) === "restart") ? "restart" : null;
  const servicesNote = (
    [
      [count(true, "up"), "core-logic.jobs.services.up"],
      [count(true, "restart"), "core-logic.jobs.services.restarting"],
    ] as [number, string][]
  )
    .filter(([k]) => k > 0)
    .map(([k, key]) => t(key, { n: k }))
    .join(t("core-logic.jobs.list_sep"));
  const live = count(false, "live");
  const jobsNote = live === 0 ? "" : t("core-logic.jobs.live_count", { n: live });
  const ended = jobs.filter(isEnded);
  const clear: string[] = [];
  for (const s of ended.map((j) => strOf(j, "session")).filter((s) => s !== "")) if (!clear.includes(s)) clear.push(s);
  return [
    {
      alarm,
      servicesNote,
      jobsNote,
      current: current.length,
      ended: ended.length,
      clear,
      allText: t("core-logic.jobs.all", { n: jobs.length }),
      clearText: t("core-logic.jobs.clear", { n: ended.length }),
      hiddenText: t("core-logic.jobs.hidden", { n: jobs.length - current.length }),
      jobs: jobs.map((j) => shown(j, c)),
    },
    next,
  ];
}

/// Those of the stations' open jobs up longer than `LONG`, watches aside, oldest first, services and jobs apart.
export function longJobs(stations: [string, string | null, J[]][], c: Clock): J {
  const long: J[] = [];
  for (const [address, name, jobs] of stations) {
    for (const j of jobs) {
      if (isWatch(j) || c.now - (msOf(j, "startedAt") ?? c.now) < LONG) continue;
      const job = shown(j, c);
      const chat = get(j, "chat");
      const chatObj = chat !== null && typeof chat === "object" && !Array.isArray(chat) ? chat : null;
      const title = chatObj && strOf(chatObj, "title") !== "" ? strOf(chatObj, "title") : t(chatObj ? "core-logic.jobs.where.chat" : "core-logic.jobs.where.none");
      const archived = get(chatObj, "archived") === true ? t("core-logic.jobs.where.archived") : null;
      job.station = address;
      job.stationName = name;
      job.whereText = [name, title, archived].filter((x) => x !== null).join(" · ");
      long.push(job);
    }
  }
  long.sort((a, b) => (msOf(a, "startedAt") ?? 0) - (msOf(b, "startedAt") ?? 0));
  const groups = (
    [
      ["services", "core-logic.jobs.long.services", true],
      ["jobs", "core-logic.jobs.long.jobs", false],
    ] as [string, string, boolean][]
  ).flatMap(([key, head, service]) => {
    const list = long.filter((j) => isService(j) === service);
    return list.length === 0 ? [] : [{ key, head: `${t(head)} · ${list.length}`, jobs: list }];
  });
  return { groups };
}

/// A job's output as read, with its last line and when it grew in words put in (`JobLogView`).
export function log(value: J, c: Clock): void {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return;
  const last = strOf(value, "text").trim();
  const at = msOf(value, "outputAt");
  if (last !== "") value.last = last;
  if (at !== null || last !== "") value.said = at === null ? t("core-logic.jobs.output") : t("core-logic.jobs.output_at", { ago: ago(at, c.now) });
}
