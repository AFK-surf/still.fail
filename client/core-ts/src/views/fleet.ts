// The card shared of a workspace's agents at work (the `fleet` view; 2026-10-26 用户：「来点花哨的设计和更多信息」，then 「改成
// xx 个 xx 订阅账号的 xx% 周额度，分天和周统计，还有当前 chat 数量」「模型调用不需要」「不如归档 chat 多少个」): how much of
// its subscriptions' weekly quota was used, by kind of subscription; how many chats were archived and what was spent
// today and over the last 7 days, each day's chats archived; how many chats are at work now and on how many stations
// (a chat whose task runs on another station at work too); how many tasks chats ran on other stations over the 7 days,
// and how many each chat that did, on average (「一个 station 的 chat 在另一个 station 执行任务也需要统计」「应该是有一个额
// 外的统计，比如总共跨设备执行了多少个任务，平均每个 chat 跨设备执行多少个任务」).
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import { isWatch, remoteOwner } from "../jobs.ts";
import * as present from "../present.ts";
import { arr as arrU, get as getU } from "../util.ts";
import { GROUPS, groupTitle } from "./profiles.ts";
import { localDay } from "./usage.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// A station as the card reads it: up or not, its chats' rows as listed, when each of its archived chats was archived,
/// its jobs (the tasks other stations' chats run on it among them), the tasks other stations' chats ran on it (when
/// each began, and whose session: its usage's `remoteRuns`).
export type FleetStation = { station: string; online: boolean; rows: J[]; archived: number[]; jobs: J[]; runs: { at: number; session: string }[] };

/// Whether a quota's window is its week's (每周…, Weekly…, 7 天).
function weekly(w: J): boolean {
  const [mark] = format.windowMark(str(get(w, "label")) ?? "");
  return mark === "W" || mark === "7D";
}

/// The workspace's subscriptions by kind (the profiles view's items), each kind's accounts with a week's quota read and
/// how much of a week's quota they used in all, each account's share of its own added up: two can use more than one's
/// (80% and 90%: 170%, 1.7 accounts' weeks), and that as a share of all their weeks (`share`, its ring: 170% of two,
/// 0.85). The most accounts first; a kind that used none (0%) left out (「0% 不要显示」). Keys (API Key) have no quota.
export function quotaOf(profiles: J[]): J[] {
  const kinds = new Map<string, number[]>();
  for (const p of profiles) {
    const kind = str(get(p, "group"));
    if (kind === null || kind === "key") continue;
    const quota = get(get(p, "profile"), "quota");
    if (get(quota, "state") !== "ok") continue;
    const week = arr(get(quota, "windows")).find(weekly);
    if (week === undefined || typeof week.usedPercent !== "number") continue;
    kinds.set(kind, [...(kinds.get(kind) ?? []), week.usedPercent]);
  }
  const order = (k: string) => GROUPS.indexOf(k as (typeof GROUPS)[number]);
  return [...kinds.entries()]
    .sort((a, b) => b[1].length - a[1].length || order(a[0]) - order(b[0]))
    .map(([kind, used]) => {
      const all = used.reduce((n, u) => n + u, 0);
      const percent = format.round(all);
      const share = Math.min(1, all / (used.length * 100));
      return { kind, accounts: used.length, used: percent, usedText: `${percent}%`, share, text: t("core-logic.fleet.quota", { n: used.length, kind: groupTitle(kind as (typeof GROUPS)[number]) }) };
    })
    .filter((q) => q.used > 0);
}

