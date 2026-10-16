// An agent in brief, for its card (views/brief.ts): its turns and how long they took, its jobs at work.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { card, jobsText, latestOf, recentOf, workText } from "../src/views/brief.ts";

holdLanguage();
const MIN = 60_000;
const turn = (startedAt: number, minutes: number | null) => ({ id: `t${startedAt}`, kind: "input", startedAt, endedAt: minutes === null ? null : startedAt + minutes * MIN });

test("work_counts_turns_and_the_time_finished_ones_took", () => {
  assert.equal(workText([]), null);
  assert.equal(workText([turn(0, 0.2)]), "1 轮");
  assert.equal(workText([turn(0, 5), turn(10 * MIN, 7), turn(30 * MIN, null)]), "3 轮 · 共工作 12 分钟");
  assert.equal(workText([turn(0, 50), turn(60 * MIN, 22)]), "2 轮 · 共工作 1 小时 12 分");
});

test("jobs_at_work_by_what_they_are", () => {
  const job = (name: string, patch: object = {}) => ({ name, state: "running", port: null, ...patch });
  assert.equal(jobsText([]), null);
  assert.equal(jobsText([job("old", { state: "exited", exitCode: 0 }), job("web", { state: "stopped", port: 5173 })]), null);
  assert.equal(
    jobsText([job("web", { port: 5173 }), job("api", { port: 8080 }), job("CI", { watch: true }), job("build"), job("lint")]),
    "服务在线：web、api · 正在监控：CI · 2 个任务运行中",
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
  assert.equal(c.work, "2 轮 · 共工作 12 分钟");
  assert.equal(c.cost, "$4.20");
  assert.equal(c.tokens, "输入 1.2M · 输出 34K");
  assert.deepEqual(c.cache, { percent: 90, text: "90%", level: "ok" });
  assert.deepEqual(c.context, { percent: 95, text: "190K / 200K", level: "red" });
  assert.equal(c.jobs, "服务在线：web");
  // A quota running out is its account's windows' to say.
  assert.deepEqual(c.attention, [{ text: "磁盘剩 8 GB", level: "amber" }, { text: "「lin」要重新登录", level: "red" }]);
  // Before its first turn and its usage is read: nothing.
  const none = card({ turns: [], attention: [], jobs: [] }, null);
  assert.deepEqual([none.work, none.cost, none.cache, none.context, none.jobs, none.latest, none.attention], [null, undefined, undefined, undefined, null, [], []]);
});

test("the_latest_three_things_it_did_oldest_first", () => {
  const call = (tool: string, input: object, more: object = {}) => ({ kind: "tool_call", tool, text: JSON.stringify(input), ...more });
  const timeline = [
    { kind: "user", text: "修一下登录" },
    call("Read", { file_path: "/src/login.ts" }),
    { kind: "tool_result", text: "…" },
    { kind: "thinking", text: "\n宽度写死了\n改成撑满" },
    call("Bash", { command: "pnpm test login", description: "跑登录测试" }),
    call("Grep", { pattern: "width" }, { subagent: true }),
    { kind: "tool_result", text: "ok" },
    { kind: "assistant", text: "测试过了。\n\n接着发消息" },
    call("mcp__stillfail__chat_post", { to: "EMBER/1", text: "改好了\n详情见 PR" }),
    call("mcp__stillfail__chat_state", { kind: "all_done", done: "合了" }),
  ];
  const lines = (live: unknown) => recentOf(live).map((r) => `${r.key} ${r.text}`);
  assert.deepEqual(lines({ timeline }), ["4 跑登录测试", "7 测试过了。", "8 改好了"]);
  assert.deepEqual(lines({ timeline: timeline.slice(0, 4) }), ["1 读取 login.ts", "3 宽度写死了"]);
  // A key is its entry's place in the whole transcript: the same as older entries are left out of what is read.
  assert.deepEqual(lines({ first: 100, timeline: timeline.slice(4) }), ["100 跑登录测试", "103 测试过了。", "104 改好了"]);
  assert.deepEqual(recentOf(null), []);
  assert.equal(card({ turns: [], attention: [], jobs: [] }, { timeline }).latest.length, 3);
});

test("its_latest_lines_end_with_what_it_does_now_while_it_works", () => {
  const call = (description: string) => ({ kind: "tool_call", tool: "Bash", text: JSON.stringify({ command: "x", description }) });
  const timeline = [call("拉代码"), call("装依赖"), call("跑测试")];
  const live = (text: string) => ({ timeline, activity: { now: { key: "k", text } } });
  const lines = (agent: unknown, l: unknown) => latestOf(agent, l).map((r) => `${r.key} ${r.text}${r.now ? " now" : ""}`);
  // At work: what it does now is the last of the three, the oldest thing done gives way.
  assert.deepEqual(lines({ status: "running" }, live("写报告")), ["1 装依赖", "2 跑测试", "now 写报告 now"]);
  assert.deepEqual(lines({ status: "queued" }, { timeline: [], activity: { now: { key: "k", text: "排队中" } } }), ["now 排队中 now"]);
  // What it does now is the last thing done already: said once.
  assert.deepEqual(lines({ status: "running" }, live("跑测试")), ["0 拉代码", "1 装依赖", "2 跑测试"]);
  // Not at work: only what it did.
  assert.deepEqual(lines({ status: "final" }, live("写报告")), ["0 拉代码", "1 装依赖", "2 跑测试"]);
  assert.deepEqual(latestOf({ status: "running" }, null), []);
});
