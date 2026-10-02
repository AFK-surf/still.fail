// A fake `codex app-server --listen stdio://`: JSON-RPC lines as the real one speaks them (initialize, thread/start,
// thread/resume, turn/start, turn/steer, turn/interrupt, thread/unsubscribe, model/list, account/rateLimits/read) and the
// notifications of a turn (turn/started, item/*, turn/completed), driven by what the input says:
//   say:<text>    a reply                       fail:auth|rate|model   turn/completed failed with codexErrorInfo
//   slow:<n>      n deltas, 100 ms apart         cmd                    a command with output, then a reply
//   again         a reply, then a turn of its own                      ask   asks the client something first
//   exit          exits 4 in the middle of the turn
// FAKE_DUMP: its argv and env are appended there as a JSON line, and every line of stdin to FAKE_DUMP.stdin.
import fs from "node:fs";
import readline from "node:readline";

const dump = process.env.FAKE_DUMP;
if (dump) fs.appendFileSync(dump, JSON.stringify({ argv: process.argv.slice(2), env: process.env, pid: process.pid }) + "\n");

const say = (msg) => fs.writeSync(1, JSON.stringify(msg) + "\n");
const notify = (method, params) => say({ method, params });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let initialized = false;
let n = 0;
/// threadId → { turn: id | null, interrupted, steers }
const threads = new Map();
const answers = new Map();

function thread(id) {
  if (!threads.has(id)) threads.set(id, { turn: null, interrupted: false, steers: [] });
  return threads.get(id);
}

async function agentMessage(threadId, t, texts, gap) {
  const itemId = `it-${++n}`;
  notify("item/started", { threadId, turnId: t.turn, item: { type: "agentMessage", id: itemId, text: "" } });
  for (const text of texts) {
    if (t.interrupted) break;
    notify("item/agentMessage/delta", { threadId, turnId: t.turn, itemId, delta: text });
    for (const s of t.steers.splice(0)) notify("item/agentMessage/delta", { threadId, turnId: t.turn, itemId, delta: `steer:${s}` });
    if (gap) await sleep(gap);
  }
  notify("item/completed", { threadId, turnId: t.turn, item: { type: "agentMessage", id: itemId } });
}

function completed(threadId, t, status, error) {
  const turn = { id: t.turn, status, items: [] };
  if (error) turn.error = error;
  t.turn = null;
  notify("turn/completed", { threadId, turn });
}

async function runTurn(threadId, text) {
  const t = thread(threadId);
  t.interrupted = false;
  notify("turn/started", { threadId, turn: { id: t.turn, status: "inProgress", items: [] } });
  if (text === "fail:auth") return completed(threadId, t, "failed", { message: "unauthorized: token expired", codexErrorInfo: "unauthorized" });
  if (text === "fail:rate") return completed(threadId, t, "failed", { message: "usage limit reached", codexErrorInfo: { usageLimitExceeded: {} } });
  if (text === "fail:model") return completed(threadId, t, "failed", { message: "model not supported", codexErrorInfo: { badRequest: null } });
  if (text === "exit") {
    await agentMessage(threadId, t, ["partial"], 0);
    process.exit(4);
  }
  if (text === "ask") {
    say({ id: "srv-1", method: "item/commandExecution/requestApproval", params: { threadId, turnId: t.turn, itemId: "x" } });
    for (let i = 0; i < 50 && !answers.has("srv-1"); i++) await sleep(20);
  }
  if (text === "cmd") {
    const itemId = `it-${++n}`;
    notify("item/started", { threadId, turnId: t.turn, item: { type: "commandExecution", id: itemId, command: "ls" } });
    notify("item/commandExecution/outputDelta", { threadId, turnId: t.turn, itemId, delta: "a\n" });
    notify("item/completed", { threadId, turnId: t.turn, item: { type: "commandExecution", id: itemId } });
  }
  if (text.startsWith("slow:")) {
    const count = Number(text.slice(5));
    await agentMessage(threadId, t, Array.from({ length: count }, (_, i) => `d${i} `), 100);
  } else {
    await agentMessage(threadId, t, [text.startsWith("say:") ? text.slice(4) : text], 0);
  }
  completed(threadId, t, t.interrupted ? "interrupted" : "completed");
  if (text === "again") {
    await sleep(50);
    t.turn = `tu-${++n}`;
    runTurn(threadId, "auto");
  }
}

function handle(msg) {
  const { id, method, params } = msg;
  const reply = (result) => say({ id, result });
  const fail = (message) => say({ id, error: { code: -32600, message } });
  if (method === undefined) {
    answers.set(id, msg);
    return;
  }
  if (method === "initialize") {
    if (initialized) return fail("Already initialized");
    initialized = true;
    return reply({ userAgent: "fake-codex/0" });
  }
  if (method === "initialized") return;
  if (!initialized) return fail("Not initialized");
  if (method === "thread/start") {
    const threadId = `th-${++n}`;
    thread(threadId);
    return reply({ thread: { id: threadId } });
  }
  if (method === "thread/resume") {
    thread(params.threadId);
    return reply({ thread: { id: params.threadId } });
  }
  if (method === "turn/start") {
    const t = thread(params.threadId);
    if (t.turn) return fail("a turn is running");
    t.turn = `tu-${++n}`;
    reply({ turn: { id: t.turn, status: "inProgress", items: [] } });
    runTurn(params.threadId, params.input.map((i) => i.text).join(""));
    return;
  }
  if (method === "turn/steer") {
    const t = thread(params.threadId);
    if (!t.turn || t.turn !== params.expectedTurnId) return fail("no active turn to steer");
    t.steers.push(params.input.map((i) => i.text).join(""));
    return reply({ turnId: t.turn });
  }
  if (method === "turn/interrupt") {
    const t = thread(params.threadId);
    if (t.turn === params.turnId) t.interrupted = true;
    return reply({});
  }
  if (method === "thread/unsubscribe") return reply({ status: "unsubscribed" });
  if (method === "account/rateLimits/read") return reply({ rateLimits: { primary: { usedPercent: 5 } } });
  if (method === "model/list") {
    if (!params.cursor)
      return reply({
        data: [
          { id: "gpt-a", supportedReasoningEfforts: [{ reasoningEffort: "low" }, { reasoningEffort: "high" }, { reasoningEffort: "low" }] },
          { id: "secret", hidden: true },
        ],
        nextCursor: "p2",
      });
    return reply({ data: [{ model: "legacy" }, { id: "gpt-a" }], nextCursor: null });
  }
  return say({ id, error: { code: -32601, message: `unknown method ${method}` } });
}

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (dump) fs.appendFileSync(dump + ".stdin", line + "\n");
  try {
    handle(JSON.parse(line));
  } catch {}
});
rl.on("close", () => process.exit(0));
