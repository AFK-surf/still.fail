import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { fleetView, quotaOf } from "../src/views/fleet.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const agent = (running: boolean): J => ({ key: "a", runtime: "claude", model: "claude-opus-5-5", process: running ? "running" : "cold", pending: 0 });
const row = (...agents: J[]): J => ({ id: "1", agents });
const account = (group: string, week: number | null, state = "ok"): J => ({
  group,
  profile: { quota: { state, windows: [{ label: "5 小时", usedPercent: 10 }, ...(week === null ? [] : [{ label: "每周", usedPercent: week }])] } },
});

test("the card shared says how much of a week's quota each kind of subscription used, its accounts' added up (past 100% with two)", () => {
  const q = quotaOf([
    account("claude", 80),
    account("claude", 90),
    account("chatgpt", 45),
    // a key has no quota; a quota not read, or with no week, says nothing
    account("key", 99),
    account("claude", 10, "unavailable"),
    account("grok", null),
  ]);
  assert.deepEqual(q.map((x: J) => [x.kind, x.accounts, x.used, x.usedText, x.text]), [
    ["claude", 2, 170, "170%", "2 个 Claude 订阅账号的周额度"],
    ["chatgpt", 1, 45, "45%", "1 个 ChatGPT 订阅账号的周额度"],
  ]);
});

test("the card shared says how many chats are at work now and on how many stations; today's and the last 7 days' chats archived and what was spent", () => {
  const tile = (label: string, value: string) => ({ label, value, sub: "" });
  const usage = {
    empty: false,
    tiles: [tile("折合费用", "$12"), tile("模型调用", "300 次"), tile("输入 token", "1.2M"), tile("输出 token", "40k")],
    daily: [
      { day: "2026-10-25", label: "10/25", calls: 100, callsText: "100 次", costText: "$4", today: false },
      { day: "2026-10-26", label: "10/26", calls: 200, callsText: "200 次", costText: "$8", today: true },
    ],
  };
  // archived on the 25th (two, on two stations) and the 26th (four), and long before the week
  const on = (d: number, h: number) => Date.UTC(2026, 9, d, h);
  const v = fleetView(
    [
      { station: "w/a", online: true, rows: [row(agent(true)), row(agent(true), agent(false)), row(agent(false))], archived: [on(25, 9), on(26, 1), on(26, 2), on(1, 3)] },
      { station: "w/b", online: true, rows: [row(agent(true))], archived: [on(25, 20), on(26, 5), on(26, 6)] },
      // down: none of what it last said counted
      { station: "w/c", online: false, rows: [row(agent(true))], archived: [on(26, 7)] },
    ],
    [account("claude", 50)],
    usage,
    "10月26日 04:12",
  );
  assert.deepEqual([v.chats, v.chatsText, v.where, v.at, v.quotaLead], [3, "3 个对话正在运行", "分布在 2 台设备", "10月26日 04:12", "本周用掉了"]);
  assert.equal(v.quota[0].usedText, "50%");
  assert.deepEqual(v.today, { title: "今天", stats: [{ label: "归档的对话", value: "4 个" }, { label: "折合费用", value: "$8" }] });
  assert.deepEqual(v.week.stats, [{ label: "归档的对话", value: "6 个" }, { label: "输入 token", value: "1.2M" }, { label: "折合费用", value: "$12" }]);
  assert.deepEqual(v.week.days, [{ label: "10/25", share: 0.5, today: false }, { label: "10/26", share: 1, today: true }]);
  // nothing of the days while they are read, or with nothing spent nor archived
  assert.deepEqual([fleetView([], [], null).today, fleetView([], [], null).week], [undefined, undefined]);
  const none = fleetView([], [], { ...usage, empty: true });
  assert.deepEqual([none.today, none.week, none.quota], [undefined, undefined, []]);
});
