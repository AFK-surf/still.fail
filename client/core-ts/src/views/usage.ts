// What the agents spent (views/usage.rs): every online station's usage put together for a scope's last 7 or 30
// days, as the usage page shows it: a few totals, each day's cost split by who it was for, and who, which chats, which
// accounts and which models spent the most.
import type { CoreError } from "../error.ts";
import { current, t, tr, type Lang } from "../i18n.ts";
import * as present from "../present.ts";
import * as model from "../shapes/model.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";

// deno-lint-ignore no-explicit-any
type J = any;
const arr = (v: unknown): J[] => arrU(v) ?? [];
const get = (v: unknown, k: string): J => getU(v, k);

const DAY_MS = 86_400_000;
/// How many people the days are split by; the rest are 其他.
const SERIES = 4;

/// A station's usage as read, for the view.
export type Source = { address: string; name: string; online: boolean; value: Value | undefined };

const two = (n: number) => String(n).padStart(2, "0");

/// `YYYY-MM-DD` of a moment, on a clock `offset` minutes east of UTC.
export function localDay(ms: number, offset: number): string {
  const days = Math.floor((ms + offset * 60_000) / DAY_MS);
  const z = days + 719_468;
  const era = Math.floor(z / 146_097);
  const doe = z - era * 146_097;
  const yoe = Math.trunc((doe - Math.trunc(doe / 1460) + Math.trunc(doe / 36_524) - Math.trunc(doe / 146_096)) / 365);
  const doy = doe - (365 * yoe + Math.trunc(yoe / 4) - Math.trunc(yoe / 100));
  const mp = Math.trunc((5 * doy + 2) / 153);
  const d = doy - Math.trunc((153 * mp + 2) / 5) + 1;
  const m = mp < 10 ? mp + 3 : mp - 9;
  const y = yoe + era * 400 + (m <= 2 ? 1 : 0);
  return `${String(y).padStart(4, "0")}-${two(m)}-${two(d)}`;
}

/// 10/1 for 2026-10-01.
function dayLabel(day: string): string {
  const part = (a: number, b: number) => {
    const n = Number(day.slice(a, b));
    return Number.isInteger(n) ? n : 0;
  };
  return `${part(5, 7)}/${part(8, 10)}`;
}

/// Dollars: $1,911 · $191 · $12.34 · $0.42 · <$0.01.
export function money(dollars: number): string {
  if (dollars <= 0) return "$0";
  if (dollars < 0.01) return "<$0.01";
  if (dollars < 100) return `$${dollars.toFixed(2)}`;
  return `$${grouped(Math.round(dollars))}`;
}

function grouped(n: number): string {
  const digits = String(Math.abs(n));
  let out = "";
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ",";
    out += digits[i];
  }
  return n < 0 ? `-${out}` : out;
}

/// A count as people read it here: 9,850 · 2.9 万 · 1715 万 · 49.1 亿.
export function count(n: number): string {
  return countIn(current(), n);
}

export function countIn(lang: Lang, n: number): string {
  const cut = (v: number, unit: string) => {
    let s = v >= 100 ? v.toFixed(0) : v.toFixed(1);
    if (s.endsWith(".0")) s = s.slice(0, -2);
    return lang === "en" ? `${s}${unit}` : `${s} ${unit}`;
  };
  if (lang === "en") {
    if (n >= 1e9) return cut(n / 1e9, "B");
    if (n >= 1e6) return cut(n / 1e6, "M");
    if (n >= 1e4) return cut(n / 1e3, "K");
  } else {
    if (n >= 1e8) return cut(n / 1e8, "亿");
    if (n >= 1e4) return cut(n / 1e4, "万");
  }
  return grouped(Math.round(n));
}

function percent(part: number, whole: number): string {
  if (whole <= 0) return "0%";
  const p = (part / whole) * 100;
  return p > 0 && p < 1 ? "<1%" : `${p.toFixed(0)}%`;
}

class Sum {
  cost = 0;
  calls = 0;
  input = 0;
  cacheRead = 0;
  cacheWrite = 0;
  output = 0;
  /// Calls of a model with no price: not in `cost`.
  unpriced = 0;

