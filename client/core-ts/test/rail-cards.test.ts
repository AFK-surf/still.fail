import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { quotaOf } from "../src/views/fleet.ts";
import { chatsCard, profilesCard, stationsCard, usageCard } from "../src/views/rail-cards.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const agent = (running: boolean): J => ({ key: "a", runtime: "claude", model: "claude-opus-5-5", process: running ? "running" : "cold", pending: 0 });
const on = (d: number, h: number) => Date.UTC(2026, 9, d, h);
const figures = (card: J) => card.stats.map((s: J) => [s.value, s.label, s.tone ?? ""]);

test("对话's card: how many chats are at work, then those waiting for the viewer, gone wrong, unread, archived today", () => {
  const rows = [{ agents: [agent(true)] }, { agents: [agent(false), agent(true)] }, { agents: [agent(false)] }];
  const card = chatsCard(rows, { wait: 2, alert: 1, unread: 3 }, [on(26, 1), on(26, 9), on(25, 20)], on(26, 12), 0);
  assert.equal(card.head, "2 个对话正在运行");
  assert.deepEqual(figures(card), [["2", "等你处理", "amber"], ["1", "出错", "red"], ["3", "未读", ""], ["2", "今天归档", ""]]);
  // none at work, none wanting anything: said so, nothing coloured
  const quiet = chatsCard([{ agents: [agent(false)] }], null, [], on(26, 12), 0);
  assert.equal(quiet.head, "暂无对话在运行");
  assert.deepEqual(quiet.stats.map((s: J) => s.tone ?? ""), ["", "", "", ""]);
});

test("Station's card: the agents at work, the stations up of all, the tasks at work; each station with its chip, CPU and memory", () => {
  const meter = (short: string, percent: number, level: string) => ({ short, percent, level });
  const host = (cpu: number, level: string) => ({ identity: "Apple M2 Max · 64 GB · macOS 26", meters: [meter("CPU", cpu, level), meter("内存", 54, "ok"), meter("磁盘", 99, "red")] });
  const job = (more: J = {}): J => ({ state: "running", port: null, ...more });
  const card = stationsCard({ running: 9, now: "9 个 agent 正在运行" }, [
    // a task, and what is not one: a watch, a service, one waiting in the queue, one over
    { station: { name: "Studio", state: "online", doing: "5 个正在运行" }, host: host(62, "ok"), jobs: [job(), job({ watch: true }), job({ port: 5173 }), job({ queued: true }), job({ state: "exited" })] },
    { station: { name: "ccvm", state: "online", doing: "4 个正在运行" }, host: host(81, "amber"), jobs: [job()] },
    { station: { name: "MBA", state: "error", doing: "连不上" }, host: host(10, "ok"), jobs: [job()] },
  ]);
  assert.equal(card.head, "9 个 agent 正在运行");
  assert.deepEqual(figures(card), [["2/3", "在线设备", "amber"], ["3", "后台任务", ""]]);
  assert.deepEqual(card.rows.map((r: J) => [r.name, r.value, r.tone ?? "", r.sub ?? "", r.subTone ?? ""]), [
    ["Studio", "5 个正在运行", "", "Apple M2 Max · CPU 62% · 内存 54%", ""],
    ["ccvm", "4 个正在运行", "", "Apple M2 Max · CPU 81% · 内存 54%", "amber"],
    // not up: what its machine last said is not said
    ["MBA", "连不上", "red", "", ""],
  ]);
  assert.equal(card.share, true);
  assert.equal(stationsCard({ running: 0, now: "暂无 agent 在运行" }, []).share, false);
});

test("Profile's card: the subscriptions with room, nearly through a window, used one up; each kind's week; the one wanting a look that refills soonest", () => {
  const now = on(26, 12);
  const account = (name: string, group: string, used: number | null, resetsAt: number | null = null, state = "ok"): J => ({
    group,
    profile: { name, quota: { state, windows: used === null ? [] : [{ label: "每周", usedPercent: used, ...(resetsAt === null ? {} : { resetsAt }) }] } },
  });
  const items = [
    account("c1", "claude", 30),
    account("c2", "claude", 85, now + 5 * 3600_000),
    account("c3", "claude", 100, now + 2 * 3600_000),
    account("g1", "chatgpt", 10),
    // a key, a quota not read, one with no window: none of them
    account("k", "key", 99),
    account("c4", "claude", 95, now + 3600_000, "unavailable"),
    account("c5", "claude", null),
  ];
  const card = profilesCard(items, quotaOf(items), now);
  assert.equal(card.head, "1 个账号额度用完了");
  assert.deepEqual(figures(card), [["2", "额度充足", ""], ["1", "快用完", "amber"], ["1", "已用完", "red"]]);
  assert.deepEqual(card.rows.map((r: J) => r.name), ["用 3 个 Claude 订阅账号消耗了 215% 的周额度", "用 1 个 ChatGPT 订阅账号消耗了 10% 的周额度"]);
  assert.equal(card.note, "c3 的额度 2 小时后刷新");
  // all with room: how many there are, no line more
  const fine = profilesCard([account("c1", "claude", 30)], [], now);
  assert.deepEqual([fine.head, fine.note], ["1 个订阅账号", undefined]);
});

test("用量's card: the last 7 days' cost, today's and the input tokens, a bar a day, the models that cost most", () => {
  const tile = (label: string, value: string) => ({ label, value, sub: "" });
  const model = (title: string, costText: string, shareText: string) => ({ title, costText, shareText });
  const usage = {
    empty: false,
    tiles: [tile("折合费用", "$12"), tile("模型调用", "300 次"), tile("输入 token", "1.2M"), tile("输出 token", "40k")],
    daily: [
      { label: "10/25", cost: 4, costText: "$4", today: false },
      { label: "10/26", cost: 8, costText: "$8", today: true },
    ],
    lists: [{ key: "people", items: [] }, { key: "models", items: [model("Opus 5.5", "$9", "75%"), model("GPT-6", "$2", "17%"), model("Sonnet 5", "$1", "8%"), model("Haiku", "$0", "0%")] }],
  };
  const card = usageCard(usage);
  assert.equal(card.head, "近 7 天折合 $12");
  assert.deepEqual(figures(card), [["$8", "今天", ""], ["1.2M", "输入 token", ""]]);
  assert.deepEqual(card.rows.map((r: J) => [r.name, r.value]), [["Opus 5.5", "$9 · 75%"], ["GPT-6", "$2 · 17%"], ["Sonnet 5", "$1 · 8%"]]);
  assert.deepEqual(card.days, [{ label: "10/25", share: 0.5, today: false }, { label: "10/26", share: 1, today: true }]);
  assert.deepEqual(usageCard({ empty: true }), { head: "近 7 天没有用量", stats: [], rows: [] });
});
