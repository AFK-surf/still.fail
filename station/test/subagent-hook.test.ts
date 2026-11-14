// The hook a Claude Code session runs before a tool it speaks by (src/agents/subagent-hook.mjs; agents/claude.ts gives
// it those tools alone, test/claude.test.ts): a subagent's call is refused with what to do instead, the session's own
// agent's is let through, and so is whatever the hook cannot read.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { chatTools } from "../src/tools/chat.ts";
import { SPEAKS } from "../src/tools/mcp.ts";

// (the file agents/claude.ts names as SUBAGENT_HOOK: test/claude.test.ts holds that it is the one started)
const SUBAGENT_HOOK = fileURLToPath(new URL("../src/agents/subagent-hook.mjs", import.meta.url));

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
  tool_input: { text: "done" },
  tool_use_id: "toolu_01",
  mcp_server: { name: "stillfail", source: "dynamic" },
});

/// What the hook says of `input` (a text given as it is): its exit status and its output, as Claude Code reads them.
function hook(input: unknown) {
  const ran = spawnSync(process.execPath, [SUBAGENT_HOOK], { input: typeof input === "string" ? input : JSON.stringify(input) });
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

test("the tools a session speaks by are tools the station has", () => {
  const names = chatTools({} as any).map((t) => t.name);
  for (const tool of SPEAKS) assert.ok(names.includes(tool), tool);
  assert.deepEqual(SPEAKS, ["chat_post", "chat_state", "session_send", "chat_create", "chat_leave", "chat_archive"]);
});