  add(row: J): void {
    const n = (k: string) => (typeof get(row, k) === "number" ? row[k] : 0);
    const calls = n("calls");
    if (typeof get(row, "cost") === "number") this.cost += row.cost;
    else this.unpriced += calls;
    this.calls += calls;
    this.input += n("input");
    this.cacheRead += n("cacheRead");
    this.cacheWrite += n("cacheWrite");
    this.output += n("output");
  }

  costText(): string {
    if (this.unpriced > 0 && this.unpriced >= this.calls) return t("core-views.usage.unpriced");
    if (this.unpriced > 0) return `≥${money(this.cost)}`;
    return money(this.cost);
  }

  tokens(): number {
    return this.input + this.cacheRead + this.cacheWrite + this.output;
  }
}

type Item = { key: string; title: string; sub: string | null; extra: Record<string, J>; sum: Sum };

function itemsShown(items: Item[], total: Sum): J[] {
  items.sort((a, b) => b.sum.cost - a.sum.cost || b.sum.calls - a.sum.calls || (a.title < b.title ? -1 : a.title > b.title ? 1 : 0));
  const byCost = total.cost > 0;
  return items.map((i) => {
    const share = byCost ? i.sum.cost / total.cost : total.calls > 0 ? i.sum.calls / total.calls : 0;
    return {
      key: i.key,
      title: i.title,
      sub: i.sub,
      cost: i.sum.cost,
      costText: i.sum.costText(),
      share,
      shareText: percent(share, 1),
      calls: i.sum.calls,
      detail: t("core-views.usage.detail", { n: count(i.sum.calls), tokens: count(i.sum.tokens()) }),
      ...i.extra,
    };
  });
}

const okOf = (v: Value | undefined): J => (v !== undefined && "ok" in v ? v.ok : undefined);

/// Each station's prices for the models counted in the period, apart.
export function priceTables(sources: Source[], first: string, last: string): J[] {
  return sources.map((s) => {
    const value = okOf(s.value);
    const table = get(value, "prices");
    const note = !s.online
      ? t("core-views.usage.prices.offline")
      : table === undefined
        ? t("core-views.usage.prices.missing")
        : typeof get(table, "note") === "string"
          ? table.note
          : t("core-views.usage.prices.unit");
    const used = new Set<string>();
    for (const r of arr(get(value, "rows"))) {
      const day = get(r, "day");
      if (typeof day === "string" && day >= first && day <= last && (typeof get(r, "calls") === "number" ? r.calls : 0) > 0) {
        used.add(typeof get(r, "model") === "string" ? model.key(r.model) : t("core-views.usage.unknown_model"));
      }
    }
    const prices = arr(get(table, "rows"));
    const matched = [...used].sort().map((m) => {
      const rate = prices.find((p) => typeof get(p, "model") === "string" && (m === p.model || (m.startsWith(p.model) && m.slice(p.model.length).startsWith("["))));
      return [m, rate] as [string, J];
    });
    const columns = (
      [
        ["input", t("core-views.usage.prices.input")],
        ["cacheRead", t("core-views.usage.prices.cache_read")],
        ["cacheWrite", t("core-views.usage.prices.cache_write")],
        ["cacheWriteLong", t("core-views.usage.prices.cache_write_long")],
        ["output", t("core-views.usage.prices.output")],
      ] as [string, string][]
    ).filter(([key]) => !key.startsWith("cacheWrite") || matched.some(([, p]) => typeof get(p, key) === "number"));
    const rows = s.online
      ? matched.map(([m, r]) => ({
          model: r !== undefined ? m : t("core-views.usage.prices.model_unpriced", { model: m }),
          rates: columns.map(([key, label]) => ({ label, value: typeof get(r, key) === "number" ? `$${r[key]}` : "—" })),
        }))
      : [];
    return { station: s.name, note, rows };
  });
}

