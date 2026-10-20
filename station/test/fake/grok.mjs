// A fake `grok agent … stdio`: ACP JSON-RPC lines as Grok Build speaks them (initialize, session/new, session/load,
// session/prompt answered with its usage, session/cancel, _x.ai/interject; session/update notifications streaming in
// chunks; session/request_permission asked of the client), keeping each session's chat_history.jsonl in
// $GROK_HOME/sessions/<cwd, escaped>/<id>/ as Grok Build writes it. `grok models` says it is signed in when
// $GROK_HOME/auth.json is there, and `grok login --device-auth` prints a link and a code and signs in once
// FAKE_DUMP.approve is there. A prompt's text says what the turn does:
//   say:<text>    a thought, then a reply in two chunks     fail:auth|rate|model   the prompt answered with an error
//   cmd           a terminal call with its output, then a reply                    ask   asks the client's permission first
//   tools         a call to the station's tools that fails as unreachable
//   post          a post through the station's tools, reached with use_tool as Grok Build reaches an MCP server's
//   sub           a subagent spawned by a call: its own session's steps, then its end
//   hold          waits until cancelled, or until a message is interjected (then says it heard it)
//   exit          exits 4 in the middle of the turn
// FAKE_DUMP: its argv and env are appended there as a JSON line, and every line of stdin to FAKE_DUMP.stdin. The version
// it says it is (`--version`) is FAKE_DUMP.version's when there is one, else 1.0.62.
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const dump = process.env.FAKE_DUMP;
const home = process.env.GROK_HOME ?? path.join(process.env.HOME ?? ".", ".grok");
const version = dump && fs.existsSync(`${dump}.version`) ? fs.readFileSync(`${dump}.version`, "utf8").trim() : "1.0.62";
const args = process.argv.slice(2);
if (args[0] === "--version") {
  console.log(`grok ${version} (fake)`);
  process.exit(0);
}
if (dump) fs.appendFileSync(dump, JSON.stringify({ argv: args, env: process.env, cwd: process.cwd(), pid: process.pid }) + "\n");
if (args[0] === "models") {
  if (!fs.existsSync(path.join(home, "auth.json"))) {
    console.log("You are not authenticated.\n\nDefault model: grok-4.6\n\nAvailable models:");
    process.exit(0);
  }
  console.log("You are logged in with grok.com.\n\nDefault model: grok-4.7\n\nAvailable models:\n  * grok-4.7 (default)\n  - grok-4.6");
  process.exit(0);
}
if (args[0] === "login") {
  console.log("\nTo sign in, open this URL in your browser:\n\n  https://accounts.x.ai/oauth2/device?user_code=ABCD-1234\n\nConfirm this code in your browser:\n\n  ABCD-1234\n\nWaiting for authorization...");
  const until = () => {
    if (dump && fs.existsSync(`${dump}.approve`)) {
      fs.mkdirSync(home, { recursive: true });
      fs.writeFileSync(path.join(home, "auth.json"), JSON.stringify({ "https://auth.x.ai::client": { key: "tok", auth_mode: "oidc", email: "grok@example.com" } }));
      console.log("Signed in.");
      process.exit(0);
    }
    setTimeout(until, 20);
  };
  until();
} else {
  agent();
}

