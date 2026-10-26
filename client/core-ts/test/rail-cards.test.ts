import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { chatsCard, usageCard } from "../src/views/rail-cards.ts";

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

test("用量's card: the last 7 days' cost, today's and the input tokens, a bar a day, the models that cost most, 分享卡片", () => {
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
  assert.equal(card.share, true);
  // nothing spent: said so, nothing to share
  assert.deepEqual(usageCard({ empty: true }), { head: "近 7 天没有用量", stats: [], rows: [] });
});
