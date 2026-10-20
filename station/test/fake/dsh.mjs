// A fake `dsh --profile acp --patch <file>` with the station's driver plugin in it (src/agents/dsh-bridge.mjs): its
// lines as the plugin writes them (answers; `event` with turn/start, turn/end, tool/call, tool/result; `stream` with the
// model's frames), keeping the session's transcript where the patch says, as dsh writes it. A prompt's text says what the
// turn does:
//   say:<text>    a thought, then a reply                fail:auth|rate|model   the turn ends in dsh's error
//   cmd           a bash call with its output, then a reply                      refuse  the prompt is refused
//   tools         a call to the station's tools that fails as unreachable
//   hold          a reply, then waits: a steer is answered in the same turn (`steer:<text>`, then it ends), a cancel
//                 ends it aborted                                                exit  exits 4 in the middle of the turn
//   gate:<name>   a reply's first part; the rest once FAKE_DUMP.<name>.a (a fifo) is written, then FAKE_DUMP.<name>.said
//                 made; the end once FAKE_DUMP.<name>.b is (what the test lets happen when, not a time)
// A steer with no turn running starts one (as dsh does). FAKE_DUMP: its argv, env and patch are appended there as a JSON
// line (a value dsh evaluates as "!!js <its code>"), and every line of stdin to FAKE_DUMP.stdin. Its version (`--version`) is FAKE_DUMP.version's, else 0.2.0.
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const dump = process.env.FAKE_DUMP;
const version = dump && fs.existsSync(`${dump}.version`) ? fs.readFileSync(`${dump}.version`, "utf8").trim() : "0.2.0";
if (process.argv[2] === "--version") {
  console.log(version);
  process.exit(0);
}
// JSON but for the one value dsh evaluates (`!!js "…"`): kept as its text.
const patchText = fs.readFileSync(process.argv[process.argv.indexOf("--patch") + 1], "utf8");
const patch = JSON.parse(patchText.replace(/!!js ("(?:[^"\\]|\\.)*")/g, (_, js) => JSON.stringify(`!!js ${JSON.parse(js)}`)));
if (dump) fs.appendFileSync(dump, JSON.stringify({ argv: process.argv.slice(2), env: process.env, patch, cwd: process.cwd(), pid: process.pid }) + "\n");
const root = patch.find((p) => p.id === "session-persistence-jsonl").config.root;

const say = (msg) => fs.writeSync(1, JSON.stringify(msg) + "\n");
const event = (type, data) => say({ ev: "event", type, data });
const gate = async (at) => {
  while (process.platform === "win32" && !fs.existsSync(at)) await new Promise((r) => setTimeout(r, 10));
  return fs.promises.readFile(at);
};

let n = 0;
let s = null;
/// The running turn: { steers, wake, cancelled }, or null.
let running = null;
const record = (type, data) => fs.appendFileSync(s.file, JSON.stringify({ type, seq: s.seq++, time: 1_800_000_000_000 + s.seq, data }) + "\n");

function open(id, cwd) {
  const dir = path.join(root, `--${cwd.replace(/[^A-Za-z0-9]/g, "-")}--`, id);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "session.v4.jsonl");
  if (!fs.existsSync(file)) fs.writeFileSync(file, JSON.stringify({ type: "session", version: 4, id, cwd }) + "\n");
  s = { id, file, seq: 0 };
}

/// One attempt of the model: a thought (when given) and a reply, streamed block by block, then committed.
function reply(words, thought) {
  const attemptId = `${s.id}:${++n}`;
  let index = 0;
  const frame = (f) => say({ ev: "stream", frame: { attemptId, ...f } });
  frame({ type: "start" });
  const block = (blockType, text) => {
    const i = index++;
    frame({ type: "chunk", index: i, chunk: { type: "block-start", index: i, blockType } });
    frame({ type: "chunk", index: i, chunk: { type: blockType === "text" ? "text-delta" : "reasoning-delta", index: i, text } });
    frame({ type: "chunk", index: i, chunk: { type: "block-end", index: i, block: { type: blockType, text } } });
  };
  if (thought) block("reasoning", thought);
  block("text", words);
  frame({ type: "end", outcome: { kind: "committed", eventType: "assistant/message" } });
  const content = [...(thought ? [{ type: "reasoning", text: thought }] : []), { type: "text", text: words }];
  record("assistant/message", { message: { role: "assistant", content, source: { kind: "model", model: "m1" }, id: `m${n}` }, usage: { inputTokens: 10, outputTokens: 2, cacheReadTokens: 5 } });
}

