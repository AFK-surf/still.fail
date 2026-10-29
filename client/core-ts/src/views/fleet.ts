// The card shared of a workspace's agents at work (the `fleet` view; 2026-10-26 用户：「来点花哨的设计和更多信息」，then 「改成
// xx 个 xx 订阅账号的 xx% 周额度，分天和周统计，还有当前 chat 数量」「模型调用不需要」「不如归档 chat 多少个」, then of the
// quota 「只算 token 和价格」): what its chats used over the last 7 days, by kind of account; how many chats were archived and what was spent
// today and over the last 7 days, each day's chats archived; how many chats are at work now (a chat whose task runs on
// another station at work too), and how many stations were used today, by today's chats or for the tasks they ran
// (「应该改成今天会话分布在几个设备而不是正在运行的会话」「那不是运行任务没有算进去」); how many tasks chats ran on other
// stations over the 7 days, and how many each chat that did, on average (「一个 station 的 chat 在另一个 station 执行任务也
// 需要统计」「应该是有一个额外的统计，比如总共跨设备执行了多少个任务，平均每个 chat 跨设备执行多少个任务」).
import * as format from "../format.ts";
import { t } from "../i18n.ts";
import { isWatch, remoteOwner } from "../jobs.ts";
import * as present from "../present.ts";
import * as model from "../shapes/model.ts";
import { arr as arrU, get as getU } from "../util.ts";
import { GROUPS, groupTitle } from "./profiles.ts";
import { count, localDay, money } from "./usage.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);
const str = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// A station as the card reads it: up or not, its chats' rows as listed, when each of its archived chats was archived,
/// its jobs (the tasks other stations' chats run on it among them), the tasks other stations' chats ran on it (when
/// each began, and whose session: its usage's `remoteRuns`), its chats' calls (its usage's `rows`: by day, chat,
/// profile and model).
export type FleetStation = { station: string; online: boolean; rows: J[]; archived: number[]; jobs: J[]; runs: { at: number; session: string }[]; calls: J[] };

/// How many of a kind's models are said one by one when it has more than one past them, the rest together.
const MODELS_NAMED = 3;

