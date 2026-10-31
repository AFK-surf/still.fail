// An agent in brief, for its card (views/brief.ts): its turns and how long they took, its jobs at work.
import assert from "node:assert/strict";
import { test } from "node:test";
import { holdLanguage } from "../src/i18n.ts";
import { cacheCold, card, jobsText, latestOf, recentOf, usageNow, workText } from "../src/views/brief.ts";

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
    attention: [{ kind: "quota", text: "5 小时剩余 12%", quota: { level: "red" } }, { kind: "disk", text: "磁盘剩 8 GB" }, { kind: "account", text: "「lin」需要重新登录" }],
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
  assert.deepEqual(c.attention, [{ text: "磁盘剩 8 GB", level: "amber" }, { text: "「lin」需要重新登录", level: "red" }]);
  // Before its first turn and its usage is read: nothing.
  const none = card({ turns: [], attention: [], jobs: [] }, null);
  assert.deepEqual([none.work, none.cost, none.cache, none.context, none.jobs, none.latest, none.attention], [null, undefined, undefined, undefined, null, [], []]);
});

test("what_it_used_is_its_streams_while_it_works_else_its_summarys", () => {
  const told = { modelCalls: 3, inputTokens: 100, cachedTokens: 50, outputTokens: 5, contextTokens: 40, contextWindow: null, cost: 0.1, unpricedCalls: 0 };
  const said = { ...told, modelCalls: 5, cost: 0.3 };
  const rested = { lastTurn: { id: "t", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed" }, usage: said };
  const working = { ...rested, process: "running" };
  assert.equal(usageNow(rested, { usage: told }), said, "at rest: its summary's, the station's count since");
  assert.equal(usageNow(working, { usage: told }), told, "at work: its stream's, each call as it is made");
  assert.equal(usageNow(working, {}), said, "at work, its stream not heard yet: its summary's");
  assert.equal(usageNow({ ...rested, usage: undefined }, { usage: told }), told, "a station from before says it on its stream alone");
  assert.equal(usageNow({ ...rested, usage: undefined }, null), null);
  // At rest, followed by no stream: its card says what it used all the same.
  const c = card({ turns: [turn(0, 5)], attention: [], jobs: [], session: rested }, { timeline: [] });
  assert.equal(c.cost, "$0.30");
  assert.deepEqual(c.cache, { percent: 50, text: "50%", level: "ok" });
  assert.deepEqual(c.context, { percent: 0, text: "40", level: "ok", unknown: true });
});

test("an_agent_at_rest_whose_cache_is_over_is_offered_a_fresh_context", () => {
  const HOUR = 60 * MIN;
  const usage = (lastCallAt: number, contextTokens: number, extra: object = {}) =>
    ({ modelCalls: 3, inputTokens: 1, cachedTokens: 0, outputTokens: 1, contextTokens, lastCallAt, cacheMs: HOUR, rereadCost: 1.6, ...extra });
  const agent = (key: string, u: object | null, patch: object = {}) =>
    ({ status: "final", wait: null, session: { key, runtimeSessionId: `r-${key}`, usage: u }, ...patch });
  // Its cache over: said with what going on reads again and what it costs.
  assert.deepEqual(cacheCold([agent("a", usage(0, 200_000))], HOUR), [{ session: "a", status: "缓存已过期", detail: "重读约 $1.60", afresh: false }, Infinity]);
  // Its station going on afresh by itself: what going on would cost said all the same, the choice on afresh.
  assert.deepEqual(cacheCold([agent("a", usage(0, 200_000))], HOUR, true), [{ session: "a", status: "缓存已过期", detail: "重读约 $1.60", afresh: true }, Infinity]);
  // Its chat's own choice outweighs its station's, either way.
  const chose = (afresh: boolean) => agent("a", null, { session: { key: "a", runtimeSessionId: "r-a", usage: usage(0, 200_000), afresh } });
  assert.equal(cacheCold([chose(true)], HOUR)[0].afresh, true);
  assert.equal(cacheCold([chose(false)], HOUR, true)[0].afresh, false);
  // Waiting on work of its own: said too, as what it waits on starts it again.
  assert.equal(cacheCold([agent("a", usage(0, 200_000), { wait: { since: 0, seconds: 600 } })], HOUR)[0].session, "a");
  // Not yet: computed again as it is over.
  assert.deepEqual(cacheCold([agent("a", usage(0, 200_000))], HOUR - 5 * MIN), [null, 5 * MIN]);
  // Unpriced: what it reads, without a cost.
  assert.equal(cacheCold([agent("a", usage(0, 200_000, { rereadCost: undefined }))], HOUR)[0].detail, "重读要 200K token");
  // Of several, the largest context.
  assert.equal(cacheCold([agent("a", usage(0, 80_000)), agent("b", usage(0, 300_000))], 2 * HOUR)[0].session, "b");
  // None at work, cleared already, with a small context, or not told how long its cache lasts.
  for (const a of [
    agent("a", usage(0, 200_000), { status: "running" }),
    agent("a", usage(0, 200_000), { status: "queued" }),
    agent("a", usage(0, 200_000), { session: { key: "a", runtimeSessionId: null, usage: usage(0, 200_000) } }),
    agent("a", usage(0, 20_000)),
    agent("a", usage(0, 200_000, { cacheMs: undefined })),
  ]) assert.deepEqual(cacheCold([a], 2 * HOUR), [null, Infinity]);
});

test("the cache choice follows the station's cost threshold unless the chat chose", () => {
  const hour = 60 * MIN;
  const agent = (cost: number | undefined, afresh?: boolean, contextTokens = 200_000) => ({
    status: "final", wait: null,
    session: {
      key: "a", runtimeSessionId: "r-a", ...(afresh === undefined ? {} : { afresh }),
      usage: { modelCalls: 1, contextTokens, lastCallAt: 0, cacheMs: hour, ...(cost === undefined ? {} : { rereadCost: cost }) },
    },
  });
  assert.equal(cacheCold([agent(0.99)], hour, true, 1)[0].afresh, false);
  assert.equal(cacheCold([agent(1)], hour, true, 1)[0].afresh, true);
  assert.equal(cacheCold([agent(undefined)], hour, true, 1)[0].afresh, false);
  assert.equal(cacheCold([agent(0.2, true)], hour, true, 1)[0].afresh, true);
  assert.equal(cacheCold([agent(2, false)], hour, true, 1)[0].afresh, false);
  // An expensive small context is offered too: the price is the configured condition.
  assert.equal(cacheCold([agent(2, undefined, 40_000)], hour, true, 1)[0].afresh, true);
  assert.equal(cacheCold([agent(2, undefined, 40_000)], hour, false, 1)[0].afresh, false);
});

test("an explicit fresh choice remains visible for a small cold context", () => {
  const hour = 60 * MIN;
  const agent = { status: "final", session: { key: "a", runtimeSessionId: "r-a", afresh: true,
    usage: { modelCalls: 1, contextTokens: 40_000, lastCallAt: 0, cacheMs: hour, rereadCost: 0.3 } } };
  assert.equal(cacheCold([agent], hour, true, 10)[0]?.afresh, true);
});

test("a zero threshold shows a fresh choice whenever the cache expires", () => {
  const hour = 60 * MIN;
  const agent = (contextTokens?: number, afresh?: boolean) => ({
    status: "final",
    session: { key: "a", runtimeSessionId: "r-a", ...(afresh === undefined ? {} : { afresh }),
      usage: { modelCalls: 1, lastCallAt: 0, cacheMs: hour, ...(contextTokens === undefined ? {} : { contextTokens }) } },
  });
  // Neither an unknown price nor an unknown or small context prevents the zero-threshold default.
  for (const context of [undefined, 40_000, 200_000]) {
    assert.equal(cacheCold([agent(context)], hour, true, 0)[0]?.afresh, true);
  }
  assert.equal(cacheCold([agent()], hour, true, 0)[0]?.detail, "重读费用未知");
  assert.deepEqual(cacheCold([agent()], hour - 1, true, 0), [null, 1]);
  assert.deepEqual(cacheCold([agent()], hour, false, 0), [null, Infinity]);
  assert.equal(cacheCold([agent(undefined, false)], hour, true, 0)[0]?.afresh, false);
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
