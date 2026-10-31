// What the agents spent (views/usage.rs): every online station's usage put together for a scope's last 7 or 30
// days, as the usage page shows it: a few totals against the days before as many, each day's cost split by the people,
// chats, accounts or models picked (`split`), and who, which chats, which accounts and which models spent the most; all
// of it of one person, account or model where one is picked (`only`).
import type { CoreError } from "../error.ts";
import { current, t, tr, type Lang } from "../i18n.ts";
import { waitNote } from "../looks.ts";
import * as present from "../present.ts";
import * as model from "../shapes/model.ts";
import type { Value } from "../store.ts";
import { arr as arrU, get as getU, isObject } from "../util.ts";
import { scale } from "./scale.ts";

export { scale };

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

function itemsShown(listed: Item[], total: Sum): J[] {
  const items = [...listed].sort((a, b) => b.sum.cost - a.sum.cost || b.sum.calls - a.sum.calls || (a.title < b.title ? -1 : a.title > b.title ? 1 : 0));
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
      callsText: count(i.sum.calls),
      tokensText: count(i.sum.tokens()),
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

/// What a list's first few spent and the rest (其他), as its share of the whole: what it is made of at a glance; none
/// for a list of one (one person, one model: nothing to tell apart).
const PARTS = 3;
function partsOf(items: J[]): J[] {
  const first = items.slice(0, items.length > PARTS + 1 ? PARTS : PARTS + 1);
  const out = first.map((i) => ({ key: i.key, title: i.title, cost: i.cost, costText: i.costText, share: i.share, shareText: i.shareText }));
  if (items.length > first.length) {
    const rest = items.slice(first.length);
    const cost = rest.reduce((n, i) => n + i.cost, 0);
    const share = rest.reduce((n, i) => n + i.share, 0);
    out.push({ key: "", title: t("core-views.usage.others"), cost, costText: money(cost), share, shareText: percent(share, 1) });
  }
  return out;
}

/// The lists a day's bar can be split by, and what can be picked to see alone (a chat opens instead).
const SPLITS = ["people", "chats", "profiles", "models"];
const ONLY = ["people", "profiles", "models"];

/// What the page picked: the list the days' bars are split by (else the people's where there are several, the models'
/// where one), and the one person, account or model to see alone.
export type UsagePick = { split?: unknown; only?: unknown; day?: unknown };

/// `now` against `before`, the days before as many: ↑18% and up, 持平 and none; nothing where nothing was spent before.
function change(now: number, before: number): { change: string | null; trend: string } {
  if (!(before > 0)) return { change: null, trend: "" };
  const p = ((now - before) / before) * 100;
  if (Math.abs(p) < 0.5) return { change: t("core-views.usage.tile.same"), trend: "" };
  const n = Math.abs(p) >= 10 ? Math.round(Math.abs(p)).toFixed(0) : Math.abs(p).toFixed(1).replace(/\.0$/, "");
  return { change: `${p > 0 ? "↑" : "↓"}${n}%`, trend: p > 0 ? "up" : "down" };
}

/// The view: `days` local days to `now`, the viewer `me` among the workspace's `members`, as `pick` asks; `accounts` the
/// workspace's accounts as the profiles page lists them (views/profiles.ts workspaceProfiles), for each subscription's
/// allowance beside what it spent.
export function usageView(sources: Source[], daysAsked: number, now: number, offset: number, me: J, members: J[], pick: UsagePick = {}, accounts: J[] = []): J {
  const days = Math.min(Math.max(daysAsked, 1), 30);
  const dayList: string[] = [];
  for (let i = days - 1; i >= 0; i--) dayList.push(localDay(now - i * DAY_MS, offset));
  const first = dayList[0];
  // the days before as many, to say each total against
  const before = new Set<string>();
  for (let i = 2 * days - 1; i >= days; i--) before.add(localDay(now - i * DAY_MS, offset));
  const beforeFirst = localDay(now - (2 * days - 1) * DAY_MS, offset);
  const onlyList = get(pick.only, "list");
  const onlyKey = get(pick.only, "key");
  const only: { list: string; key: string } | null = typeof onlyList === "string" && ONLY.includes(onlyList) && typeof onlyKey === "string" ? { list: onlyList, key: onlyKey } : null;
  // the one day everything but the days' bars is of, where one is picked (one of the days)
  const dayOnly = typeof pick.day === "string" && dayList.includes(pick.day) ? pick.day : null;
  const several = sources.filter((s) => s.online).length > 1;
  let reading = false;
  const waiting: string[] = [];
  const failing: { station: string; name: string; message: string }[] = [];
  const notes: string[] = [];
  let since: number | null = null;
  const total = new Sum();
  const earlier = new Sum();
  // whether every station's rows reach back over the days before (an older one read only 30 days; one recording since)
  let compared = true;
  // each chat's cost by who it was for and by model (its words: the most of each)
  const chatWho = new Map<string, Map<string, number>>();
  const chatModel = new Map<string, Map<string, number>>();
  const most = (m: Map<string, number> | undefined): string | null => {
    let best: [string, number] | null = null;
    for (const [k, v] of m ?? []) if (best === null || v > best[1] || (v === best[1] && k < best[0])) best = [k, v];
    return best === null ? null : best[0];
  };
  const bump = (m: Map<string, Map<string, number>>, key: string, name: string, by: number) => {
    const at = m.get(key) ?? new Map<string, number>();
    m.set(key, at);
    at.set(name, (at.get(name) ?? 0) + by);
  };
  // each day's sum and its cost by each list's keys
  const byDay = new Map<string, [Sum, Record<string, Map<string, number>>]>(dayList.map((d) => [d, [new Sum(), { people: new Map(), chats: new Map(), profiles: new Map(), models: new Map() }]]));
  const people = new Map<string, Item>();
  const chats = new Map<string, Item>();
  const profiles = new Map<string, Item>();
  // Each account's tokens by model (its key: its name, its tokens), for the one it used most.
  const profileModels = new Map<string, Map<string, [string, number]>>();
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
      waiting.push(s.name);
      continue;
    }
    if ("err" in s.value) {
      const e: CoreError = s.value.err;
      if (e.status !== 404) failing.push({ station: s.address, name: s.name, message: e.message });
      notes.push(e.status === 404 ? t("core-views.usage.note.outdated", { name: s.name }) : t("core-views.named_error", { name: s.name, error: e.message }));
      continue;
    }
    const value = s.value.ok as J;
    reading ||= get(value, "reading") === true;
    const from = get(value, "from");
    if (typeof from !== "number" || localDay(from, offset) > beforeFirst) compared = false;
    if (typeof get(value, "since") === "number") since = since === null ? value.since : Math.min(since, value.since);
    const place = several ? s.name : null;
    const threads = get(value, "threads") ?? null;
    const stationPeople = get(value, "people") ?? null;
    const stationProfiles = get(value, "profiles") ?? null;
    for (const row of arr(get(value, "rows"))) {
      const day = typeof get(row, "day") === "string" ? row.day : "";
      const at = byDay.get(day);
      if (!at && !before.has(day)) continue;
      const text = (k: string): string | null => (typeof get(row, k) === "string" ? row[k] : null);
      const reference = text("person");
      const knownPerson = reference !== null && isObject(get(stationPeople, reference)) ? stationPeople[reference] : undefined;
      const person = present.person(knownPerson !== undefined ? knownPerson : { id: reference ?? "", name: t("core-views.usage.unknown_person"), email: null }, me, members);
      const personKey = (typeof person.email === "string" ? person.email : typeof person.id === "string" ? person.id : "").toLowerCase();
      const name = typeof person.shown?.display === "string" ? person.shown.display : "";
      const session = text("session") ?? "";
      const thread = typeof get(row, "thread") === "number" && Number.isInteger(row.thread) && row.thread >= 0 ? (row.thread as number) : null;
      const chatKey = `${s.address}/${thread !== null ? thread : session}`;
      const profile = text("profile") ?? "";
      const profileKey = `${s.address}/${profile}`;
      const m = text("model") ?? "";
      const keys: Record<string, string> = { people: personKey, chats: chatKey, profiles: profileKey, models: model.key(m) };
      if (only !== null && keys[only.list] !== only.key) continue;
      if (!at) {
        earlier.add(row);
        continue;
      }
      const [daySum, dayParts] = at;
      daySum.add(row);
      const cost = typeof get(row, "cost") === "number" ? row.cost : 0;
      for (const list of SPLITS) dayParts[list].set(keys[list], (dayParts[list].get(keys[list]) ?? 0) + cost);
      // (a day picked: the days' bars all of them, the rest of it alone)
      if (dayOnly !== null && day !== dayOnly) continue;
      total.add(row);
      // (by cost, else by calls where none was priced)
      const weight = cost > 0 ? cost : (typeof get(row, "calls") === "number" ? row.calls : 0) * 1e-9;
      bump(chatWho, chatKey, name, weight);
      if (m !== "") bump(chatModel, chatKey, model.name(m), weight);
      entry(people, personKey, () => ({ key: personKey, title: name, sub: null, extra: { person: knownPerson !== undefined ? person : null }, sum: new Sum() })).sum.add(row);

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

      entry(profiles, profileKey, () => {
        const pname = get(get(stationProfiles, profile), "name");
        const title = typeof pname === "string" && pname !== "" ? pname : profile === "" ? t("core-views.usage.unknown_account") : t("core-views.usage.deleted_account", { profile });
        return { key: profileKey, title, sub: place, extra: {}, sum: new Sum() };
      }).sum.add(row);
      if (m !== "") {
        const used = profileModels.get(profileKey) ?? new Map<string, [string, number]>();
        profileModels.set(profileKey, used);
        const one = new Sum();
        one.add(row);
        const was = used.get(model.key(m));
        used.set(model.key(m), [model.name(m), (was?.[1] ?? 0) + one.tokens()]);
      }
      entry(models, model.key(m), () => {
        const priced = get(row, "cost") !== undefined && row.cost !== null;
        return { key: model.key(m), title: m === "" ? t("core-views.usage.unknown_which_model") : model.name(m), sub: priced ? null : t("core-views.usage.no_price"), extra: {}, sum: new Sum() };
      }).sum.add(row);
    }
  }

  // (recorded only since within the days before: no telling what they spent; a day picked: none to say it against)
  if (since !== null && localDay(since, offset) > beforeFirst) compared = false;
  if (dayOnly !== null) compared = false;
  // each chat said with who it was for and its model, the most of each, before where it is (who only where several
  // spent, the model only where several were used: one of them says nothing)
  for (const [key, item] of chats) {
    const said = [people.size > 1 ? most(chatWho.get(key)) : null, models.size > 1 ? most(chatModel.get(key)) : null, item.sub].filter((x): x is string => x !== null && x !== "");
    item.sub = said.length > 0 ? said.join(" · ") : null;
  }
  const lists_: Record<string, Map<string, Item>> = { people, chats, profiles, models };
  const splitAsked = typeof pick.split === "string" && SPLITS.includes(pick.split) ? pick.split : null;
  const split = splitAsked ?? (people.size > 1 ? "people" : "models");
  const ranked = [...lists_[split]].sort((a, b) => b[1].sum.cost - a[1].sum.cost || (a[1].title < b[1].title ? -1 : a[1].title > b[1].title ? 1 : 0));
  const top = ranked.slice(0, ranked.length > SERIES + 1 ? SERIES : SERIES + 1).map(([k, i]) => [k, i.title] as [string, string]);
  const rest = ranked.length > top.length;
  const series: J[] = top.map(([key, name]) => ({ key, name }));
  if (rest) series.push({ key: "", name: t("core-views.usage.others") });
  const today = localDay(now, offset);
  // Too many days for each to say its date under its bar: today's and one a week back from the last.
  const many = byDay.size > 10;
  const daily = [...byDay].map(([day, [sum, byList]], i) => {
    const split_ = byList[split];
    const parts = top.map(([k]) => split_.get(k) ?? 0);
    if (rest) {
      let other = 0;
      for (const [k, v] of split_) if (!top.some(([x]) => x === k)) other += v;
      parts.push(other);
    }
    const name = day === today ? t("core-views.usage.today") : dayLabel(day);
    return {
      day,
      label: dayLabel(day),
      today: day === today,
      name,
      tick: !many || day === today || (byDay.size - 1 - i) % 7 === 0 ? name : "",
      shares: parts.map((p) => (sum.cost > 0 ? Math.min(1, Math.max(p > 0 ? 0.01 : 0, p / sum.cost)) : 0)),
      cost: sum.cost,
      costText: sum.costText(),
      calls: sum.calls,
      callsText: t("core-views.usage.calls", { n: count(sum.calls) }),
      partsText: parts.map(money),
      sharesText: parts.map((p) => percent(p, sum.cost)),
      parts,
    };
  });
  const max = [...byDay.values()].reduce((m, [s]) => Math.max(m, s.cost), 0);
  const input = total.input + total.cacheRead + total.cacheWrite;
  const vs = (now_: number, before_: number) => (compared ? change(now_, before_) : { change: null, trend: "" });
  const tiles = [
    { label: t("core-views.usage.tile.cost"), value: total.costText(), sub: t("core-views.usage.tile.cost_sub"), ...(total.unpriced > 0 || earlier.unpriced > 0 ? { change: null, trend: "" } : vs(total.cost, earlier.cost)) },
    { label: t("core-views.usage.tile.calls"), value: t("core-views.usage.tile.calls_value", { n: count(total.calls) }), sub: t("core-views.usage.tile.calls_sub", { n: count(total.calls / days) }), ...vs(total.calls, earlier.calls) },
    { label: t("core-views.usage.tile.input"), value: count(input), sub: t("core-views.usage.tile.input_sub", { percent: percent(total.cacheRead, input) }), ...vs(input, earlier.input + earlier.cacheRead + earlier.cacheWrite) },
    { label: t("core-views.usage.tile.output"), value: count(total.output), sub: t("core-views.usage.tile.output_sub", { n: count(total.calls > 0 ? total.output / total.calls : 0) }), ...vs(total.output, earlier.output) },
  ];
  for (const [key, used] of profileModels) {
    const most = [...used.values()].sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))[0];
    const item = profiles.get(key);
    if (item !== undefined && most !== undefined && most[1] > 0) item.extra.topModel = t("core-views.usage.top_model", { model: most[0] });
  }
  const lists = [
    { key: "people", title: t("core-views.usage.by.people"), items: itemsShown([...people.values()], total) },
    { key: "chats", title: t("core-views.usage.by.chats"), items: itemsShown([...chats.values()], total) },
    { key: "profiles", title: t("core-views.usage.by.profiles"), items: itemsShown([...profiles.values()], total) },
    { key: "models", title: t("core-views.usage.by.models"), items: itemsShown([...models.values()], total) },
  ].map((l) => ({ ...l, parts: l.items.length > 1 ? partsOf(l.items) : [] }));
  // each subscription with an allowance: what is left of it, and what it spent (its copies' on every station)
  const spentBy = new Map([...profiles].map(([k, i]) => [k, i.sum]));
  const allowances = accounts
    .filter((a) => get(get(get(a, "profile"), "quota"), "state") === "ok" && arr(get(get(get(a, "profile"), "quota"), "windows")).length > 0)
    .map((a) => {
      const sum = new Sum();
      for (const m of arr(get(a, "members"))) {
        const spent = spentBy.get(`${get(m, "station")}/${get(m, "profileId")}`);
        if (spent !== undefined) for (const k of ["cost", "calls", "input", "cacheRead", "cacheWrite", "output", "unpriced"] as const) (sum as J)[k] += spent[k];
      }
      return { key: String(get(a, "key") ?? ""), title: String(get(a, "title") ?? ""), quota: a.profile.quota, cost: sum.cost, costText: sum.costText() };
    })
    .sort((a, b) => b.cost - a.cost || (a.title < b.title ? -1 : a.title > b.title ? 1 : 0));
  if (reading) notes.unshift(t("core-views.usage.note.reading"));
  if (since !== null && localDay(since, offset) > first) {
    const label = dayLabel(localDay(since, offset));
    const [month, day] = label.split("/");
    notes.push(t("core-views.usage.note.since", { month, day }));
  }
  if (total.unpriced > 0) notes.push(t("core-views.usage.note.unpriced", { n: count(total.unpriced) }));
  const { top: scaleTop, ticks } = scale(max);
  // the one seen alone, by its name in its list (none spent in the days: its key)
  const onlyShown = only !== null ? { list: only.list, key: only.key, title: lists_[only.list].get(only.key)?.title ?? only.key } : null;
  const dayShown = dayOnly !== null ? (dayOnly === today ? t("core-views.usage.today") : dayLabel(dayOnly)) : null;
  return { days, day: dayOnly, accounts: allowances, split, only: onlyShown, prices: priceTables(sources, first, today), wait: waitNote(waiting, failing, total.calls === 0), empty: total.calls === 0, tiles, versus: t("core-views.usage.tile.versus", { n: days }), period: dayShown ?? t("core-views.usage.period", { n: days }), series, daily, many, max, top: scaleTop, ticks, lists, notes, basis: t("core-views.usage.basis") };
}

export { tr };