/// The card: `stations` as read, the workspace's profiles (the profiles view's items), the usage view of the last 7 days
/// (null while it is not made yet), and when it is (`at`, in words: 10月26日 04:12), on a clock `offset` minutes east of
/// UTC (the usage view's days'). A chat is at work while its agents run, or while a task it started runs on another
/// station (`remoteOwner`; one waiting in that station's queue not yet); the stations at work are those of the chats at
/// work (the tasks' are said apart: `days`).
export function fleetView(stations: FleetStation[], profiles: J[], usage: J, at = "", offset = 0): J {
  const online = stations.filter((s) => s.online);
  const chats = new Set<string>();
  const working = new Set<string>();
  const archived: number[] = [];
  const runs: { at: number; session: string }[] = [];
  for (const s of online) {
    archived.push(...s.archived);
    runs.push(...s.runs);
    for (const row of s.rows) {
      if (present.rowState(arr(get(row, "agents"))) !== "run") continue;
      chats.add(`${s.station}\n${str(get(row, "id")) ?? ""}`);
      working.add(s.station);
    }
  }
  for (const s of online) {
    for (const job of s.jobs) {
      if (get(job, "state") !== "running" || get(job, "queued") === true || isWatch(job)) continue;
      const owner = remoteOwner(str(get(job, "session")) ?? "");
      const home = owner && online.find((o) => o.station === owner.station);
      if (!owner || !home) continue;
      // its chat as its station lists it: the session's own, or one it takes part in; else the session alone
      const row = home.rows.find((r) => get(r, "session") === owner.session) ??
        home.rows.find((r) => arr(get(r, "agents")).some((a) => get(a, "key") === owner.session));
      chats.add(`${home.station}\n${row ? (str(get(row, "id")) ?? "") : owner.session}`);
      working.add(home.station);
    }
  }
  return {
    at,
    quotaLead: t("core-logic.fleet.quota_lead"),
    quota: quotaOf(profiles),
    chats: chats.size,
    chatsText: t("core-logic.fleet.chats", { n: chats.size }),
    where: t("core-logic.fleet.machines", { n: working.size }),
    ...(days(usage, archived, runs, offset) ?? {}),
  };
}

/// Today and the last 7 days: how many chats were archived, and what was spent as the usage view has it (today's cost;
/// the week's input tokens and cost, its tiles); each day's chats archived as a share of the most on a day, and its
/// date; the tasks chats ran on other stations over them (`runs`), and how many each chat that ran any did, on average
/// (by its session: a chat's own agent), none said with none run. None while the usage is read, or with nothing spent
/// nor archived.
function days(usage: J, archived: number[], runs: { at: number; session: string }[], offset: number): J {
  if (usage === null || usage === undefined) return null;
  const tiles = arr(get(usage, "tiles"));
  const daily = arr(get(usage, "daily"));
  if (tiles.length < 3 || daily.length === 0) return null;
  const on = new Map<string, number>();
  for (const at of archived) {
    const day = localDay(at, offset);
    on.set(day, (on.get(day) ?? 0) + 1);
  }
  const count = (d: J) => on.get(str(d.day) ?? "") ?? 0;
  const week = daily.reduce((n, d) => n + count(d), 0);
  if (week === 0 && get(usage, "empty") === true) return null;
  const most = Math.max(...daily.map(count), 1);
  const stat = (x: J) => ({ label: str(get(x, "label")) ?? "", value: str(get(x, "value")) ?? "" });
  const chats = (n: number) => ({ label: t("core-logic.fleet.archived"), value: t("core-logic.fleet.archived_value", { n }) });
  const today = daily.find((d) => d.today === true) ?? daily[daily.length - 1];
  const shown = new Set(daily.map((d) => str(d.day)));
  const ran = runs.filter((r) => shown.has(localDay(r.at, offset)));
  const by = new Set(ran.map((r) => r.session)).size;
  const tasks = ran.length === 0 ? {} : {
    tasksText: t("core-logic.fleet.tasks", { n: ran.length }),
    tasksPer: t("core-logic.fleet.tasks_per", { n: Math.round((ran.length / by) * 10) / 10 }),
  };
  return {
    ...tasks,
    today: {
      title: t("core-logic.fleet.today"),
      stats: [chats(count(today)), { label: str(get(tiles[0], "label")) ?? "", value: str(today.costText) ?? "" }],
    },
    week: {
      title: t("core-logic.fleet.week"),
      stats: [chats(week), stat(tiles[2]), stat(tiles[0])],
      days: daily.map((d) => ({ label: str(d.label) ?? "", share: count(d) / most, today: d.today === true })),
    },
  };
}