function call(name, args, output, isError) {
  const attemptId = `${s.id}:${++n}`;
  const callId = `call_${n}`;
  say({ ev: "stream", frame: { attemptId, type: "start" } });
  say({ ev: "stream", frame: { attemptId, type: "chunk", chunk: { type: "block-start", index: 0, blockType: "tool-call" } } });
  say({ ev: "stream", frame: { attemptId, type: "chunk", chunk: { type: "tool-call-delta", index: 0, id: callId, name, argumentsDelta: args } } });
  say({ ev: "stream", frame: { attemptId, type: "chunk", chunk: { type: "block-end", index: 0 } } });
  say({ ev: "stream", frame: { attemptId, type: "end", outcome: { kind: "committed" } } });
  record("assistant/message", { message: { role: "assistant", content: [{ type: "tool-call", id: callId, name, arguments: args }], id: `m${n}` } });
  event("tool/call", { callId, name, arguments: args });
  const result = { message: { role: "tool", toolCallId: callId, content: [{ type: "text", text: output }], isError } };
  event("tool/result", result);
  record("tool/result", result);
}

async function turn(text) {
  const t = { steers: [], wake: null, cancelled: false };
  running = t;
  event("turn/start", { turn: ++n });
  record("user/message", { content: [{ type: "text", text }], source: { kind: "user" }, role: "user", id: `u${n}` });
  record("user/message", { content: [{ type: "text", text: "Current runtime context." }], source: { kind: "runtime-context" }, role: "user", id: `u${n}` });
  const end = (reason) => {
    running = null;
    event("turn/end", { turn: n, reason });
  };
  const failed = { "fail:auth": ["AUTH", '401: {"message":"Upstream request failed: Invalid credential"}'], "fail:rate": ["RATE_LIMIT", "429: rate limit reached"], "fail:model": ["UNKNOWN_MODEL", "no such model"] }[text];
  if (failed) return end({ kind: "error", error: { code: failed[0], message: failed[1] } });
  if (text === "exit") {
    reply("partial");
    process.exit(4);
  }
  if (text === "cmd") call("bash", '{"command":"ls"}', "a\n", false);
  if (text === "tools") call("mcp__stillfail__chat_post", '{"text":"hi"}', "fetch failed: ECONNREFUSED 127.0.0.1:4750", true);
  if (text === "hold") {
    reply("holding");
    while (!t.cancelled && t.steers.length === 0) await new Promise((r) => (t.wake = r));
    if (t.cancelled) return end({ kind: "aborted", reason: { kind: "user" } });
    reply(`steer:${t.steers.join(" ")}`);
    return end({ kind: "completed" });
  }
  if (text.startsWith("gate:")) {
    const at = `${dump}.${text.slice(5)}`;
    reply("first ");
    await gate(`${at}.a`);
    reply("second");
    fs.writeFileSync(`${at}.said`, "");
    await gate(`${at}.b`);
    return end({ kind: "completed" });
  }
  reply(text.startsWith("say:") ? text.slice(4) : text, "thinking it over");
  end({ kind: "completed" });
}

async function handle(msg) {
  const { id, op } = msg;
  const answer = (more = {}) => say({ id, ...more });
  if (op === "open") {
    if (msg.resume) {
      const dir = fs.readdirSync(root).map((d) => path.join(root, d, msg.resume)).find((d) => fs.existsSync(d));
      if (!dir) return answer({ error: `session ${msg.resume} not found` });
      open(msg.resume, msg.cwd);
    } else {
      open(`00000000-0000-4000-8000-${String(process.pid % 1e6).padStart(6, "0")}${String(++n).padStart(6, "0")}`, msg.cwd);
    }
    return answer({ session: s.id });
  }
  if (s === null) return answer({ error: "no session is open" });
  if (op === "prompt") {
    if (msg.text === "refuse") return answer({ error: "the prompt is refused" });
    answer();
    if (running) running.steers.push(msg.text);
    else void turn(msg.text);
    return;
  }
  if (op === "steer") {
    answer();
    if (running) {
      running.steers.push(msg.text);
      running.wake?.();
    } else void turn(msg.text);
    return;
  }
  if (op === "cancel") {
    answer();
    if (running) {
      running.cancelled = true;
      running.wake?.();
    }
    return;
  }
  answer({ error: `unknown op ${op}` });
}

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (dump) fs.appendFileSync(dump + ".stdin", line + "\n");
  try {
    void handle(JSON.parse(line));
  } catch {}
});
rl.on("close", () => process.exit(0));
