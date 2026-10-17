// A scripted `claude -p --input-format stream-json --output-format stream-json` for the dev environment's station
// (bin/claude runs it; anything else goes to station/test/fake). What a person writes stays what they wrote: the scene
// it plays is the first of $DEVENV_SCENES (scenes.json, written by seed.ts) whose `match` is in the message, and with
// none, a short reply. A scene's steps:
//   {think}            a thought (in the transcript, so the execution history has it)
//   {tool, input, output, ok?}   a call and its result: streamed as the real CLI streams them and kept in the transcript
//   {post: {...}}      chat_post to the message's thread (text, kind, done, need, card, files) through the station's MCP
//   {state: {...}}     chat_state;  {job: {...}} job_start
//   {hold: {tool, input}}  a call left running: the turn stays busy until interrupted or moved to the background
// The transcript goes where Claude Code keeps it: $CLAUDE_CONFIG_DIR/projects/<cwd, encoded>/<session id>.jsonl.
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const args = process.argv.slice(2);
const flag = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const sessionId = flag("--session-id") || flag("--resume") || "none";
const say = (frame) => fs.writeSync(1, JSON.stringify(frame) + "\n");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let n = 0;
const stream = (event) => say({ type: "stream_event", event, parent_tool_use_id: null, session_id: sessionId, uuid: `u${++n}` });

const home = process.env.CLAUDE_CONFIG_DIR || path.join(process.env.HOME || "/tmp", ".claude");
const projects = path.join(home, "projects", process.cwd().replace(/[^A-Za-z0-9]/g, "-"));
const transcript = path.join(projects, `${sessionId}.jsonl`);
let parent = null;
function record(type, content) {
  fs.mkdirSync(projects, { recursive: true });
  const uuid = `${sessionId}-${++n}`;
  fs.appendFileSync(transcript, JSON.stringify({ type, uuid, parentUuid: parent, sessionId, cwd: process.cwd(), timestamp: new Date().toISOString(), message: { role: type, content } }) + "\n");
  parent = uuid;
}