/// The view: `days` local days to `now`, the viewer `me` among the workspace's `members`.
export function usageView(sources: Source[], daysAsked: number, now: number, offset: number, me: J, members: J[]): J {
  const days = Math.min(Math.max(daysAsked, 1), 30);
  const dayList: string[] = [];
  for (let i = days - 1; i >= 0; i--) dayList.push(localDay(now - i * DAY_MS, offset));
  const first = dayList[0];
  const several = sources.filter((s) => s.online).length > 1;
  let loading = false;
  let reading = false;
  const notes: string[] = [];
  let since: number | null = null;
  const total = new Sum();
  const byDay = new Map<string, [Sum, Map<string, number>]>(dayList.map((d) => [d, [new Sum(), new Map()]]));
  const people = new Map<string, Item>();
  const chats = new Map<string, Item>();
  const profiles = new Map<string, Item>();
  const models = new Map<string, Item>();
  const entry = (map: Map<string, Item>, key: string, make: () => Item) => {
    let item = map.get(key);
    if (!item) {
      item = make();
      map.set(key, item);
    }
    return item;
  };
  for (const s of sources) {
    if (!s.online) {
      notes.push(t("core-views.usage.note.offline", { name: s.name }));
      continue;
    }
    if (s.value === undefined) {
      loading = true;
      continue;
    }
    if ("err" in s.value) {
      const e: CoreError = s.value.err;
      notes.push(e.status === 404 ? t("core-views.usage.note.outdated", { name: s.name }) : t("core-views.named_error", { name: s.name, error: e.message }));
      continue;
    }
    const value = s.value.ok as J;
    reading ||= get(value, "reading") === true;
    if (typeof get(value, "since") === "number") since = since === null ? value.since : Math.min(since, value.since);
    const place = several ? s.name : null;
    const threads = get(value, "threads") ?? null;
    const stationPeople = get(value, "people") ?? null;
    const stationProfiles = get(value, "profiles") ?? null;
    for (const row of arr(get(value, "rows"))) {
      const day = typeof get(row, "day") === "string" ? row.day : "";
      const at = byDay.get(day);
      if (!at) continue;
      const [daySum, dayPeople] = at;
      daySum.add(row);
      total.add(row);
      const text = (k: string): string | null => (typeof get(row, k) === "string" ? row[k] : null);
      const reference = text("person");
      const knownPerson = reference !== null && isObject(get(stationPeople, reference)) ? stationPeople[reference] : undefined;
      const person = knownPerson !== undefined ? structuredClone(knownPerson) : { id: reference ?? "", name: t("core-views.usage.unknown_person"), email: null };
      present.person(person, me, members);
      const personKey = (typeof person.email === "string" ? person.email : typeof person.id === "string" ? person.id : "").toLowerCase();
      const name = typeof person.shown?.display === "string" ? person.shown.display : "";
      const cost = typeof get(row, "cost") === "number" ? row.cost : 0;
      dayPeople.set(personKey, (dayPeople.get(personKey) ?? 0) + cost);
      entry(people, personKey, () => ({ key: personKey, title: name, sub: null, extra: { person: knownPerson !== undefined ? person : null }, sum: new Sum() })).sum.add(row);

      const session = text("session") ?? "";
      const thread = typeof get(row, "thread") === "number" && Number.isInteger(row.thread) && row.thread >= 0 ? (row.thread as number) : null;
      const chatKey = `${s.address}/${thread !== null ? thread : session}`;
      entry(chats, chatKey, () => {
        const known = thread !== null ? get(threads, String(thread)) : undefined;
        const title = typeof get(known, "title") === "string" ? known.title : t("core-views.usage.deleted_chat");
        const archived = get(known, "archived") === true;
        const surface = get(known, "surface");
        const slack = typeof surface === "string" && !(surface === "ember" || surface === "stillfail");
        const sub = [place, slack ? "Slack" : null, archived ? t("core-views.usage.archived") : null].filter((x) => x !== null);
        let page: J = null;
        if (known !== undefined && !slack) page = { station: s.address, thread };
        else if (known !== undefined && slack && get(known, "home") !== undefined && known.home !== null) page = { station: s.address, session: known.home };
        else if (session !== "" && known !== undefined) page = { station: s.address, session };
        return { key: chatKey, title, sub: sub.length > 0 ? sub.join(" · ") : null, extra: { chat: page }, sum: new Sum() };
      }).sum.add(row);

      const profile = text("profile") ?? "";
      const profileKey = `${s.address}/${profile}`;
      entry(profiles, profileKey, () => {
        const pname = get(get(stationProfiles, profile), "name");
        const title = typeof pname === "string" && pname !== "" ? pname : profile === "" ? t("core-views.usage.unknown_account") : t("core-views.usage.deleted_account", { profile });
        return { key: profileKey, title, sub: place, extra: {}, sum: new Sum() };
      }).sum.add(row);
      const m = text("model") ?? "";
      entry(models, model.key(m), () => {
        const priced = get(row, "cost") !== undefined && row.cost !== null;
        return { key: model.key(m), title: m === "" ? t("core-views.usage.unknown_which_model") : model.name(m), sub: priced ? null : t("core-views.usage.no_price"), extra: {}, sum: new Sum() };
      }).sum.add(row);
    }
  }

  const ranked = [...people].sort((a, b) => b[1].sum.cost - a[1].sum.cost || (a[1].title < b[1].title ? -1 : a[1].title > b[1].title ? 1 : 0));
  const top = ranked.slice(0, ranked.length > SERIES + 1 ? SERIES : SERIES + 1).map(([k, i]) => [k, i.title] as [string, string]);
  const rest = ranked.length > top.length;
  const series: J[] = top.map(([key, name]) => ({ key, name }));
  if (rest) series.push({ key: "", name: t("core-views.usage.others") });
  const today = localDay(now, offset);
  const daily = [...byDay].map(([day, [sum, split]]) => {
    const parts = top.map(([k]) => split.get(k) ?? 0);
    if (rest) {
      let other = 0;
      for (const [k, v] of split) if (!top.some(([x]) => x === k)) other += v;
      parts.push(other);
    }
    return {
      day,
      label: dayLabel(day),
      today: day === today,
      cost: sum.cost,
      costText: sum.costText(),
      calls: sum.calls,
      callsText: t("core-views.usage.calls", { n: count(sum.calls) }),
      partsText: parts.map(money),
      parts,
    };
  });
  const max = [...byDay.values()].reduce((m, [s]) => Math.max(m, s.cost), 0);
  const input = total.input + total.cacheRead + total.cacheWrite;
  const tiles = [
    { label: t("core-views.usage.tile.cost"), value: total.costText(), sub: t("core-views.usage.tile.cost_sub") },
    { label: t("core-views.usage.tile.calls"), value: t("core-views.usage.tile.calls_value", { n: count(total.calls) }), sub: t("core-views.usage.tile.calls_sub", { n: count(total.calls / days) }) },
    { label: t("core-views.usage.tile.input"), value: count(input), sub: t("core-views.usage.tile.input_sub", { percent: percent(total.cacheRead, input) }) },
    { label: t("core-views.usage.tile.output"), value: count(total.output), sub: t("core-views.usage.tile.output_sub", { n: count(total.calls > 0 ? total.output / total.calls : 0) }) },
  ];
  const lists = [
    { key: "people", title: t("core-views.usage.by.people"), items: itemsShown([...people.values()], total) },
    { key: "chats", title: t("core-views.usage.by.chats"), items: itemsShown([...chats.values()], total) },
    { key: "profiles", title: t("core-views.usage.by.profiles"), items: itemsShown([...profiles.values()], total) },
    { key: "models", title: t("core-views.usage.by.models"), items: itemsShown([...models.values()], total) },
  ];
  if (reading) notes.unshift(t("core-views.usage.note.reading"));
  if (since !== null && localDay(since, offset) > first) {
    const label = dayLabel(localDay(since, offset));
    const [month, day] = label.split("/");
    notes.push(t("core-views.usage.note.since", { month, day }));
  }
  if (total.unpriced > 0) notes.push(t("core-views.usage.note.unpriced", { n: count(total.unpriced) }));
  return { days, prices: priceTables(sources, first, today), loading, empty: total.calls === 0, tiles, series, daily, max, lists, notes, basis: t("core-views.usage.basis") };
}

export { tr };