function agent() {
  const say = (msg) => fs.writeSync(1, JSON.stringify({ jsonrpc: "2.0", ...msg }) + "\n");
  const update = (sessionId, u) => say({ method: "session/update", params: { sessionId, update: u } });
  let n = 0;
  /// sessionId → { file, cancel, heard }
  const sessions = new Map();
  const answers = new Map();
  const waits = new Map();

  function open(id, cwd) {
    const dir = path.join(home, "sessions", encodeURIComponent(cwd), id);
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, "chat_history.jsonl");
    if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify({ type: "system", content: "You are Grok." }) + "\n");
    const s = { file, id, cancel: null, heard: null, prompts: 0 };
    sessions.set(id, s);
    return s;
  }
  const record = (s, line) => fs.appendFileSync(s.file, JSON.stringify(line) + "\n");
  const usage = (promptId) => ({ sessionId: "", promptId, requestId: promptId, modelId: "grok-4.7", totalTokens: 1234, usage: { inputTokens: 100, outputTokens: 7, cachedReadTokens: 60, cacheCreationTokens: 10, totalTokens: 107, modelCalls: 2 } });
  const models = { currentModelId: "grok-4.7", availableModels: [{ modelId: "grok-4.7", _meta: { totalContextTokens: 256000 } }, { modelId: "grok-4.6", _meta: { totalContextTokens: 500000 } }] };
  const notify = (sessionId, u) => say({ method: "_x.ai/session_notification", params: { sessionId, update: u } });

  async function turn(s, text) {
    record(s, { type: "user", content: [{ type: "text", text: "<system-reminder>skills</system-reminder>" }], synthetic_reason: "system_reminder" });
    record(s, { type: "user", content: [{ type: "text", text: `<user_query>\n${text}\n</user_query>` }], prompt_index: s.prompts++ });
    const reply = (words, thought) => {
      if (thought) {
        update(s.id, { sessionUpdate: "agent_thought_chunk", content: { type: "text", text: thought } });
        record(s, { type: "reasoning", id: `rs_${++n}`, summary: [{ type: "summary_text", text: thought }], encrypted_content: "x" });
      }
      const half = Math.ceil(words.length / 2);
      update(s.id, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: words.slice(0, half) } });
      update(s.id, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: words.slice(half) } });
      record(s, { type: "assistant", content: words, model_id: "grok-4.7-build" });
    };
    if (text === "fail:auth") throw new Error("Unauthorized: the access token could not be validated (401)");
    if (text === "fail:rate") throw new Error("429 Too Many Requests: rate limit reached");
    if (text === "fail:model") throw new Error("model grok-9 not found");
    if (text === "exit") {
      reply("partial");
      process.exit(4);
    }
    if (text === "ask") {
      say({ id: "perm-1", method: "session/request_permission", params: { sessionId: s.id, toolCall: { toolCallId: "c0" }, options: [{ optionId: "reject-once", kind: "reject_once", name: "No" }, { optionId: "allow-once", kind: "allow_once", name: "Yes" }] } });
      if (!answers.has("perm-1")) await new Promise((r) => waits.set("perm-1", r));
    }
    if (text === "cmd") {
      const callId = `call-${++n}`;
      update(s.id, { sessionUpdate: "tool_call", toolCallId: callId, title: "run_terminal_command", rawInput: { command: "ls" }, _meta: { "x.ai/tool": { name: "run_terminal_command" } } });
      record(s, { type: "assistant", content: "Listing.", tool_calls: [{ id: callId, name: "run_terminal_command", arguments: '{"command":"ls"}' }], model_id: "grok-4.7-build" });
      update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "in_progress", content: [{ type: "content", content: { type: "text", text: "" } }] });
      update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "completed", content: [{ type: "content", content: { type: "text", text: "a\n" } }] });
      record(s, { type: "tool_result", tool_call_id: callId, content: "exit: 0\na\n" });
    }
    if (text === "tools") {
      const callId = `call-${++n}`;
      update(s.id, { sessionUpdate: "tool_call", toolCallId: callId, title: "stillfail__chat_post", rawInput: { text: "hi" }, _meta: { "x.ai/tool": { name: "stillfail__chat_post" } } });
      update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "failed", content: [{ type: "content", content: { type: "text", text: "fetch failed: ECONNREFUSED 127.0.0.1:4750" } }] });
    }
    if (text === "post") {
      const callId = `call-${++n}`;
      const input = { tool_name: "stillfail__chat_post", tool_input: { text: "posted words" } };
      update(s.id, { sessionUpdate: "tool_call", toolCallId: callId, title: "use_tool", rawInput: input, _meta: { "x.ai/tool": { name: "use_tool" } } });
      record(s, { type: "assistant", content: "", tool_calls: [{ id: callId, name: "use_tool", arguments: JSON.stringify(input) }], model_id: "grok-4.7-build" });
      update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "completed", content: [{ type: "content", content: { type: "text", text: "Posted." } }] });
      record(s, { type: "tool_result", tool_call_id: callId, content: "Posted." });
    }
    if (text === "sub") {
      const callId = `call-${++n}`;
      const child = `child-${++n}`;
      update(s.id, { sessionUpdate: "tool_call", toolCallId: callId, title: "spawn_subagent", rawInput: { description: "look around" }, _meta: { "x.ai/tool": { name: "spawn_subagent" } } });
      notify(s.id, { sessionUpdate: "subagent_spawned", subagent_id: child, parent_session_id: s.id, child_session_id: child, subagent_type: "explore", description: "look around" });
      update(child, { sessionUpdate: "tool_call", toolCallId: "c1", title: "read_file", rawInput: { path: "a" }, _meta: { "x.ai/tool": { name: "read_file" } } });
      update(child, { sessionUpdate: "tool_call_update", toolCallId: "c1", status: "completed", content: [{ type: "content", content: { type: "text", text: "A" } }] });
      update(child, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "found A" } });
      notify(s.id, { sessionUpdate: "subagent_finished", subagent_id: child, child_session_id: child, status: "completed", tool_calls: 1, turns: 1 });
      update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "completed", content: [{ type: "content", content: { type: "text", text: "found A" } }] });
    }
    if (text === "hold") {
      reply("holding");
      const why = await new Promise((r) => {
        s.cancel = () => r("cancelled");
        s.heard = (said) => r(said);
      });
      s.cancel = null;
      s.heard = null;
      if (why === "cancelled") return "cancelled";
      record(s, { type: "user", content: [{ type: "text", text: why }], synthetic_reason: "interjection" });
      reply(`heard: ${why}`);
      return "end_turn";
    }
    reply(text.startsWith("say:") ? text.slice(4) : text, "thinking it over");
    return "end_turn";
  }

  async function handle(msg) {
    const { id, method, params } = msg;
    const reply = (result) => say({ id, result });
    const fail = (message) => say({ id, error: { code: -32603, message: `Internal error: ${message}` } });
    if (method === undefined) {
      answers.set(id, msg);
      waits.get(id)?.();
      return;
    }
    if (method === "initialize") return reply({ protocolVersion: 1, agentCapabilities: { loadSession: true, mcpCapabilities: { http: true, sse: true } }, _meta: { agentVersion: version } });
    if (method === "session/new") {
      const s = open(`01a151b0-0000-7000-8000-${String(process.pid % 1e6).padStart(6, "0")}${String(++n).padStart(6, "0")}`, params.cwd);
      return reply({ sessionId: s.id, models });
    }
    if (method === "session/load") {
      const root = path.join(home, "sessions");
      const dir = (fs.existsSync(root) ? fs.readdirSync(root) : []).map((d) => path.join(root, d, params.sessionId)).find((d) => fs.existsSync(d));
      if (!dir) return fail(`Session ${params.sessionId} not found`);
      open(params.sessionId, params.cwd);
      return reply({ models });
    }
    if (method === "session/prompt") {
      const s = sessions.get(params.sessionId);
      const promptId = `p${++n}`;
      try {
        const stopReason = await turn(s, params.prompt.map((p) => p.text).join(""));
        return reply({ stopReason, _meta: { ...usage(promptId), sessionId: s.id } });
      } catch (e) {
        return fail(e.message);
      }
    }
    if (method === "session/set_config_option") return reply({ configOptions: [] });
    if (method === "session/cancel") {
      sessions.get(params.sessionId)?.cancel?.();
      return;
    }
    if (method === "_x.ai/interject") {
      const s = sessions.get(params.sessionId);
      reply({ status: "queued" });
      s?.heard?.(params.text);
      return;
    }
    return say({ id, error: { code: -32601, message: "Method not found" } });
  }

  const rl = readline.createInterface({ input: process.stdin });
  rl.on("line", (line) => {
    if (dump) fs.appendFileSync(dump + ".stdin", line + "\n");
    try {
      void handle(JSON.parse(line));
    } catch {}
  });
  rl.on("close", () => process.exit(0));
}
