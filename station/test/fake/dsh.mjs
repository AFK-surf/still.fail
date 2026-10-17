// A fake `dsh --profile acp --patch <file>`: ACP JSON-RPC lines as DeepSeek Harness speaks them (initialize,
// session/new, session/resume, session/prompt, session/cancel; session/update notifications; session/request_permission
// asked of the client), keeping each session's transcript where its patch says, as dsh writes it. A prompt's text says
// what the turn does:
//   say:<text>    a reply (and a thought before it)       fail:auth|rate|model   the prompt answered with an error
//   cmd           a bash call with its output, then a reply                       ask   asks the client's permission first
//   tools         a call to the station's tools that fails as unreachable
//   hold          waits until cancelled                                            exit  exits 4 in the middle of the turn
//   gate:<name>   a reply's first part; the rest once FAKE_DUMP.<name>.a (a fifo) is written, then FAKE_DUMP.<name>.said
//                 made; the answer once FAKE_DUMP.<name>.b is (what the test lets happen when, not a time)
// FAKE_DUMP: its argv, env and patch are appended there as a JSON line, and every line of stdin to FAKE_DUMP.stdin. The
// version it says it is (`--version`) is FAKE_DUMP.version's when there is one, else 0.2.0.
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const dump = process.env.FAKE_DUMP;
const version = dump && fs.existsSync(`${dump}.version`) ? fs.readFileSync(`${dump}.version`, "utf8").trim() : "0.2.0";
if (process.argv[2] === "--version") {
  console.log(version);
  process.exit(0);
}
const patchFile = process.argv[process.argv.indexOf("--patch") + 1];
const patch = JSON.parse(fs.readFileSync(patchFile, "utf8"));
if (dump) fs.appendFileSync(dump, JSON.stringify({ argv: process.argv.slice(2), env: process.env, patch, cwd: process.cwd(), pid: process.pid }) + "\n");
const root = patch.find((p) => p.id === "session-persistence-jsonl").config.root;

const say = (msg) => fs.writeSync(1, JSON.stringify({ jsonrpc: "2.0", ...msg }) + "\n");
const update = (sessionId, u) => say({ method: "session/update", params: { sessionId, update: u } });
const gate = async (at) => {
  while (process.platform === "win32" && !fs.existsSync(at)) await new Promise((r) => setTimeout(r, 10));
  return fs.promises.readFile(at);
};

let n = 0;
/// sessionId → { file, seq, cancel: () => void | null }
const sessions = new Map();
const answers = new Map();
const heard = new Map();

function open(id, cwd) {
  const dir = path.join(root, `--${cwd.replace(/[^A-Za-z0-9]/g, "-")}--`, id);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "session.v4.jsonl");
  if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify({ type: "session", version: 4, id, cwd }) + "\n");
  const s = { file, seq: 0, cancel: null, id };
  sessions.set(id, s);
  return s;
}
const record = (s, type, data) => fs.appendFileSync(s.file, JSON.stringify({ type, seq: s.seq++, time: 1_800_000_000_000 + s.seq, data }) + "\n");

