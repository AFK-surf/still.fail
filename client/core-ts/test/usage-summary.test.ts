// The usage page's summary (views/usage-summary.ts): Codex's year of activity, with still.fail's own figures.
import assert from "node:assert/strict";
import { test } from "node:test";
import { conform } from "../src/conform.ts";
import { holdLanguage } from "../src/i18n.ts";
import { level, usageSummary, WEEKS } from "../src/views/usage-summary.ts";
import { usageView, type Source } from "../src/views/usage.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;

/// 2026-10-02 (a Friday) 12:00 at +8.
const NOW = 1_790_913_600_000;
const day = (d: string, tokens: number, model = "claude-opus-5-5", runtime = "claude"): J => ({ day: d, runtime, model, tokens, calls: 1 });
const history = (days: J[], more: J = {}): J => ({ days, chats: 0, longestTurnMs: null, places: { ember: 1 }, archived: 0, remoteRuns: 0, cards: 0, picked: 0, ...more });
const station = (h: J | undefined): J => ({ since: 0, reading: false, rows: [], threads: {}, people: {}, profiles: {}, ...(h ? { history: h } : {}) });
const source = (name: string, h: J | undefined): Source => ({ address: `ws/${name}`, name, online: true, value: { ok: station(h) } });

test("levels are the quarters of the most of a day, as Codex grades them", () => {
  assert.deepEqual([0, 1, 25, 26, 50, 51, 75, 76, 100].map((v) => level(v, 100)), [0, 1, 1, 2, 2, 3, 3, 4, 4]);
  assert.equal(level(5, 0), 0);
});

test("the figures across stations: tokens, chats archived, tasks across devices, decisions tapped, devices at work", () => {
  const a = history([day("2026-09-29", 300), day("2026-10-02", 20, "gpt-6", "codex")], { archived: 7, remoteRuns: 3, cards: 10, picked: 6, places: { ember: 9, slack: 2 } });
  const b = history([day("2026-09-30", 80)], { archived: 2, remoteRuns: 1, cards: 10, picked: 3, places: { ember: 1, feishu: 4 } });
  // a station that told its history but did no work: not one of the devices at work
  const c = history([]);
  const s = usageSummary([source("studio", a), source("mba", b), source("idle", c)], NOW, 480, "星火")!;
  assert.deepEqual(s.figures.map((f: J) => f.value), ["400", "9", "4", "45%", "2"]);
  assert.equal(s.title, "星火");
  assert.equal(s.partial, null);
  assert.deepEqual(s.stations.items.map((f: J) => [f.name, f.value]), [["studio", "320 token · 80%"], ["mba", "80 token · 20%"]]);
  assert.deepEqual(s.places.items.map((f: J) => [f.name, f.value]), [["still.fail", "11 个对话"], ["飞书", "4 个对话"], ["Slack", "2 个对话"]]);
});

test("one place: where the chats came from not said; no decision cards: no share", () => {
  const s = usageSummary([source("studio", history([day("2026-10-02", 1)]))], NOW, 480, "")!;
  assert.equal(s.places, undefined);
  assert.equal(s.figures[3].value, "—");
});

test("the year: 52 weeks Sunday first, today in the last, a day after it -1; each week's bar of the tallest", () => {
  const s = usageSummary([source("studio", history([day("2026-10-02", 100), day("2026-09-27", 40), day("2025-01-01", 999)]))], NOW, 480, "")!;
  const cells = s.activity.cells;
  assert.equal(cells.length, WEEKS * 7);
  // the last column: Sunday 9/27 .. Saturday 10/3; Friday 10/2 is today, Saturday after it
  assert.deepEqual(cells.slice(-7), [2, 0, 0, 0, 0, 4, -1]);
  // a day more than a year back is not in the year (its most is today's)
  assert.equal(cells.filter((c: number) => c > 0).length, 2);
  assert.equal(s.activity.weekly[WEEKS - 1], 7);
  assert.equal(s.activity.cumulative[WEEKS - 1], 7);
  assert.ok(s.activity.months.length >= 11);
});

test("what each day and week says under the pointer: its date and tokens; a day after today nothing", () => {
  const s = usageSummary([source("studio", history([day("2026-10-02", 1200), day("2026-09-28", 300)]))], NOW, 480, "")!;
  const a = s.activity;
  assert.equal(a.tips.length, WEEKS * 7);
  assert.deepEqual(a.tips.slice(-7), ["9月27日 · 没有用 token", "9月28日 · 300 token", "9月29日 · 没有用 token", "9月30日 · 没有用 token", "10月1日 · 没有用 token", "10月2日 · 1,200 token", ""]);
  assert.equal(a.weekTips[WEEKS - 1], "9月27日起一周 · 1,500 token");
  // the running total as of today, the week's last day so far
  assert.equal(a.runningTips[WEEKS - 1], "截至10月2日累计 · 1,500 token");
  assert.equal(a.runningTips[WEEKS - 2], "截至9月26日累计 · 没有用 token");
});

test("a station from before tells no history: left out and said; none at all: no summary", () => {
  const s = usageSummary([source("studio", history([day("2026-10-02", 1)])), source("old", undefined)], NOW, 480, "")!;
  assert.ok(s.partial !== null);
  assert.equal(usageSummary([source("old", undefined)], NOW, 480, ""), null);
  const v = { ...usageView([source("studio", history([day("2026-10-02", 1)]))], 7, NOW, 480, { id: "a@x", email: "a@x" }, []), summary: s };
  assert.ok("ok" in conform("UsageView", v));
});
