// Background jobs and web services as the clients show them: each job's dot, its state in a word and the
// line under its name (`shown`), a chat's all together (`chatJobs`), those left up a long while (`longJobs`). Times in
// words here count in seconds, so what shows them is computed again when the next of them changes (`nextChange`).
import * as format from "./format.ts";
import { said } from "./format.ts";
import { t } from "./i18n.ts";
import type { Clock } from "./present.ts";
import { type LogLine, linesOf } from "./log-lines.ts";
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

/// Whether a job still matters to the person: a service that is up, restarting or died within the day (it was there for
/// them to use), a task while it runs. A task that ended is over however it ended: its exit went to its agent, which
/// acts on it (a watch exits non-zero when what it watched failed).
function isCurrent(job: J, now: number): boolean {
  const tn = tone(job);
  if (tn === "off") return false;
  if (!isService(job) && tn !== "live") return false;
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

/// How long ago: 刚刚, 12 秒前, 4 分钟前, 3 小时前, 1 天前. Counted in elapsed time, so never 昨天: 40 hours back can be two days back.
export function ago(at: number, now: number): string {
  const s = format.round((now - at) / 1000);
  if (s < 5) return t("core-logic.jobs.ago.now");
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
  const meta: J[] = [];
  const then = (text: string | null) => {
    if (text !== null) meta.push(plain(` · ${text}`));
  };
  const notices = arr(get(job, "notices"));
  if (service) {
    meta.push(saidWord());
    if (tn === "up") then(span(now - started));
    else if (tn === "restart") {
      const r = intOf(get(job, "restarts"));
      then(r !== null && r > 0 ? t("core-logic.jobs.restart_count", { n: r }) : null);
    } else then(ended);
  } else if (tn === "live") {
    const last = notices[0];
    const outputAt = msOf(job, "outputAt");
    if (last !== undefined) {
      meta.push({ text: strOf(last, "text"), kind: "notice" });
      then(ago(typeof get(last, "at") === "number" ? last.at : now, now));
    } else if (outputAt !== null) meta.push(plain(t("core-logic.jobs.no_notice", { ago: ago(outputAt, now) })));
    else {
      meta.push(saidWord());
      then(span(now - started));
    }
  } else if (tn === "fail" && state !== "failed") {
    meta.push(saidWord());
    const code = intOf(get(job, "exitCode"));
    then(code !== null ? t("core-logic.jobs.exit_code", { code }) : t("core-logic.jobs.signalled"));
    then(ended);
  } else {
    meta.push(saidWord());
    then(ended);
  }
  const when = state === "running" ? span(now - started) : (ended ?? "");
  const told = notices.length === 0 ? "" : ` · ${t("core-logic.jobs.notices", { n: notices.length })}`;
  job.tone = tn;
  job.service = service;
  job.open = service && (state === "running" || state === "exited");
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
export function chatJobs(chat: J, c: Clock, summary = false): [J, number] {
  if (summary) {
    // The chat's bar needs only whether the button exists (a job that matters now) and its alarm. Preparing and
    // copying every job is left for the jobs page. A recent failure can cease to be news even when the station sends
    // no change.
    let hasJobs = false;
    let alarm: string | null = null;
    let next = Infinity;
    for (const agent of arr(get(chat, "agents"))) for (const job of arr(get(agent, "jobs"))) {
      const tn = tone(job);
      if (!isCurrent(job, c.now)) continue;
      hasJobs = true;
      if (tn === "fail") {
        const until = (msOf(job, "endedAt") ?? msOf(job, "startedAt") ?? 0) + NEWS - c.now;
        if (until > 0) {
          alarm = "fail";
          next = Math.min(next, until);
        }
      } else if (tn === "restart" && alarm === null) alarm = "restart";
    }
    return [{ jobs: [], hasJobs, alarm, servicesNote: "", jobsNote: "", allText: "" }, next];
  }
  // Only what matters now (`isCurrent`): a job that is over is not shown at all.
  const all: J[] = arr(get(chat, "agents")).flatMap((a) => arr(get(a, "jobs")));
  const next = all.reduce((m, j) => Math.min(m, jobChanges(j, c.now)), Infinity);
  const jobs = all.filter((j) => isCurrent(j, c.now));
  jobs.sort((a, b) => rank(tone(a)) - rank(tone(b)) || (msOf(b, "startedAt") ?? 0) - (msOf(a, "startedAt") ?? 0));
  const count = (service: boolean, tn: string) => jobs.filter((j) => isService(j) === service && tone(j) === tn).length;
  const alarm = jobs.some((j) => tone(j) === "fail") ? "fail" : jobs.some((j) => tone(j) === "restart") ? "restart" : null;
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
  return [
    {
      alarm,
      servicesNote,
      jobsNote,
      allText: t("core-logic.jobs.all", { n: jobs.length }),
      jobs: jobs.map((j) => shown(j, c)),
    },
    next,
  ];
}

/// Whose a task another station's agent runs here is (station/src/jobs/remote.ts names it
/// `remote:<workspace>:<station>:<session>`): that station's address and the session there.
export function remoteOwner(session: string): { station: string; session: string } | null {
  const m = /^remote:([^:/]+):([^:/]+):(.+)$/.exec(session);
  return m ? { station: `${m[1]}/${m[2]}`, session: m[3]! } : null;
}

/// The chat on another station a task runs for (`remoteOwner`): that station's name, and the chat as its sidebar has
/// it (`station` its address), none when its row is not known here.
export interface From {
  name: string;
  chat: { id: string; title: string | null; archived: boolean; station: string } | null;
}

/// How the rail's bell takes the jobs left up long: whether they light it at all (`badgeKinds.services`), and those it
/// has shown already (`jobsSeen`, `<station>/<id>`).
export type Bell = { on: boolean; seen: Set<string> };

/// A station's screens as its `screens` topic has them (screens.ts `screensView`), for those left up long.
export type HeldScreens = [address: string, name: string | null, screens: J[]];

/// What costs a station while nobody uses it, besides its jobs (`longJobs`): its simulators and emulators up longer
/// than `LONG` (`since`, closed from here: `screen.close`), and people's views of its screens open that long
/// (`screen.endView`): each as a job is shown, with `stop` saying how it is stopped. Only those the viewer may stop;
/// a view on this device aside (it is in sight here), and an agent's (it goes 60 s after its last use).
export function longScreens(stations: HeldScreens[], c: Clock): { simulators: J[]; views: J[] } {
  const simulators: J[] = [];
  const views: J[] = [];
  const row = (address: string, name: string | null, id: string, title: string, startedAt: number, where: (string | null)[], stop: J): J => ({
    id, name: title, state: "running", startedAt, tone: "live", service: false, age: span(c.now - startedAt),
    station: address, stationName: name, whereText: [name, ...where].filter((x) => x !== null && x !== "").join(" · "), stop,
  });
  for (const [address, name, screens] of stations) {
    for (const s of screens) {
      const id = strOf(s, "id");
      const since = msOf(s, "since");
      if (id !== "" && since !== null && get(s, "closable") === true && c.now - since >= LONG) {
        const kind = id.startsWith("android:") ? "core-logic.jobs.long.android" : "core-logic.jobs.long.ios";
        simulators.push(row(address, name, `screen:${id}`, strOf(s, "title"), since, [t(kind)], { call: "screen.close", screen: id, word: t("core-logic.jobs.long.shutdown") }));
      }
      for (const v of arr(get(s, "views"))) {
        const at = msOf(v, "at");
        if (at === null || get(v, "may") !== true || get(v, "agent") === true || get(v, "here") === true || c.now - at < LONG) continue;
        views.push(row(address, name, `view:${id}/${strOf(v, "id")}`, strOf(s, "title"), at, [strOf(v, "name"), strOf(v, "device")], { call: "screen.endView", screen: id, view: strOf(v, "id"), word: t("core-logic.jobs.long.disconnect") }));
      }
    }
  }
  return { simulators, views };
}

/// How long until one of the stations' jobs or screens not up `LONG` yet is (null: none will be).
export function longNext(stations: [string, string | null, J[]][], screens: HeldScreens[], now: number): number | null {
  const starts: number[] = [];
  for (const [, , jobs] of stations) for (const j of jobs) if (!isWatch(j) && msOf(j, "startedAt") !== null) starts.push(j.startedAt);
  for (const [, , list] of screens) {
    for (const s of list) {
      const since = msOf(s, "since");
      if (since !== null && get(s, "closable") === true) starts.push(since);
      for (const v of arr(get(s, "views"))) if (msOf(v, "at") !== null && get(v, "may") === true && get(v, "agent") !== true) starts.push(v.at);
    }
  }
  const left = starts.map((at) => at + LONG - now).filter((ms) => ms > 0);
  return left.length === 0 ? null : Math.min(...left);
}

/// Those of the stations' open jobs up longer than `LONG`, watches aside, oldest first, services and jobs apart; then
/// their simulators and people's views of their screens up that long (`longScreens`). A task run for another station's
/// chat (`from`, by its session) is in that chat, and says which station it came from. The bell's dot (`lit`) while one
/// is there it has not shown yet; `ids` are what it keeps as shown once it opens.
export function longJobs(stations: [string, string | null, J[]][], c: Clock, from: (session: string) => From | null = () => null, bell: Bell = { on: true, seen: new Set() }, screens: HeldScreens[] = []): J {
  const long: J[] = [];
  for (const [address, name, jobs] of stations) {
    for (const j of jobs) {
      if (isWatch(j) || c.now - (msOf(j, "startedAt") ?? c.now) < LONG) continue;
      const job = shown(j, c);
      const chat = get(j, "chat");
      let chatObj = chat !== null && typeof chat === "object" && !Array.isArray(chat) ? chat : null;
      const elsewhere = chatObj === null ? from(strOf(j, "session")) : null;
      if (elsewhere?.chat) chatObj = job.chat = elsewhere.chat;
      const title = chatObj && strOf(chatObj, "title") !== "" ? strOf(chatObj, "title")
        : t(chatObj || elsewhere ? "core-logic.jobs.where.chat" : "core-logic.jobs.where.none");
      const archived = get(chatObj, "archived") === true ? t("core-logic.jobs.where.archived") : null;
      const origin = elsewhere ? t("core-logic.jobs.where.from", { station: elsewhere.name }) : null;
      job.station = address;
      job.stationName = name;
      job.whereText = [name, title, archived, origin].filter((x) => x !== null).join(" · ");
      long.push(job);
    }
  }
  const oldest = (a: J, b: J) => (msOf(a, "startedAt") ?? 0) - (msOf(b, "startedAt") ?? 0);
  long.sort(oldest);
  const { simulators, views } = longScreens(screens, c);
  simulators.sort(oldest);
  views.sort(oldest);
  const groups = (
    [
      ["services", "core-logic.jobs.long.services", long.filter((j) => isService(j))],
      ["jobs", "core-logic.jobs.long.jobs", long.filter((j) => !isService(j))],
      ["simulators", "core-logic.jobs.long.simulators", simulators],
      ["views", "core-logic.jobs.long.views", views],
    ] as [string, string, J[]][]
  ).flatMap(([key, head, list]) => (list.length === 0 ? [] : [{ key, head: `${t(head)} · ${list.length}`, jobs: list }]));
  const ids = [...long, ...simulators, ...views].map((j) => `${j.station}/${strOf(j, "id")}`);
  return { groups, lit: bell.on && ids.some((id) => !bell.seen.has(id)), ids };
}

/// A job's output as read (`JobLogView`): its lines as a terminal shows them, each its runs of one style and its number
/// (log-lines.ts: what the link kept, `from` its first's), with its last line with words in it and when it grew in
/// words put in. Asked for its last line alone (`lines` 1: a job's row), those two alone, no lines.
export function log(value: J, c: Clock, asked: unknown = null): J {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return value;
  // (one already shown, its lines made and its text gone, as it is: present.ts may shape a value twice)
  if (typeof value.text !== "string" && Array.isArray(value.lines)) return value;
  const all = linesOf(strOf(value, "text"));
  const from = typeof value.from === "number" ? value.from : 0;
  let last = "";
  for (let i = all.length - 1; i >= 0 && last === ""; i--) last = all[i]!.map((r) => r.text).join("").trim();
  const at = msOf(value, "outputAt");
  const { text: _text, runs: _runs, from: _from, lines: _lines, ...rest } = value;
  return {
    ...rest,
    ...(asked !== 1 ? { lines: all.map((runs, i): LogLine => ({ n: from + i, runs })) } : {}),
    ...(last !== "" ? { last } : {}),
    ...(at !== null || last !== "" ? { said: at === null ? t("core-logic.jobs.output") : t("core-logic.jobs.output_at", { ago: ago(at, c.now) }) } : {}),
  };
}
