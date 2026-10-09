// An agent in brief, for its card (views/brief.ts): its turns and how long they took, its jobs at work.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { card, jobsText, workText } from "../src/views/brief.ts";

holdLanguage();
const MIN = 60_000;
const turn = (startedAt: number, minutes: number | null) => ({ id: `t${startedAt}`, kind: "input", startedAt, endedAt: minutes === null ? null : startedAt + minutes * MIN });

test("work_counts_turns_and_the_time_finished_ones_took", () => {
  assert.equal(workText([]), null);
  assert.equal(workText([turn(0, 0.2)]), "1 轮");
  assert.equal(workText([turn(0, 5), turn(10 * MIN, 7), turn(30 * MIN, null)]), "3 轮 · 共干了 12 分钟");
  assert.equal(workText([turn(0, 50), turn(60 * MIN, 22)]), "2 轮 · 共干了 1 小时 12 分");
});

test("jobs_at_work_by_what_they_are", () => {
  const job = (name: string, patch: object = {}) => ({ name, state: "running", port: null, ...patch });
  assert.equal(jobsText([]), null);
  assert.equal(jobsText([job("old", { state: "exited", exitCode: 0 }), job("web", { state: "stopped", port: 5173 })]), null);
  assert.equal(
    jobsText([job("web", { port: 5173 }), job("api", { port: 8080 }), job("CI", { watch: true }), job("build"), job("lint")]),
    "服务在线：web、api · 在盯着：CI · 2 个任务在跑",
  );
});

test("the_card_says_what_it_did_cost_and_used", () => {
  const agent = {
    turns: [turn(0, 5), turn(10 * MIN, 7)],
    attention: [{ kind: "quota", text: "5 小时剩余 12%", quota: { level: "red" } }, { kind: "disk", text: "磁盘剩 8 GB" }, { kind: "account", text: "「lin」要重新登录" }],
    jobs: [{ name: "web", state: "running", port: 5173 }],
  };
  const live = { usage: { modelCalls: 40, inputTokens: 1_200_000, cachedTokens: 1_080_000, outputTokens: 34_000, contextTokens: 190_000, contextWindow: 200_000, cost: 4.2, unpricedCalls: 0 } };
  const c = card(agent, live);
  assert.equal(c.work, "2 轮 · 共干了 12 分钟");
  assert.equal(c.cost, "$4.20");
  assert.equal(c.tokens, "输入 1.2M · 输出 34K");
  assert.deepEqual(c.cache, { percent: 90, text: "90%", level: "ok" });
  assert.deepEqual(c.context, { percent: 95, text: "190K / 200K", level: "red" });
  assert.equal(c.jobs, "服务在线：web");
  // A quota running out is its account's windows' to say.
  assert.deepEqual(c.attention, [{ text: "磁盘剩 8 GB", level: "amber" }, { text: "「lin」要重新登录", level: "red" }]);
  // Before its first turn and its usage is read: nothing.
  const none = card({ turns: [], attention: [], jobs: [] }, null);
  assert.deepEqual([none.work, none.cost, none.cache, none.context, none.jobs, none.attention], [null, undefined, undefined, undefined, null, []]);
});
