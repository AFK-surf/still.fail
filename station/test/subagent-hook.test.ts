// The hook a Claude Code session runs before a tool it speaks by (src/agents/subagent-hook.mjs; agents/claude.ts gives
// it those tools alone, test/claude.test.ts): a subagent's call is refused with what to do instead, the session's own
// agent's is let through, and so is whatever the hook cannot read. Of slack_api a subagent's writes are refused and
// its reads let through, a write being what the station's threads rule takes for one.
// Run as a session runs it: the command its settings carry (`SILENT_SUBAGENTS`), by a shell, so that the file, the
// Node, the words it is told and their quoting are the ones a session gets.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { SILENT_SUBAGENTS, SUBAGENT_HOOK } from "../src/agents/claude.ts";
import { chatTools } from "../src/tools/chat.ts";
import { SLACK_WRITES, SPEAKS, isSlackWrite } from "../src/tools/mcp.ts";

const COMMAND = SILENT_SUBAGENTS.PreToolUse[0]!.hooks[0]!.command;

/// What Claude Code 2.1.323 gave a PreToolUse hook for a call of `tool`, run as the station runs it (2026-11-14): the
/// session's own agent's, and with `agent` the same call made inside a subagent.
const given = (tool: string, agent?: { agent_id: string; agent_type: string }) => ({
  session_id: "3926f368-70fa-4840-9419-55087ee5692e",
  transcript_path: "/home/projects/-work/3926f368-70fa-4840-9419-55087ee5692e.jsonl",
  cwd: "/work",
  prompt_id: "a8793534-3616-4113-a922-7ba5446dd824",
  permission_mode: "bypassPermissions",
  ...agent,
  hook_event_name: "PreToolUse",
  tool_name: `mcp__stillfail__${tool}`,
  tool_input: { text: "done" } as Record<string, unknown>,
  tool_use_id: "toolu_01",
  mcp_server: { name: "stillfail", source: "dynamic" },
});

/// What the hook says of `input` (a text given as it is): its exit status and its output, as Claude Code reads them.
function hook(input: unknown) {
  const ran = spawnSync("sh", ["-c", COMMAND], { input: typeof input === "string" ? input : JSON.stringify(input) });
  return { status: ran.status, out: ran.stdout.toString(), err: ran.stderr.toString() };
}
const silent = { status: 0, out: "", err: "" };

test("the session's own agent's call is let through, with nothing said", () => {
  for (const tool of SPEAKS) assert.deepEqual(hook(given(tool)), silent, tool);
  // A session started as a named agent says its type and is no subagent.
  assert.deepEqual(hook({ ...given("chat_post"), agent_type: "reviewer" }), silent);
});

test("a subagent's call is refused, of whatever kind it is, and told to hand its result back", () => {
  // As each said itself: started in the foreground or the background, by a subagent, by a forked skill; an Explore; a fork.
  for (const agent_type of ["general-purpose", "Explore", "fork"]) {
    for (const tool of SPEAKS) {
      const said = hook(given(tool, { agent_id: "a9f69f7989c7a17a7", agent_type }));
      assert.deepEqual([said.status, said.err], [0, ""], `${agent_type} ${tool}`);
      const { hookSpecificOutput: answer, ...rest } = JSON.parse(said.out);
      assert.deepEqual(rest, {});
      assert.deepEqual(Object.keys(answer), ["hookEventName", "permissionDecision", "permissionDecisionReason"]);
      assert.deepEqual([answer.hookEventName, answer.permissionDecision], ["PreToolUse", "deny"]);
      // The tool by the name the station gives it, that nothing was done, and what to do instead.
      assert.match(answer.permissionDecisionReason, new RegExp(`^Refused: you are a subagent, and ${tool} is only for the agent that started you\\.`));
      assert.match(answer.permissionDecisionReason, /Nothing was sent or changed\./);
      assert.match(answer.permissionDecisionReason, /give what you did or found as your final answer/);
    }
  }
  // Without a type too: the id alone says a subagent.
  assert.equal(JSON.parse(hook({ ...given("chat_post"), agent_id: "a1" }).out).hookSpecificOutput.permissionDecision, "deny");
});

test("what the hook cannot read is let through: a session that cannot speak is worse than a subagent that can", () => {
  for (const input of ["", "not json", "{", "null", "[]", "42", JSON.stringify({ agent_id: "" }), JSON.stringify({ agent_id: null })]) assert.deepEqual(hook(input), silent, JSON.stringify(input));
});

