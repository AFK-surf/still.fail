// A fake `claude -p --input-format stream-json --output-format stream-json`: frames as the real CLI writes them
// (system/init, status, stream_event partial messages, assistant/user messages, result), driven by what the prompt says:
//   say:<text>    a reply                       fail:auth|rate|model   a result with is_error
//   slow:<n>      n deltas, 100 ms apart         retry401               api_retry 401 frames until interrupted
//   tool          a Bash call that waits until background_tasks (or interrupt)
//   again         a reply, then a turn of its own (no prompt of ours)
//   exit          exits 3 in the middle of the turn
// Input while busy is read into the turn (a delta "steer:<text>"); "queue:<text>" becomes a turn after it.
// FAKE_DUMP: its argv and env are appended there as a JSON line, and every line of stdin to FAKE_DUMP.stdin.
import fs from "node:fs";
import readline from "node:readline";

const dump = process.env.FAKE_DUMP;
if (dump) fs.appendFileSync(dump, JSON.stringify({ argv: process.argv.slice(2), env: process.env, pid: process.pid }) + "\n");
const args = process.argv.slice(2);
const flag = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const sessionId = flag("--session-id") || flag("--resume") || "none";

const say = (frame) => fs.writeSync(1, JSON.stringify(frame) + "\n");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let busy = false;
let interrupted = false;
let backgrounded = false;
let steers = [];
const queued = [];
let n = 0;

function stream(event) {
  say({ type: "stream_event", event, parent_tool_use_id: null, session_id: sessionId, uuid: `u${++n}` });
}

async function message(texts, gap) {
  const id = `msg_${++n}`;
  stream({ type: "message_start", message: { id, role: "assistant", content: [] } });
  stream({ type: "content_block_start", index: 0, content_block: { type: "text", text: "" } });
  let all = "";
  for (const t of texts) {
    if (interrupted) break;
    stream({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: t } });
    all += t;
    for (const s of steers.splice(0)) {
      stream({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: `steer:${s}` } });
      all += `steer:${s}`;
    }
    if (gap) await sleep(gap);
  }
  stream({ type: "content_block_stop", index: 0 });
  stream({ type: "message_stop" });
  say({ type: "assistant", message: { id, role: "assistant", content: [{ type: "text", text: all }] }, session_id: sessionId });
  return all;
}

function result(fields) {
  say({ type: "result", subtype: "success", is_error: false, duration_ms: 1, num_turns: 1, session_id: sessionId, ...fields });
}

async function turn(text) {
  busy = true;
  interrupted = false;
  backgrounded = false;
  say({ type: "system", subtype: "init", session_id: sessionId, model: flag("--model") || "default", tools: [], mcp_servers: [] });
  say({ type: "system", subtype: "status", status: "requesting", session_id: sessionId });
  if (text === "fail:auth") result({ is_error: true, result: "API Error: 401 invalid x-api-key" });
  else if (text === "fail:rate") result({ is_error: true, result: "You've hit your weekly limit · resets Oct 8" });
  else if (text === "fail:model") result({ is_error: true, result: "prompt is too long" });
  else if (text === "retry401") {
    for (let attempt = 1; !interrupted && attempt < 200; attempt++) {
      say({ type: "system", subtype: "api_retry", attempt, retry_delay_ms: 100, error_status: 401, error: "invalid token", session_id: sessionId });
      await sleep(100);
    }
    result({ subtype: "error_during_execution", is_error: true, result: "" });
  } else if (text === "exit") {
    await message(["partial"], 0);
    process.exit(3);
  } else if (text === "tool") {
    const id = `msg_${++n}`;
    stream({ type: "message_start", message: { id } });
    stream({ type: "content_block_start", index: 0, content_block: { type: "tool_use", id: "call_1", name: "Bash", input: {} } });
    stream({ type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: '{"command":' } });
    stream({ type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: '"sleep 60"}' } });
    stream({ type: "content_block_stop", index: 0 });
    stream({ type: "message_stop" });
    for (let i = 0; i < 100 && !backgrounded && !interrupted; i++) await sleep(100);
    say({ type: "user", message: { role: "user", content: [{ type: "tool_result", tool_use_id: "call_1", content: backgrounded ? "moved to background" : "interrupted" }] } });
    if (interrupted) result({ subtype: "error_during_execution", is_error: true, result: "" });
    else result({ result: await message(["done"], 0) });
  } else if (text.startsWith("slow:")) {
    const count = Number(text.slice(5));
    const all = await message(Array.from({ length: count }, (_, i) => `d${i} `), 100);
    if (interrupted) result({ subtype: "error_during_execution", is_error: true, result: "" });
    else result({ result: all });
  } else {
    result({ result: await message([text.startsWith("say:") ? text.slice(4) : text], 0) });
    if (text === "again") queued.push("auto");
  }
  busy = false;
  const next = queued.shift();
  if (next !== undefined) setTimeout(() => turn(next), 50);
}

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (dump) fs.appendFileSync(dump + ".stdin", line + "\n");
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  if (msg.type === "control_request") {
    const subtype = msg.request && msg.request.subtype;
    if (subtype === "interrupt") interrupted = true;
    if (subtype === "background_tasks") backgrounded = true;
    say({ type: "control_response", response: { subtype: "success", request_id: msg.request_id } });
    return;
  }
  if (msg.type !== "user") return;
  const text = msg.message.content.map((c) => c.text).join("");
  if (!busy) turn(text);
  else if (text.startsWith("queue:")) queued.push(text.slice(6));
  else steers.push(text);
});
rl.on("close", () => process.exit(0));