async function turn(s, text) {
  record(s, "user/message", { content: [{ type: "text", text }], source: { kind: "user" }, role: "user", id: `u${++n}` });
  record(s, "user/message", { content: [{ type: "text", text: "Current runtime context." }], source: { kind: "runtime-context" }, role: "user", id: `u${++n}` });
  const reply = (words, thought) => {
    const id = `m${++n}`;
    if (thought) update(s.id, { sessionUpdate: "agent_thought_chunk", messageId: id, content: { type: "text", text: thought } });
    update(s.id, { sessionUpdate: "agent_message_chunk", messageId: id, content: { type: "text", text: words } });
    const content = [...(thought ? [{ type: "reasoning", text: thought }] : []), { type: "text", text: words }];
    record(s, "assistant/message", { message: { role: "assistant", content, source: { kind: "model", model: "m1" }, id }, usage: { inputTokens: 10, outputTokens: 2, cacheReadTokens: 5 } });
  };
  if (text === "fail:auth") throw new Error('turn failed: 401: {"message":"Upstream request failed: Invalid credential"}');
  if (text === "fail:rate") throw new Error("turn failed: 429: rate limit reached");
  if (text === "fail:model") throw new Error("turn failed: UNKNOWN_MODEL: no such model");
  if (text === "exit") {
    reply("partial");
    process.exit(4);
  }
  if (text === "ask") {
    say({ id: "perm-1", method: "session/request_permission", params: { sessionId: s.id, toolCall: { toolCallId: "c0" }, options: [{ optionId: "no", kind: "reject_once", name: "No" }, { optionId: "yes", kind: "allow_once", name: "Yes" }] } });
    if (!answers.has("perm-1")) await new Promise((r) => heard.set("perm-1", r));
  }
  if (text === "cmd") {
    const callId = `call_${++n}`;
    update(s.id, { sessionUpdate: "tool_call", toolCallId: callId, title: "bash", kind: "other", status: "in_progress", rawInput: { command: "ls" } });
    record(s, "assistant/message", { message: { role: "assistant", content: [{ type: "tool-call", id: callId, name: "bash", arguments: '{"command":"ls"}' }], id: `m${++n}` } });
    update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "completed", content: [{ type: "content", content: { type: "text", text: "a\n" } }] });
    record(s, "tool/result", { message: { role: "tool", toolCallId: callId, content: [{ type: "text", text: "a\n" }], isError: false } });
  }
  if (text === "tools") {
    const callId = `call_${++n}`;
    update(s.id, { sessionUpdate: "tool_call", toolCallId: callId, title: "mcp__stillfail__chat_post", kind: "other", status: "in_progress", rawInput: { text: "hi" } });
    update(s.id, { sessionUpdate: "tool_call_update", toolCallId: callId, status: "failed", content: [{ type: "content", content: { type: "text", text: "fetch failed: ECONNREFUSED 127.0.0.1:4750" } }] });
  }
  if (text === "hold") {
    reply("holding");
    await new Promise((r) => (s.cancel = r));
    return "cancelled";
  }
  if (text.startsWith("gate:")) {
    const at = `${dump}.${text.slice(5)}`;
    reply("first ");
    await gate(`${at}.a`);
    reply("second");
    fs.writeFileSync(`${at}.said`, "");
    await gate(`${at}.b`);
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
    heard.get(id)?.();
    return;
  }
  if (method === "initialize") return reply({ protocolVersion: 1, agentCapabilities: { mcpCapabilities: { http: true }, sessionCapabilities: { resume: {} } } });
  if (method === "session/new") {
    const s = open(`00000000-0000-4000-8000-${String(process.pid % 1e6).padStart(6, "0")}${String(++n).padStart(6, "0")}`, params.cwd);
    return reply({ sessionId: s.id, configOptions: [] });
  }
  if (method === "session/resume") {
    const dir = fs.readdirSync(root).map((d) => path.join(root, d, params.sessionId)).find((d) => fs.existsSync(d));
    if (!dir) return fail(`unknown session ${params.sessionId}`);
    open(params.sessionId, params.cwd);
    return reply({ configOptions: [] });
  }
  if (method === "session/prompt") {
    const s = sessions.get(params.sessionId);
    try {
      const stopReason = await turn(s, params.prompt.map((p) => p.text).join(""));
      return reply({ stopReason });
    } catch (e) {
      return fail(e.message);
    }
  }
  if (method === "session/cancel") {
    const s = sessions.get(params.sessionId);
    s?.cancel?.();
    return;
  }
  return say({ id, error: { code: -32601, message: `Method not found: ${method}` } });
}

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (dump) fs.appendFileSync(dump + ".stdin", line + "\n");
  try {
    void handle(JSON.parse(line));
  } catch {}
});
rl.on("close", () => process.exit(0));