const SUB = { agent_id: "a9f69f7989c7a17a7", agent_type: "general-purpose" };
/// A call of slack_api with `method`, the session's own agent's or (with `agent`) a subagent's.
const slack = (method: unknown, agent?: typeof SUB) => ({ ...given("slack_api", agent), tool_input: { method, params: { channel: "C1", text: "hi" } } });

test("of slack_api a subagent's writes are refused and its reads let through; the session's own agent's all go through", () => {
  for (const method of ["chat.postMessage", "chat.update", "chat.delete", "reactions.add", "files.completeUploadExternal", "assistant.threads.setStatus", "conversations.history", "users.info"]) {
    assert.deepEqual(hook(slack(method)), silent, method);
  }
  for (const method of ["conversations.history", "conversations.replies", "conversations.open", "users.info", "files.info", "reactions.get", "chat.getPermalink", "auth.test"]) {
    assert.deepEqual(hook(slack(method, SUB)), silent, method);
  }
  const said = hook(slack("chat.postMessage", SUB));
  assert.deepEqual([said.status, said.err], [0, ""]);
  const answer = JSON.parse(said.out).hookSpecificOutput;
  assert.deepEqual([answer.hookEventName, answer.permissionDecision], ["PreToolUse", "deny"]);
  // The method refused, that reading is fine, that nothing was done, and what to do instead.
  assert.match(answer.permissionDecisionReason, /^Refused: you are a subagent, and writing to Slack \(chat\.postMessage\) is only for the agent that started you\. Reading Slack with slack_api is fine \(conversations\.history, /);
  assert.match(answer.permissionDecisionReason, /Nothing was sent or changed\./);
  assert.match(answer.permissionDecisionReason, /give what you did or found as your final answer/);
});

test("what the hook takes for a Slack write is what the station's threads rule takes for one", () => {
  const refused = (method: unknown) => {
    const said = hook(slack(method, SUB));
    assert.deepEqual([said.status, said.err], [0, ""], JSON.stringify(method));
    return said.out !== "" && JSON.parse(said.out).hookSpecificOutput.permissionDecision === "deny";
  };
  // Every entry of the list, as it is and as the start of a longer method; reads; near misses; and the method as the
  // tool reads it (src/tools/slack.ts trims it).
  const methods = [
    ...SLACK_WRITES,
    ...SLACK_WRITES.map((w) => `${w}More`),
    ...SLACK_WRITES.map((w) => ` ${w}\n`),
    ...["conversations.history", "conversations.replies", "users.info", "files.info", "files.getUploadURLExternal", "reactions.get", "reactions.list", "pins.list", "chat.getPermalink"],
    ...["Chat.postMessage", "chat.post", "chat", "xchat.postMessage", "assistant.threads", "assistant.search.context", ""],
  ];
  for (const method of methods) assert.equal(refused(method), isSlackWrite(method.trim()), JSON.stringify(method));
  assert.ok(methods.some((m) => isSlackWrite(m.trim())) && methods.some((m) => !isSlackWrite(m.trim())));
  // No method, or one that is no text: none the station would call (it answers that it is no Slack method).
  for (const method of [undefined, null, 7, ["chat.postMessage"], { method: "chat.postMessage" }]) assert.equal(refused(method), false, JSON.stringify(method));
  assert.deepEqual(hook({ ...given("slack_api", SUB), tool_input: undefined }), silent);
});

test("a command line from before it was told Slack's writes still refuses what it did, and takes no Slack call for a write", () => {
  // A session's process keeps the command it was started with while the file becomes the next release's.
  const older = (input: unknown) => spawnSync(process.execPath, [SUBAGENT_HOOK], { input: JSON.stringify(input) }).stdout.toString();
  assert.equal(JSON.parse(older(given("chat_post", SUB))).hookSpecificOutput.permissionDecision, "deny");
  assert.equal(older(given("chat_post")), "");
  assert.equal(older(slack("chat.postMessage", SUB)), "");
});

test("the tools a session speaks by are tools the station has", () => {
  const names = chatTools({} as any).map((t) => t.name);
  for (const tool of SPEAKS) assert.ok(names.includes(tool), tool);
  assert.deepEqual(SPEAKS, ["chat_post", "chat_state", "session_send", "chat_create", "chat_leave", "chat_archive"]);
});
