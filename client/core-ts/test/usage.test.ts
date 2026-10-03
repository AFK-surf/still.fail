// The Rust core's views/usage.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { holdLanguage, tr } from "../src/i18n.ts";
import { count, countIn, localDay, money, priceTables, usageView, type Source } from "../src/views/usage.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

const row = (day: string, person: string, thread: number, profile: string, model: string, calls: number, cost: number | null): J => ({
  day, session: "ember:c-1", thread, person, profile, runtime: "claude", model, calls, input: 10 * calls, cacheRead: 90 * calls, cacheWrite: 0, output: calls, cost,
});
const station = (rows: J[]): J => ({
  since: 0, reading: false, rows,
  threads: { "7": { title: "修登录", surface: "ember", home: "ember:c-1", archived: false }, "8": { title: "#ops", surface: "slack:T1", home: "ember:c-2", archived: true } },
  people: { "a@x": { id: "a@x", name: "a@x", email: "a@x", via: "cloud" }, "slack:ds:U1": { id: "slack:ds:U1", name: "阿一", email: "a@x", via: "slack" }, "b@x": { id: "b@x", name: "b@x", email: "b@x", via: "cloud" } },
  profiles: { cc: { name: "公司账号", runtime: "claude" } },
});
const NOW = 1_790_913_600_000;
const ok = (v: J) => ({ ok: v });

test("days_split_by_who_and_lists_ranked_by_cost", () => {
  assert.equal(localDay(NOW, 480), "2026-10-02");
  const rows = [
    row("2026-10-02", "a@x", 7, "cc", "claude-opus-5-5", 10, 3.0),
    row("2026-10-02", "slack:ds:U1", 8, "cc", "claude-opus-5-5", 5, 1.0),
    row("2026-10-01", "b@x", 7, "gone", "gpt-6", 4, null),
    row("2026-09-20", "b@x", 7, "cc", "claude-opus-5-5", 100, 100.0),
  ];
  const sources: Source[] = [{ address: "ws/st", name: "studio", online: true, value: ok(station(rows)) }];
  const members = [{ email: "a@x", name: "阿一", picture: "https://p/a" }];
  const v = usageView(sources, 7, NOW, 480, { id: "b@x", email: "b@x" }, members);
  assert.equal(v.tiles[0].value, "≥$4.00");
  assert.equal(v.tiles[1].value, "19 次");
  const daily = v.daily;
  assert.deepEqual([daily.length, daily[6].label, daily[6].today], [7, "10/2", true]);
  assert.deepEqual(v.series, [{ key: "a@x", name: "阿一" }, { key: "b@x", name: "你" }]);
  assert.deepEqual(daily[6].parts, [4.0, 0.0]);
  const list = (k: number) => v.lists[k].items;
  const people = list(0);
  assert.deepEqual([people[0].title, people[0].shareText, people[0].person.shown.picture], ["阿一", "100%", "https://p/a"]);
  const chats = list(1);
  assert.deepEqual([chats[0].title, chats[0].chat], ["修登录", { station: "ws/st", thread: 7 }]);
  assert.deepEqual([chats[1].sub, chats[1].chat], ["Slack · 已归档", { station: "ws/st", session: "ember:c-2" }]);
  const profiles = list(2);
  assert.deepEqual([profiles[0].title, profiles[1].title], ["公司账号", "gone（已删除）"]);
  const models = list(3);
  assert.deepEqual([models[0].title, models[1].sub], ["Opus 5.5", "没有价目，不计费用"]);
  assert.deepEqual(v.notes, ["4 次调用的模型没有价目，没算进费用"]);
});

test("price_tables_keep_station_rates_separate_and_handle_older_stations", () => {
  const source = (name: string, rate: number): Source => ({
    address: name, name, online: true,
    value: ok({ rows: [{ day: "2026-10-02", model: "gpt-6-astra", calls: 1 }], prices: { note: "standard", rows: [{ model: "gpt-6-astra", input: rate, cacheRead: 0.01, output: 50.0 }] } }),
  });
  const tables = priceTables([source("alpha", 10), source("beta", 12), { address: "old", name: "old", online: true, value: ok({}) }], "2026-09-26", "2026-10-02");
  assert.equal(tables[0].rows[0].rates[0].value, "$10");
  assert.equal(tables[1].rows[0].rates[0].value, "$12");
  assert.equal(tables[0].rows[0].rates[1].value, "$0.01");
  assert.deepEqual(tables[2].rows, []);
  assert.ok(tables[2].note.includes("更新 station"));
});

