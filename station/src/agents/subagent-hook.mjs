// A PreToolUse hook of Claude Code's: a subagent's call of a tool by which a session speaks or acts in chats as itself
// (tools/mcp.ts `SPEAKS`, and slack_api where its method writes; Claude Code runs this for those alone, by the matcher
// agents/claude.ts makes of them) is refused before it is made. A subagent (Claude Code's Agent tool, a skill that
// runs forked) is given its session's tools and none of the station's instructions, and its call reaches the station
// with its session's token, as its parent's does: the station cannot tell them apart, Claude Code can. What it gives a
// hook says `agent_id` inside a subagent and not in the session's own agent (2.1.323, 2026-11-14, as the station
// starts it: there for a subagent in the foreground and in the background, a fork, an Explore, one started by a
// subagent, a forked skill's; absent for the main agent); `agent_type` is no sign of one, a session started with
// --agent has it too.
// The refusal is the hook's answer, not its failure: it stood with --dangerously-skip-permissions, the call never
// reached the station, and the subagent's model was given the reason as the tool's error.
// argv[2]: the Slack methods that write, as the station tells them (tools/mcp.ts `SLACK_WRITES`, joined by commas: a
// method that starts with one is a write). This file is the release's and its command line the one a session's
// process was started with, by an older release too: what an older one did not say is read as nothing said.
import { readFileSync } from "node:fs";

let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch {
  // What cannot be read is let through, on purpose, as is anything else that goes wrong here (the command ends
  // `|| true`): this runs before the main agent's every post and every turn's end, and a session that cannot speak is
  // worse than a subagent that can, as it could before there was this.
  process.exit(0);
}
const agent = input?.agent_id;
if (agent === undefined || agent === null || agent === "") process.exit(0);

const tool = typeof input.tool_name === "string" ? input.tool_name.split("__").at(-1) : "this tool";
const instead = "Nothing was sent or changed. Do not retry, and do not look for another way to do it: finish your task and give what you did or found as your final answer. The agent that started you reads it and posts what people need.";
let reason = `Refused: you are a subagent, and ${tool} is only for the agent that started you. A subagent does not post to the chat, end the turn, write to another chat's agent, or open, leave or archive a chat. ${instead}`;
if (tool === "slack_api") {
  // A subagent reads Slack as its parent does; only a write is its parent's alone. The method as the station reads it
  // (tools/slack.ts trims it; one that is no text is no method there, and is left to the station to refuse).
  const method = typeof input.tool_input?.method === "string" ? input.tool_input.method.trim() : "";
  const writes = (process.argv[2] ?? "").split(",").filter((w) => w !== "");
  if (!writes.some((w) => method.startsWith(w))) process.exit(0);
  reason = `Refused: you are a subagent, and writing to Slack (${method.slice(0, 60)}) is only for the agent that started you. Reading Slack with slack_api is fine (conversations.history, conversations.replies, users.info, files.info and the like). ${instead}`;
}
process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: reason } }));
