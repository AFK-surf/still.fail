// Which of the station's tools a session speaks by (src/tools/mcp.ts `SPEAKS`, and slack_api where it writes): those
// are its own agent's, and a subagent is kept from them (station/AGENTS.md, Agents; src/agents/claude.ts
// `SILENT_SUBAGENTS`). Every tool the station declares is sorted here by hand, so that a new one fails this until
// someone has decided whether a subagent may call it: nothing else would put a new tool that writes in a chat into
// the list.
import assert from "node:assert/strict";
import { test } from "node:test";
import { SLACK_WRITES, SPEAKS, SPEAKS_WRITING, isSlackWrite } from "../src/tools/mcp.ts";
import { stationTools } from "./station-tools.ts";

/// By these a session says or does something in a chat as itself: a subagent's call is refused.
const SPEAK = ["chat_post", "chat_state", "session_send", "chat_create", "chat_leave", "chat_archive"];
/// Speaks where its method writes, reads otherwise: a subagent's writes are refused.
const SPEAKS_IN_WRITES = "slack_api";
/// These put a card before a person (a request to approve, a sign-in, a login, a retirement's step), close or renew
/// one, or send a report to the still.fail team: no message of the caller's own in the chat, though a card says its
/// reason. A subagent is not kept from them; whether it should be is the owner's to decide (not decided, 2026-11-14).
const ASKS = [
  "secret_use", "secret_save", "secret_describe", "secret_delete", "secret_reask", "secret_cancel", "sign_in", "login", "station_use", "device_use", "phone_use",
  "station_retire", "feedback_send", "feedback_reply",
];
/// These say nothing in any chat: they read, or work on the station, its jobs, its screens, its devices and its other
/// stations. feishu_api among them: it refuses to send, answer or change a message, and adds only reactions.
const QUIET = [
  "chat_history", "chat_list", "chat_read", "session_history", "archive_policy", "station_list", "station_task", "station_file", "workspace_limit",
  "job_start", "job_list", "job_log", "job_stop", "screen", "permissions", "computer", "peer_forward", "relays", "phone_send", "adb_devices", "browser",
  "device_list", "feishu_api", "skill_read", "search", "secret_list", "secret_run",
];

test("every tool the station declares is sorted: a session speaks by it, or it does not", () => {
  const sorted = [...SPEAK, SPEAKS_IN_WRITES, ...ASKS, ...QUIET];
  assert.equal(new Set(sorted).size, sorted.length, "a tool is sorted twice");
  assert.deepEqual(
    stationTools().map((t) => t.name).sort(),
    [...sorted].sort(),
    "a tool was added or taken away: sort it in test/speaks.test.ts. One by which a session posts, ends its turn, writes to an agent or changes a chat goes in SPEAK and in src/tools/mcp.ts SPEAKS, so that a subagent is kept from it; any other in ASKS or QUIET",
  );
  // What the drivers go by is what is sorted here.
  assert.deepEqual(SPEAKS, SPEAK);
  assert.equal(SPEAKS_WRITING, SPEAKS_IN_WRITES);
});

test("a Slack method writes by one list, the threads rule's: what it names and what begins with it", () => {
  for (const method of ["chat.postMessage", "chat.postEphemeral", "chat.scheduleMessage", "chat.update", "chat.delete", "chat.meMessage", "reactions.add", "reactions.remove", "pins.add", "pins.remove", "files.completeUploadExternal", "assistant.threads.setStatus", "assistant.threads.setTitle"]) {
    assert.equal(isSlackWrite(method), true, method);
  }
  for (const method of ["conversations.history", "conversations.replies", "conversations.info", "conversations.open", "users.info", "users.list", "files.info", "reactions.get", "pins.list", "chat.getPermalink", "auth.test", ""]) {
    assert.equal(isSlackWrite(method), false, method);
  }
  // Each a method's name or the start of some, in a method's own letters: what agents/claude.ts joins with commas for
  // its hook's command line, and its shell reads as one word.
  for (const w of SLACK_WRITES) assert.match(w, /^[a-z][A-Za-z]*(\.[A-Za-z]+)*\.?$/, w);
});