test("price_table_only_lists_counted_models_in_the_selected_period", () => {
  const sources: Source[] = [{
    address: "st", name: "st", online: true,
    value: ok({
      rows: [
        { day: "2026-10-02", model: "openai/gpt-6-astra", calls: 2 },
        { day: "2026-10-01", model: "gpt-6-astra", calls: 3 },
        { day: "2026-09-10", model: "claude-opus-5-5", calls: 1 },
        { day: "2026-10-02", model: "gpt-6-sol", calls: 0 },
        { day: "2026-10-02", model: "new-model", calls: 1 },
      ],
      prices: { rows: [{ model: "gpt-6-astra", input: 10.0, cacheRead: 1.0, output: 50.0 }, { model: "claude-opus-5-5", input: 4.0, cacheWrite: 5.0 }, { model: "gpt-6-sol", input: 2.0 }] },
    }),
  }];
  const short = priceTables(sources, "2026-09-26", "2026-10-02");
  assert.equal(short[0].rows.length, 2);
  assert.equal(short[0].rows[0].model, "gpt-6-astra");
  assert.equal(short[0].rows[0].rates.length, 3);
  assert.equal(short[0].rows[1].model, "new-model（未计价）");
  const long = priceTables(sources, "2026-09-03", "2026-10-02");
  assert.equal(long[0].rows.length, 3);
  assert.equal(long[0].rows[0].rates.length, 4);
});

test("unknown_prices_are_not_shown_as_zero_and_tokens_stay_counted", () => {
  const sources: Source[] = [{ address: "ws/st", name: "studio", online: true, value: ok(station([row("2026-10-02", "a@x", 7, "cc", "unknown-model", 2, null)])) }];
  const v = usageView(sources, 7, NOW, 480, {}, []);
  assert.equal(v.tiles[0].value, "未计价");
  assert.equal(v.tiles[1].value, "2 次");
  assert.equal(v.daily[6].costText, "未计价");
  assert.equal(v.daily[0].costText, "$0");
  for (const list of v.lists) {
    assert.equal(list.items[0].costText, "未计价");
    assert.equal(list.items[0].detail, "2 次调用 · 202 token");
  }
  assert.ok("ok" in conform("UsageView", v));
});

test("unknown_people_keep_their_usage_and_the_view_decodes", () => {
  for (const reference of [null, "missing@x"]) {
    const unknown = row("2026-10-02", "", 7, "cc", "gpt-6", 2, 3.0);
    unknown.person = reference;
    const sources: Source[] = [{ address: "ws/st", name: "studio", online: true, value: ok(station([unknown, row("2026-10-02", "a@x", 7, "cc", "gpt-6", 1, 1.0)])) }];
    const v = usageView(sources, 7, NOW, 480, {}, []);
    const decoded = conform("UsageView", v) as J;
    assert.ok("ok" in decoded, JSON.stringify(decoded));
    const people = decoded.ok.lists[0].items;
    assert.equal(decoded.ok.tiles[0].value, "$4.00");
    assert.equal(decoded.ok.tiles[1].value, "3 次");
    assert.equal(people[0].title, "说不清是谁");
    assert.equal(people[0].person ?? null, null);
    assert.equal(people[0].cost, 3.0);
    assert.equal(people[1].person.via, "cloud");
  }
});

test("stations_that_cannot_say_are_noted_and_one_not_read_yet_is_loading", () => {
  const sources: Source[] = [
    { address: "ws/a", name: "alpha", online: true, value: undefined },
    { address: "ws/b", name: "beta", online: true, value: { err: new CoreError("http_404", "no", 404) } },
    { address: "ws/c", name: "gamma", online: false, value: undefined },
  ];
  const v = usageView(sources, 30, NOW, 0, {}, []);
  assert.deepEqual([v.loading, v.empty, v.daily.length], [true, true, 30]);
  assert.deepEqual(v.notes, ["beta 的 station 还没更新到记用量的版本", "gamma 离线，它的用量没算进来"]);
});

test("numbers_read_as_people_say_them", () => {
  assert.deepEqual([money(1911.16), money(191.4), money(12.346), money(0.004), money(0)], ["$1,911", "$191", "$12.35", "<$0.01", "$0"]);
  assert.deepEqual([count(9850), count(29_443), count(17_146_455), count(4_914_110_860)], ["9,850", "2.9 万", "1715 万", "49.1 亿"]);
  const en = (n: number) => countIn("en", n);
  assert.deepEqual([en(9850), en(29_443), en(17_146_455), en(4_914_110_860)], ["9,850", "29.4K", "17.1M", "4.9B"]);
  assert.deepEqual([tr("en", "core-views.usage.calls", { n: en(1) }), tr("en", "core-views.usage.calls", { n: en(29_443) })], ["1 call", "29.4K calls"]);
});