/// What the workspace's chats used over the last 7 days, by kind of account (2026-10-29 用户：「应该是每个 chat 自己统计」
/// 「用了哪些账号分别用了多少」「只算 token 和价格」; it was how full each account's week read, which counts what was used
/// before the days and outside still.fail, and none of a week that reset in them): the calls each station's chats made
/// on its accounts (`stations`' `calls`, the usage rows of the days `days`), each on the account its profile is (the
/// profiles view's items, `profiles`: an account on two stations once), each kind the accounts that made any and, model by
/// model, their tokens (read and written, the cache's too) and what they would cost at API prices (as the usage page
/// counts them, ≥ with calls without a price): one model's tokens are not another's, so no kind adds its models' up
/// (2026-10-30 用户「token 没有写模型」, then 「按模型分开写 token 和钱」). A kind's models the most tokens first, the first
/// MODELS_NAMED by name, the rest one line; the kinds the most tokens first, each its share of all kinds' tokens its ring.
/// A call of an account no longer listed left out.
export function spentOf(profiles: J[], stations: FleetStation[], days: Set<string>): J[] {
  const accountOf = new Map<string, J>();
  for (const p of profiles) for (const m of arr(get(p, "members"))) accountOf.set(`${get(m, "station")}\n${get(m, "profileId")}`, p);
  type Spent = { tokens: number; cost: number; unpriced: number };
  const kinds = new Map<string, { accounts: Set<string>; tokens: number; models: Map<string, Spent & { name: string }> }>();
  const n = (row: J, k: string) => (typeof get(row, k) === "number" ? row[k] : 0);
  for (const s of stations) {
    for (const row of s.calls) {
      if (!days.has(str(get(row, "day")) ?? "")) continue;
      const account = accountOf.get(`${s.station}\n${str(get(row, "profile")) ?? ""}`);
      const kind = str(get(account, "group"));
      if (account === undefined || kind === null) continue;
      const tokens = n(row, "input") + n(row, "cacheRead") + n(row, "cacheWrite") + n(row, "output");
      if (tokens === 0) continue;
      const k = kinds.get(kind) ?? { accounts: new Set<string>(), tokens: 0, models: new Map() };
      k.accounts.add(String(get(account, "key")));
      k.tokens += tokens;
      const id = str(get(row, "model"));
      const key = id === null ? "" : model.key(id);
      const m = k.models.get(key) ?? { name: id === null ? t("core-views.usage.unknown_which_model") : model.name(id), tokens: 0, cost: 0, unpriced: 0 };
      m.tokens += tokens;
      if (typeof get(row, "cost") === "number") m.cost += row.cost;
      else m.unpriced += n(row, "calls");
      k.models.set(key, m);
      kinds.set(kind, k);
    }
  }
  // a model's tokens and cost: 2.1 亿 · $1,420 (≥$1,420 with calls without a price; none priced, its tokens alone)
  const said = (name: string, m: Spent) => {
    const tokensText = count(m.tokens);
    const priced = m.cost > 0 || m.unpriced === 0;
    const costText = priced ? `${m.unpriced > 0 ? "≥" : ""}${money(m.cost)}` : "";
    return {
      name, tokens: m.tokens, tokensText, costText,
      lineText: priced ? `${tokensText} · ${costText}` : tokensText,
      of: priced ? t("core-logic.fleet.tokens_of", { cost: costText }) : t("core-logic.fleet.tokens"),
    };
  };
  const all = [...kinds.values()].reduce((sum, k) => sum + k.tokens, 0);
  const order = (k: string) => GROUPS.indexOf(k as (typeof GROUPS)[number]);
  return [...kinds.entries()]
    .sort(([a, x], [b, y]) => y.tokens - x.tokens || order(a) - order(b))
    .map(([kind, k]) => {
      const accounts = k.accounts.size;
      // said as a sentence round its first model's tokens: 用 6 个 Claude 订阅账号消耗了 | 2.1 亿 | Opus 5.5 | token，折合 $1,420;
      // or as its ring's key, a line beside the others' (Claude 订阅 · 6 个账号), each model a line under it
      const name = groupTitle(kind as (typeof GROUPS)[number]);
      const lead = kind === "key" ? t("core-logic.fleet.keys_by", { n: accounts }) : t("core-logic.fleet.accounts_by", { n: accounts, kind: name });
      const ranked = [...k.models.values()].sort((a, b) => b.tokens - a.tokens || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
      const named = ranked.length > MODELS_NAMED + 1 ? ranked.slice(0, MODELS_NAMED) : ranked;
      const rest = ranked.slice(named.length);
      const models = named.map((m) => said(m.name, m));
      if (rest.length > 0) {
        const sum = (f: keyof Spent) => rest.reduce((x, m) => x + m[f], 0);
        models.push(said(t("core-logic.fleet.other_models", { n: rest.length }), { tokens: sum("tokens"), cost: sum("cost"), unpriced: sum("unpriced") }));
      }
      return {
        kind, name, accounts, accountsText: t("core-logic.fleet.accounts", { n: accounts }),
        tokens: k.tokens, share: all > 0 ? k.tokens / all : 0, lead, models,
      };
    });
}

/// The card: `stations` as read, the workspace's profiles (the profiles view's items), the usage view of the last 7 days
/// (null while it is not made yet), and when it is (`now`, said in words: 10月26日 04:12), on a clock `offset` minutes
/// east of UTC (the usage view's days'). A chat is at work while its agents run, or while a task it started runs on
/// another station (`remoteOwner`; one waiting in that station's queue not yet); the stations used today are those of
/// today's chats (at work, or their last letter written, or archived, today) and those that ran their tasks today (one
/// running now, or begun today: `runs`).
export function fleetView(stations: FleetStation[], profiles: J[], usage: J, now = 0, offset = 0): J {
  const online = stations.filter((s) => s.online);
  const day = localDay(now, offset);
  const today = (at: unknown) => typeof at === "number" && localDay(at, offset) === day;
  const chats = new Set<string>();
  const used = new Set<string>();
  const archived: number[] = [];
  const runs: { at: number; session: string }[] = [];
  for (const s of online) {
    archived.push(...s.archived);
    runs.push(...s.runs);
    if (s.archived.some(today) || s.runs.some((r) => today(r.at))) used.add(s.station);
    for (const row of s.rows) {
      if (today(get(row, "lastActiveAt"))) used.add(s.station);
      if (present.rowState(arr(get(row, "agents"))) !== "run") continue;
      chats.add(`${s.station}\n${str(get(row, "id")) ?? ""}`);
      used.add(s.station);
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
      used.add(home.station).add(s.station);
    }
  }
  return {
    at: format.dateClock(now, offset),
    spent: spentOf(profiles, online, new Set(Array.from({ length: 7 }, (_, i) => localDay(now - i * 86_400_000, offset)))),
    chats: chats.size,
    chatsText: t("core-logic.fleet.chats", { n: chats.size }),
    where: t("core-logic.fleet.machines", { n: used.size }),
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
      days: daily.map((d) => ({ label: str(d.label) ?? "", share: count(d) / most, value: t("core-logic.fleet.archived_value", { n: count(d) }), today: d.today === true })),
    },
  };
}
