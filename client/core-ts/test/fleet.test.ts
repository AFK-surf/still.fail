import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { fleetView, machineOf } from "../src/views/fleet.ts";

holdLanguage();
// deno-lint-ignore no-explicit-any
type J = any;
const agent = (model: string, running: boolean): J => ({ key: model, runtime: "claude", model, process: running ? "running" : "cold", pending: 0 });
const row = (...agents: J[]): J => ({ id: "1", agents });
const host = { cpuModel: "Apple M2 Max", memory: { totalBytes: 64 * 1024 ** 3 } };

test("the card shared says how many agents are at work, on which machines, with which models", () => {
  const v = fleetView(
    [
      { station: "w/a", name: "Studio", online: true, running: 3, host, rows: [row(agent("claude-opus-5-5", true), agent("gpt-6", true)), row(agent("claude-opus-5-5", true))] },
      { station: "w/b", name: "ccvm", online: true, running: 5, host: undefined, rows: [row(agent("deepseek-v4", true), agent("claude-opus-5-5", false))] },
      // idle, or down whatever it last counted: not on the card
      { station: "w/c", name: "Mini1", online: true, running: 0, host, rows: [] },
      { station: "w/d", name: "MBA", online: false, running: 2, host, rows: [] },
    ],
    null,
  );
  assert.equal(v.running, 8);
  assert.equal(v.unit, "个 agent 正在运行");
  assert.equal(v.where, "分布在 2 台设备 · 3 种模型");
  // the busiest first, each with its machine and its agents' makers, the most first
  assert.deepEqual(v.stations.map((s: J) => [s.name, s.running, s.machine, s.makers]), [
    ["ccvm", 5, null, ["deepseek"]],
    ["Studio", 3, "Apple M2 Max · 64 GB", ["anthropic", "openai"]],
  ]);
  // the models at work, the most first (an agent not at work not counted)
  assert.equal(v.models[0].count, 2);
  assert.equal(v.models[0].maker, "anthropic");
  assert.equal(v.models[0].text, "×2");
  assert.equal(v.models.length, 3);
  // nothing of the last 7 days while they are read
  assert.equal(v.week, undefined);
  assert.equal(machineOf(undefined), null);
});

test("the card shared's last 7 days: its calls, input tokens and cost, each day's calls as a share of the busiest", () => {
  const tile = (label: string, value: string) => ({ label, value, sub: "" });
  const usage = {
    empty: false,
    tiles: [tile("折合费用", "$12"), tile("模型调用", "300 次"), tile("输入 token", "1.2M"), tile("输出 token", "40k")],
    daily: [{ label: "10/25", calls: 100, today: false }, { label: "10/26", calls: 200, today: true }],
  };
  const v = fleetView([], usage);
  assert.deepEqual(v.week.stats.map((s: J) => s.value), ["300 次", "1.2M", "$12"]);
  assert.deepEqual(v.week.days, [{ label: "10/25", share: 0.5, today: false }, { label: "10/26", share: 1, today: true }]);
  assert.equal(fleetView([], { ...usage, empty: true }).week, undefined);
});
