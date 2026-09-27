import assert from "node:assert/strict";
import { test } from "node:test";
import { ThreadStatus, toolStatus } from "../src/chat/slack-status.ts";

const settle = (ms = 30) => new Promise((r) => setTimeout(r, ms));

test("a thread's status line says what the agent does, and goes when it is done", async () => {
  const calls: [string, Record<string, string>][] = [];
  const line = new ThreadStatus(async (method, params) => { calls.push([method, params]); }, "C1", "1.1");
  line.say("正在思考…", "1.2");
  await settle();
  line.say("", null);
  await settle();
  assert.deepEqual(calls.map(([m, p]) => [m, p.status]), [["assistant.threads.setStatus", "正在思考…"], ["assistant.threads.setStatus", ""]]);
  assert.deepEqual([calls[0]![1].channel_id, calls[0]![1].thread_ts], ["C1", "1.1"]);
});

test("where Slack will not show a status, an 👀 on the message that started the work stands in", async () => {
  const calls: [string, Record<string, string>][] = [];
  const line = new ThreadStatus(async (method, params) => {
    calls.push([method, params]);
    if (method === "assistant.threads.setStatus") throw new Error("slack assistant.threads.setStatus: missing_scope");
  }, "C1", "1.1");
  line.say("正在运行命令…", "1.2");
  await settle();
  line.say("", null);
  await settle();
  assert.deepEqual(calls.map(([m, p]) => [m, p.timestamp ?? null, p.name ?? null]), [
    ["assistant.threads.setStatus", null, null], ["reactions.add", "1.2", "eyes"], ["reactions.remove", "1.2", "eyes"],
  ]);
});

test("tool calls in words, by either runtime's names", () => {
  assert.deepEqual(["Read", "Bash", "exec_command", "apply_patch", "WebSearch", "mcp__ember__chat_post", "something"].map(toolStatus),
    ["正在查看文件…", "正在运行命令…", "正在运行命令…", "正在修改文件…", "正在搜索网页…", "正在看 Slack…", "正在处理…"]);
});
