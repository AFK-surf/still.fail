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

test("the_card_has_a_row_for_each_thing_it_has", () => {
  const agent = {
    turns: [turn(0, 5), turn(10 * MIN, 7)],
    account: { name: "lin@acme.dev", quotaLine: { text: "5 小时剩 12%", level: "red" } },
    attention: [
      { kind: "quota", text: "5 小时剩余 12%", more: "2 小时后恢复", quota: { level: "red" } },
      { kind: "disk", text: "磁盘剩 8 GB" },
    ],
    jobs: [{ name: "web", state: "running", port: 5173 }],
  };
  const live = { usage: { modelCalls: 40, inputTokens: 1_200_000, cachedTokens: 1_080_000, outputTokens: 34_000, contextTokens: 190_000, contextWindow: 200_000, cost: 4.2, unpricedCalls: 0 } };
  const rows = card(agent, live).rows.map((r) => [r.label, r.value, r.level ?? null]);
  assert.deepEqual(rows.map((r) => r[0]), ["工作", "费用估算", "Token", "缓存命中率", "上下文", "账号", "额度", "后台", "注意"]);
  assert.deepEqual(rows.find((r) => r[0] === "缓存命中率"), ["缓存命中率", "90%", null]);
  assert.equal(rows.find((r) => r[0] === "上下文")?.[2], "red");
  assert.deepEqual(rows.find((r) => r[0] === "额度"), ["额度", "5 小时剩 12% · 2 小时后恢复", "red"]);
  assert.deepEqual(rows.at(-1), ["注意", "磁盘剩 8 GB", "amber"]);
  // Before its first turn and its usage is read: nothing but its account.
  assert.deepEqual(card({ turns: [], profile: { name: "lin" }, attention: [], jobs: [] }, null).rows.map((r) => r.label), ["账号"]);
});
