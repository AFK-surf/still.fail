// The usage page's summary, after Codex's usage summary (openai/codex codex-rs/tui/src/analytics/summary_panel.rs,
// activity_chart.rs), with still.fail's own figures (2026-11-02 用户：「缺了我们自己的特色数据，比如跨 station 任务执行」「归档
// chat 数量」「决策点击率」「连续多少天那个没用」): from every station's `history` (GET /usage?history=1, station
// read/usage.ts usageHistory), five figures (the tokens in all, the chats archived, the tasks run across devices, the
// share of decision cards answered by an option pressed, the devices that worked); a year of days, each its level of the
// most of a day (Codex's graded levels), or each week's tokens, or their running total; what each device did and where
// the chats came from. A station from before (no `history`) or one not read leaves its part out, said in `partial`.
import { t } from "../i18n.ts";
import * as format from "../format.ts";
import { arr as arrU, get as getU } from "../util.ts";
import { count, localDay, type Source } from "./usage.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const DAY_MS = 86_400_000;
/// The year's weeks, each a column of its seven days, Sunday first (Codex's WEEK_COUNT, DAY_COUNT).
export const WEEKS = 52;
const WEEK_DAYS = 7;
/// Where chats come from, by their surface's kind: still.fail's own, Slack, Feishu.
function placeName(place: string): string {
  if (place === "ember") return "still.fail";
  if (place === "slack") return "Slack";
  if (place === "feishu") return t("core-views.usage.summary.feishu");
  return place;
}

/// A day's level of the most of a day (Codex's graded_levels): none 0, then 1 to 4 by quarters of the most.
export function level(value: number, most: number): number {
  if (value <= 0 || most <= 0) return 0;
  if (value * 4 > most * 3) return 4;
  if (value * 2 > most) return 3;
  if (value * 4 > most) return 2;
  return 1;
}

/// How many of a week's seven rows a bar fills, of the tallest (Codex's bar_levels): at least one for any at all.
function height(value: number, most: number): number {
  if (value <= 0 || most <= 0) return 0;
  return Math.ceil((value * WEEK_DAYS) / most);
}

/// The day `n` days after `day` (YYYY-MM-DD).
function plus(day: string, n: number): string {
  const ms = Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10))) + n * DAY_MS;
  return localDay(ms, 0);
}

/// The weekday of `day`, Sunday 0.
function weekday(day: string): number {
  const ms = Date.UTC(Number(day.slice(0, 4)), Number(day.slice(5, 7)) - 1, Number(day.slice(8, 10)));
  return (Math.floor(ms / DAY_MS) + 4) % 7;
}