let mcp = null;
try {
  mcp = JSON.parse(flag("--mcp-config")).mcpServers.stillfail.url;
} catch {}
let calls = 0;
async function tool(name, args) {
  const r = await fetch(mcp, { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${process.env.STILLFAIL_MCP_TOKEN}` }, body: JSON.stringify({ jsonrpc: "2.0", id: ++calls, method: "tools/call", params: { name, arguments: args } }) }).then((r) => r.json());
  const said = r.result?.content?.[0]?.text ?? JSON.stringify(r.error ?? r);
  // What went wrong, for the seeder to say (seed.ts fails on it).
  if ((r.error || r.result?.isError) && process.env.DEVENV_SCENES) fs.appendFileSync(`${process.env.DEVENV_SCENES}.errors`, `${name}: ${said}\n`);
  return said;
}

let interrupted = false;
let backgrounded = false;
let wake = () => {};
const pause = () => new Promise((r) => (wake = r));

/// A call as the CLI streams it, then its result (none while `running`).
async function call(name, input, output, ok = true) {
  const id = `toolu_${sessionId.slice(0, 8)}_${++n}`;
  const mid = `msg_${n}`;
  stream({ type: "message_start", message: { id: mid, role: "assistant", content: [] } });
  stream({ type: "content_block_start", index: 0, content_block: { type: "tool_use", id, name, input: {} } });
  stream({ type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: JSON.stringify(input) } });
  stream({ type: "content_block_stop", index: 0 });
  stream({ type: "message_stop" });
  const use = [{ type: "tool_use", id, name, input }];
  say({ type: "assistant", message: { id: mid, role: "assistant", content: use }, session_id: sessionId });
  record("assistant", use);
  if (output === undefined) return id;
  const result = [{ type: "tool_result", tool_use_id: id, content: output, is_error: !ok }];
  say({ type: "user", message: { role: "user", content: result }, session_id: sessionId });
  record("user", result);
  return id;
}

function text(t) {
  const mid = `msg_${++n}`;
  stream({ type: "message_start", message: { id: mid, role: "assistant", content: [] } });
  stream({ type: "content_block_start", index: 0, content_block: { type: "text", text: "" } });
  stream({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: t } });
  stream({ type: "content_block_stop", index: 0 });
  stream({ type: "message_stop" });
  say({ type: "assistant", message: { id: mid, role: "assistant", content: [{ type: "text", text: t }] }, session_id: sessionId });
  record("assistant", [{ type: "text", text: t }]);
}

function scenes() {
  try {
    return JSON.parse(fs.readFileSync(process.env.DEVENV_SCENES, "utf8"));
  } catch {
    return [];
  }
}

async function turn(message) {
  interrupted = false;
  backgrounded = false;
  say({ type: "system", subtype: "init", session_id: sessionId, model: flag("--model") || "default", tools: [], mcp_servers: [] });
  say({ type: "system", subtype: "status", status: "requesting", session_id: sessionId });
  const to = /thread="([^"]+)"/.exec(message)?.[1] ?? "";
  const body = /<message[^>]*>\n([\s\S]*?)\n<\/message>/.exec(message)?.[1] ?? message;
  record("user", [{ type: "text", text: body }]);
  const scene = scenes().find((s) => s.match && body.includes(s.match));
  const steps = scene?.steps ?? [{ post: { text: "收到", kind: "all_done", done: "answered the message" } }];
  for (const step of steps) {
    if (interrupted) break;
    if (step.think) {
      record("assistant", [{ type: "thinking", thinking: step.think, signature: "" }]);
    } else if (step.tool) {
      await call(step.tool, step.input ?? {}, step.output ?? "", step.ok !== false);
    } else if (step.post) {
      const input = { to, ...step.post };
      const id = await call("mcp__stillfail__chat_post", input);
      const answer = await tool("chat_post", input);
      const result = [{ type: "tool_result", tool_use_id: id, content: answer }];
      say({ type: "user", message: { role: "user", content: result }, session_id: sessionId });
      record("user", result);
    } else if (step.state) {
      const id = await call("mcp__stillfail__chat_state", step.state);
      record("user", [{ type: "tool_result", tool_use_id: id, content: await tool("chat_state", step.state) }]);
    } else if (step.job) {
      const id = await call("mcp__stillfail__job_start", step.job);
      record("user", [{ type: "tool_result", tool_use_id: id, content: await tool("job_start", step.job) }]);
    } else if (step.hold) {
      const id = await call(step.hold.tool ?? "Bash", step.hold.input ?? { command: "sleep 3600" });
      while (!interrupted && !backgrounded) await pause();
      const result = [{ type: "tool_result", tool_use_id: id, content: backgrounded ? "moved to background" : "interrupted", is_error: !backgrounded }];
      say({ type: "user", message: { role: "user", content: result }, session_id: sessionId });
      record("user", result);
    }
    if (step.wait) await sleep(step.wait);
  }
  if (interrupted) say({ type: "result", subtype: "error_during_execution", is_error: true, duration_ms: 1, num_turns: 1, session_id: sessionId, result: "" });
  else {
    if (scene?.say) text(scene.say);
    say({ type: "result", subtype: "success", is_error: false, duration_ms: 1, num_turns: 1, session_id: sessionId, result: scene?.say ?? "" });
  }
  // The seeder waits for this line before its next message.
  if (process.env.DEVENV_SCENES) fs.appendFileSync(`${process.env.DEVENV_SCENES}.done`, `${sessionId}\n`);
}

let busy = Promise.resolve();
const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  if (msg.type === "control_request") {
    const subtype = msg.request?.subtype;
    if (subtype === "interrupt") interrupted = true;
    if (subtype === "background_tasks") backgrounded = true;
    wake();
    say({ type: "control_response", response: { subtype: "success", request_id: msg.request_id } });
    return;
  }
  if (msg.type !== "user") return;
  const content = msg.message?.content;
  const said = typeof content === "string" ? content : (content ?? []).map((c) => c.text ?? "").join("");
  busy = busy.then(() => turn(said)).catch((e) => fs.writeSync(2, `agent: ${e?.stack ?? e}\n`));
});
rl.on("close", () => process.exit(0));
