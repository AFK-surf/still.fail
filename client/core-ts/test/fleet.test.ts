import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { fleetView, spentOf } from "../src/views/fleet.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const agent = (running: boolean): J => ({ key: "a", runtime: "claude", model: "claude-opus-5-5", process: running ? "running" : "cold", pending: 0 });
const row = (id: string, ...agents: J[]): J => ({ id, session: `s-${id}`, agents });
// a chat at rest, its last letter written `at`
const quiet = (id: string, at: number): J => ({ ...row(id, agent(false)), lastActiveAt: at });
// an account (the profiles view's item): its kind, and the profiles it is on each station
const account = (key: string, group: string, ...on: [string, string][]): J => ({ key, group, members: on.map(([station, profileId]) => ({ station, profileId })) });
// a station's calls on a day, of a profile
const call = (day: string, profile: string, input: number, output: number, cost: number | null, more: J = {}): J => ({ day, profile, calls: 1, input, cacheRead: 0, cacheWrite: 0, output, cost, ...more });
const at = (station: string, calls: J[]): J => ({ station, online: true, rows: [], archived: [], jobs: [], runs: [], calls });

test("the card shared says, by kind of account, how many accounts the chats used over the last 7 days and, model by model, their tokens and what they would cost; an account on two stations once", () => {
  const profiles = [
    account("claude-a", "claude", ["w/a", "p1"], ["w/b", "p1"]),
    account("claude-b", "claude", ["w/a", "p2"]),
    account("chatgpt-c", "chatgpt", ["w/a", "p3"]),
    account("key-k", "key", ["w/b", "pk"]),
    // not used in the days: not said
    account("claude-z", "claude", ["w/a", "p9"]),
  ];
  const opus = { model: "claude-opus-5-5" };
  const spent = spentOf(profiles, [
    at("w/a", [
      call("2026-10-26", "p1", 1000, 100, 2, { cacheRead: 500_000, ...opus }),
      call("2026-10-25", "p2", 1_000_000, 0, 5, { model: "claude-sonnet-5-5" }),
      call("2026-10-24", "p3", 300_000, 0, 1.5, { model: "gpt-5.5" }),
      // a model without a price: its tokens said, its cost at least what the rest's is
      call("2026-10-24", "p3", 200_000, 0, null, { model: "gpt-5.5" }),
      // before the days, and of a profile no longer listed: none of them
      call("2026-10-18", "p1", 9_000_000, 0, 50, opus),
      call("2026-10-26", "gone", 9_000_000, 0, 50, opus),
    ]),
    // the same model on another station, one line with the first's; a call of no model said
    at("w/b", [call("2026-10-20", "p1", 400_000, 98_900, 3, { model: "anthropic/claude-opus-5-5" }), call("2026-10-26", "pk", 50_000, 0, 0.25)]),
  ], new Set(["2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25", "2026-10-26"]));
  // said round its first model's tokens: 用 2 个 Claude 订阅账号消耗了 | 100 万 | Opus 5.5 token，折合 $5.00
  assert.deepEqual(spent.map((x: J) => [x.kind, x.accounts, x.tokens, x.lead, x.accountsText]), [
    ["claude", 2, 2_000_000, "用 2 个 Claude 订阅账号消耗了", "2 个账号"],
    ["chatgpt", 1, 500_000, "用 1 个 ChatGPT 订阅账号消耗了", "1 个账号"],
    ["key", 1, 50_000, "用 1 个 API Key 消耗了", "1 个账号"],
  ]);
  assert.deepEqual(spent.map((x: J) => x.models.map((m: J) => [m.name, m.tokens, m.lineText, m.of])), [
    [["Opus 5.5", 1_000_000, "100 万 · $5.00", "Opus 5.5 token，折合 $5.00"], ["Sonnet 5.5", 1_000_000, "100 万 · $5.00", "Sonnet 5.5 token，折合 $5.00"]],
    [["GPT-5.5", 500_000, "50 万 · ≥$1.50", "GPT-5.5 token，折合 ≥$1.50"]],
    [["未知模型", 50_000, "5 万 · $0.25", "未知模型 token，折合 $0.25"]],
  ]);
  assert.deepEqual(spent.map((x: J) => Math.round(x.share * 1000) / 1000), [0.784, 0.196, 0.02]);
});

test("a kind's models, the most tokens first: four said one by one, past four the first three and the rest together; one none of whose calls was priced, its tokens alone", () => {
  const profiles = [account("c", "claude", ["s", "c"])];
  const by = (model: string, input: number, cost: number | null = 1) => call("d", "c", input, 0, cost, { model });
  const four = [by("claude-sonnet-5-5", 300), by("claude-opus-5-5", 500), by("claude-haiku-4-5", 100), by("claude-fable-5-1", 50, null)];
  assert.deepEqual(spentOf(profiles, [at("s", four)], new Set(["d"]))[0].models.map((m: J) => [m.name, m.lineText]), [
    ["Opus 5.5", "500 · $1.00"], ["Sonnet 5.5", "300 · $1.00"], ["Haiku 4.5", "100 · $1.00"], ["Fable 5.1", "50"],
  ]);
  const five = [...four, by("claude-opus-4-7", 20)];
  assert.deepEqual(spentOf(profiles, [at("s", five)], new Set(["d"]))[0].models.map((m: J) => [m.name, m.lineText]), [
    ["Opus 5.5", "500 · $1.00"], ["Sonnet 5.5", "300 · $1.00"], ["Haiku 4.5", "100 · $1.00"], ["其他 2 个模型", "70 · ≥$1.00"],
  ]);
});

