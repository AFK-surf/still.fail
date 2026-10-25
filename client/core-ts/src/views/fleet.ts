// The card shared of a workspace's agents at work (the `fleet` view; 2026-10-26 用户：「来点花哨的设计和更多信息」，then 「改成
// xx 个 xx 订阅账号的 xx% 周额度，分天和周统计，还有当前 chat 数量」「模型调用不需要」「不如归档 chat 多少个」): how much of
// its subscriptions' weekly quota was used, by kind of subscription; how many chats were archived and what was spent
// today and over the last 7 days, each day's chats archived; how many chats are at work now and on how many stations.
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import * as present from "../present.ts";
import { arr as arrU, get as getU } from "../util.ts";
import { GROUPS, groupTitle } from "./profiles.ts";
import { localDay } from "./usage.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// A station as the card reads it: up or not, its chats' rows as listed, when each of its archived chats was archived.
export type FleetStation = { station: string; online: boolean; rows: J[]; archived: number[] };

/// Whether a quota's window is its week's (每周…, Weekly…, 7 天).
function weekly(w: J): boolean {
  const [mark] = format.windowMark(str(get(w, "label")) ?? "");
  return mark === "W" || mark === "7D";
}

/// The workspace's subscriptions by kind (the profiles view's items), each kind's accounts with a week's quota read and
/// how much of a week's quota they used in all, each account's share of its own added up: two can use more than one's
/// (80% and 90%: 170%). The most accounts first. Keys (API Key) have no quota: none of them.
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
      const percent = format.round(used.reduce((n, u) => n + u, 0));
      return { kind, accounts: used.length, used: percent, usedText: `${percent}%`, text: t("core-logic.fleet.quota", { n: used.length, kind: groupTitle(kind as (typeof GROUPS)[number]) }) };
    });
}

/// The card: `stations` as read, the workspace's profiles (the profiles view's items), the usage view of the last 7 days
/// (null while it is not made yet), and when it is (`at`, in words: 10月26日 04:12), on a clock `offset` minutes east of
/// UTC (the usage view's days').
export function fleetView(stations: FleetStation[], profiles: J[], usage: J, at = "", offset = 0): J {
  let chats = 0;
  let working = 0;
  const archived: number[] = [];
  for (const s of stations) {
    if (!s.online) continue;
    archived.push(...s.archived);
    const here = s.rows.filter((row) => present.rowState(arr(get(row, "agents"))) === "run").length;
    chats += here;
    if (here > 0) working += 1;
  }
  return {
    at,
    quotaLead: t("core-logic.fleet.quota_lead"),
    quota: quotaOf(profiles),
    chats,
    chatsText: t("core-logic.fleet.chats", { n: chats }),
    where: t("core-logic.fleet.machines", { n: working }),
    ...(days(usage, archived, offset) ?? {}),
  };
}

/// Today and the last 7 days: how many chats were archived, and what was spent as the usage view has it (today's cost;
/// the week's input tokens and cost, its tiles); each day's chats archived as a share of the most on a day, and its
/// date. None while the usage is read, or with nothing spent nor archived.
function days(usage: J, archived: number[], offset: number): J {
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
  return {
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