/// The summary of `sources`' histories, `now` on a clock `offset` minutes east of UTC; `title` whose it is (the
/// workspace's name). Null where no station has a history to say.
export function usageSummary(sources: Source[], now: number, offset: number, title: string): J | null {
  const today = localDay(now, offset);
  const byDay = new Map<string, number>();
  const byStation: [string, number][] = [];
  const places = new Map<string, number>();
  let total = 0;
  let archived = 0;
  let remote = 0;
  let cards = 0;
  let picked = 0;
  let read = 0;
  let missing = 0;
  const num = (v: unknown, k: string): number => (typeof get(v, k) === "number" ? get(v, k) : 0);
  for (const s of sources) {
    const history = s.value !== undefined && "ok" in s.value ? get(s.value.ok, "history") : undefined;
    if (history === undefined || history === null) {
      missing++;
      continue;
    }
    read++;
    archived += num(history, "archived");
    remote += num(history, "remoteRuns");
    cards += num(history, "cards");
    picked += num(history, "picked");
    const placed = get(history, "places");
    if (placed !== null && typeof placed === "object") for (const [k, n] of Object.entries(placed)) if (typeof n === "number") places.set(k, (places.get(k) ?? 0) + n);
    let mine = 0;
    for (const d of arr(get(history, "days"))) {
      const day = typeof get(d, "day") === "string" ? d.day : "";
      const tokens = num(d, "tokens");
      if (day === "" || day > today || tokens <= 0) continue;
      byDay.set(day, (byDay.get(day) ?? 0) + tokens);
      total += tokens;
      mine += tokens;
    }
    if (mine > 0) byStation.push([s.name, mine]);
  }
  if (read === 0) return null;
  const share = (part: number, whole: number) => (whole > 0 ? `${Math.round((part / whole) * 100)}%` : "—");
  const figures = [
    { label: t("core-views.usage.summary.lifetime"), value: count(total) },
    { label: t("core-views.usage.summary.archived"), value: count(archived) },
    { label: t("core-views.usage.summary.remote"), value: count(remote) },
    { label: t("core-views.usage.summary.picked"), value: share(picked, cards) },
    { label: t("core-views.usage.summary.stations"), value: String(byStation.length) },
  ];
  // the year: 52 weeks of days, Sunday first, the last week today's (Codex's chart_start); a day after today none
  const start = plus(today, -weekday(today) - (WEEKS - 1) * WEEK_DAYS);
  const values: number[] = [];
  for (let i = 0; i < WEEKS * WEEK_DAYS; i++) values.push(byDay.get(plus(start, i)) ?? 0);
  const most = Math.max(0, ...values);
  const cells = values.map((v, i) => (plus(start, i) > today ? -1 : level(v, most)));
  const weeks: number[] = [];
  for (let w = 0; w < WEEKS; w++) weeks.push(values.slice(w * WEEK_DAYS, (w + 1) * WEEK_DAYS).reduce((a, b) => a + b, 0));
  const running: number[] = [];
  weeks.reduce((sum, v) => (running.push(sum + v), sum + v), 0);
  const tallest = Math.max(0, ...weeks);
  const top = running[running.length - 1] ?? 0;
  // each month's name over the week its first days are in (Codex's month_labels)
  const months: J[] = [];
  const names = t("core-views.usage.summary.months").split(",");
  for (let w = 0; w < WEEKS; w++) {
    const day = plus(start, w * WEEK_DAYS);
    if (Number(day.slice(8, 10)) <= 7) months.push({ week: w, label: names[Number(day.slice(5, 7)) - 1] ?? "" });
  }
  const year = values.some((v) => v > 0);
  // what each is, said as the pointer rests on it: a day its date and tokens, a week its first day and tokens, the
  // running total as of the week's last day so far
  const tokens = (n: number) => (n > 0 ? t("core-views.usage.summary.tokens", { n: count(n) }) : t("core-views.usage.summary.no_tokens"));
  const tips = values.map((v, i) => (plus(start, i) > today ? "" : t("core-views.usage.summary.day_tip", { date: format.monthDayOf(plus(start, i)), tokens: tokens(v) })));
  const weekTips = weeks.map((v, w) => t("core-views.usage.summary.week_tip", { date: format.monthDayOf(plus(start, w * WEEK_DAYS)), tokens: tokens(v) }));
  const runningTips = running.map((v, w) => {
    const last = plus(start, w * WEEK_DAYS + WEEK_DAYS - 1);
    return t("core-views.usage.summary.running_tip", { date: format.monthDayOf(last > today ? today : last), tokens: tokens(v) });
  });
  byStation.sort((x, y) => y[1] - x[1]);
  const placed = [...places].sort((x, y) => y[1] - x[1]);
  return {
    title,
    figures,
    activity: {
      title: t("core-views.usage.summary.activity"),
      sub: t("core-views.usage.summary.year"),
      views: [t("core-views.usage.summary.view.daily"), t("core-views.usage.summary.view.weekly"), t("core-views.usage.summary.view.cumulative")],
      weekdays: t("core-views.usage.summary.weekdays").split(","),
      months,
      cells,
      weekly: weeks.map((v) => height(v, tallest)),
      cumulative: running.map((v) => height(v, top)),
      tips,
      weekTips,
      runningTips,
      less: t("core-views.usage.summary.less"),
      more: t("core-views.usage.summary.more"),
      captions: year
        ? ["", t("core-views.usage.summary.weekly_caption", { n: count(tallest) }), t("core-views.usage.summary.cumulative_caption", { n: count(top) })]
        : [t("core-views.usage.summary.no_year"), t("core-views.usage.summary.no_year"), t("core-views.usage.summary.no_year")],
    },
    stations: {
      title: t("core-views.usage.summary.by_station"),
      items: byStation.map(([name, tokens]) => ({ name, value: `${t("core-views.usage.summary.tokens", { n: count(tokens) })} · ${share(tokens, total)}` })),
    },
    // (said only where the chats came from more than one place)
    ...(placed.length > 1
      ? {
          places: {
            title: t("core-views.usage.summary.places"),
            items: placed.map(([place, n]) => ({ name: placeName(place), value: t("core-views.usage.summary.chats_n", { n }) })),
          },
        }
      : {}),
    asOf: t("core-views.usage.summary.as_of", { date: format.monthDayOf(today) }),
    partial: missing > 0 ? t("core-views.usage.summary.partial") : null,
  };
}