test("the card's kinds rank by tokens, with a stable kind order for ties", () => {
  const profiles = [account("g", "grok", ["s", "g"]), account("c", "claude", ["s", "c"]), account("o", "chatgpt", ["s", "o"]), account("k", "kimi", ["s", "k"])];
  const calls = [call("d", "g", 80, 0, 1), call("d", "c", 60, 0, 1), call("d", "o", 90, 0, 1), call("d", "k", 80, 0, 1)];
  for (const input of [calls, [...calls].reverse()]) {
    assert.deepEqual(spentOf(profiles, [at("s", input)], new Set(["d"])).map((q: J) => [q.kind, q.tokens]), [["chatgpt", 90], ["grok", 80], ["kimi", 80], ["claude", 60]]);
  }
});

test("the card shared says how many chats are at work now, and on how many stations today's chats are; today's and the last 7 days' chats archived and what was spent; the tasks chats ran on other stations over them", () => {
  const tile = (label: string, value: string) => ({ label, value, sub: "" });
  const usage = {
    empty: false,
    tiles: [tile("折合费用", "$12"), tile("模型调用", "300 次"), tile("输入 token", "1.2M"), tile("输出 token", "40k")],
    daily: [
      { day: "2026-10-25", label: "10/25", calls: 100, callsText: "100 次", costText: "$4", today: false },
      { day: "2026-10-26", label: "10/26", calls: 200, callsText: "200 次", costText: "$8", today: true },
    ],
  };
  // archived on the 25th (two, on two stations) and the 26th (four: one on g), and long before the week
  const on = (d: number, h: number) => Date.UTC(2026, 9, d, h);
  // tasks run on d for a's chats: 3's (idle on a: at work so), 1's (at work already); one waiting in d's queue, one
  // over, a watch, and one for a chat of a station down: none of them. Over the week, a's 1 ran three on h, its 3 one
  // (and one long before); one ran on c, down
  const task = (session: string, more: J = {}): J => ({ id: session, session: `remote:w:${session}`, state: "running", ...more });
  const v = fleetView(
    [
      { station: "w/a", online: true, rows: [row("1", agent(true)), row("2", agent(true), agent(false)), row("3", agent(false))], archived: [on(25, 9), on(26, 1), on(1, 3)], jobs: [], runs: [], calls: [] },
      { station: "w/b", online: true, rows: [row("4", agent(true))], archived: [on(25, 20), on(26, 5), on(26, 6)], jobs: [], runs: [], calls: [] },
      // down: none of what it last said counted
      { station: "w/c", online: false, rows: [row("5", agent(true))], archived: [on(26, 3)], jobs: [], runs: [{ at: on(26, 1), session: "remote:w:a:s-1" }], calls: [] },
      // today's chats, at rest: one written in today (e), one archived today (g); f's quiet since yesterday
      { station: "w/e", online: true, rows: [quiet("6", on(26, 3))], archived: [], jobs: [], runs: [], calls: [] },
      { station: "w/f", online: true, rows: [quiet("7", on(25, 22))], archived: [], jobs: [], runs: [], calls: [] },
      { station: "w/g", online: true, rows: [quiet("8", on(25, 23))], archived: [on(26, 2)], jobs: [], runs: [], calls: [] },
      {
        station: "w/d",
        online: true,
        rows: [],
        archived: [],
        jobs: [task("a:s-3"), task("a:s-1"), task("a:s-9", { queued: true }), task("a:s-3", { state: "exited" }), task("a:s-3", { watch: true }), task("c:s-5")],
        runs: [],
        calls: [],
      },
      // the tasks a's chats ran on h, none running now
      {
        station: "w/h",
        online: true,
        rows: [],
        archived: [],
        jobs: [],
        runs: [[1, "s-1"], [25, "s-1"], [25, "s-1"], [26, "s-1"], [26, "s-3"]].map(([d, k], i) => ({ at: on(d as number, i), session: `remote:w:a:${k}` })),
        calls: [call("2026-10-26", "p1", 100, 0, 1), call("2026-10-18", "p1", 100, 0, 1)],
      },
    ],
    [account("claude-a", "claude", ["w/h", "p1"])],
    usage,
    Date.UTC(2026, 9, 26, 4, 12),
  );
  // used today: a and b (chats at work), e and g (at rest), d (running their tasks) and h (it ran some today); not f
  assert.deepEqual([v.chats, v.chatsText, v.where, v.at], [4, "4 个对话正在运行", "今天用了 6 台设备", "10月26日 04:12"]);
  assert.deepEqual([v.tasksText, v.tasksPer], ["近 7 天 agent 跨设备执行了 4 个任务", "平均每个对话 2 个"]);
  // the calls of the last 7 days
  assert.deepEqual(v.spent.map((x: J) => [x.kind, x.tokens]), [["claude", 100]]);
  assert.deepEqual(v.today, { title: "今天", stats: [{ label: "归档的对话", value: "4 个" }, { label: "折合费用", value: "$8" }] });
  assert.deepEqual(v.week.stats, [{ label: "归档的对话", value: "6 个" }, { label: "输入 token", value: "1.2M" }, { label: "折合费用", value: "$12" }]);
  assert.deepEqual(v.week.days, [{ label: "10/25", share: 0.5, value: "2 个", today: false }, { label: "10/26", share: 1, value: "4 个", today: true }]);
  // nothing of the days while they are read, or with nothing spent nor archived
  assert.deepEqual([fleetView([], [], null).today, fleetView([], [], null).week], [undefined, undefined]);
  const none = fleetView([], [], { ...usage, empty: true });
  assert.deepEqual([none.today, none.week, none.spent, none.tasksText], [undefined, undefined, [], undefined]);
});
