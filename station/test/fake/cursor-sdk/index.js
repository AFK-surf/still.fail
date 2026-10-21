// A fake @cursor/sdk for the station's Cursor driver (src/agents/cursor-bridge.mjs, loaded by STILLFAIL_CURSOR_SDK):
// Agent.create and Agent.resume (an agent kept as a file under the SDK's home, os.homedir()/.cursor), agent.send (a run
// whose messages stream as the SDK's do), run.steer, run.cancel, run.wait. A prompt's text says what the run does:
//   say:<text>      a thought (in pieces), then a reply (in pieces)
//   cmd             a shell call with its output, then a reply
//   tools           a call to the station's tools that fails as unreachable
//   hold            a reply, then waits: a steer is answered in the same run (`steer:<text>`), a cancel ends it cancelled
//   gate:<name>     a reply's first part; the rest once FAKE_DUMP.<name>.a (a fifo) is written, then FAKE_DUMP.<name>.said
//                   made; the end once FAKE_DUMP.<name>.b is
//   error:<code>    the run ends in error with that code    refuse  agent.send throws, unauthenticated
//   exit            a reply, then the process exits 4
// FAKE_DUMP: each create, resume and send is appended there as a JSON line (with the environment and os.homedir()).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";

const dump = process.env.FAKE_DUMP;
const log = (line) => dump && fs.appendFileSync(dump, JSON.stringify(line) + "\n");
const kept = () => path.join(os.homedir(), ".cursor", "fake-agents");
const gate = async (at) => {
  while (process.platform === "win32" && !fs.existsSync(at)) await new Promise((r) => setTimeout(r, 10));
  return fs.promises.readFile(at);
};
const fail = (message, code) => Object.assign(new Error(message), { code });
const USAGE = { inputTokens: 10, outputTokens: 5, cacheReadTokens: 3, cacheWriteTokens: 0, totalTokens: 18 };

let runs = 0;

class FakeRun {
  constructor(agent, text, model) {
    this.id = `run-${++runs}`;
    this.agentId = agent.agentId;
    this.model = model;
    this.messages = [];
    this.finished = null;
    this.wake = null;
    this.steered = null;
    this.cancelled = false;
    this.ended = new Promise((resolve) => (this.end = resolve));
    void this.script(text);
  }

  push(message) {
    this.messages.push({ agent_id: this.agentId, run_id: this.id, ...message });
    this.wake?.();
  }

  say(text) {
    for (const piece of [text.slice(0, Math.ceil(text.length / 2)), text.slice(Math.ceil(text.length / 2))]) if (piece !== "") this.push({ type: "assistant", message: { role: "assistant", content: [{ type: "text", text: piece }] } });
  }

  finish(status, error) {
    if (this.finished !== null) return;
    if (status === "finished") this.push({ type: "usage", usage: USAGE });
    this.finished = { id: this.id, status, ...(error ? { error } : {}), ...(status === "finished" ? { usage: USAGE } : {}), model: this.model };
    this.wake?.();
    this.end();
  }

  async script(text) {
    await null;
    this.push({ type: "status", status: "RUNNING" });
    if (text.startsWith("say:")) {
      this.push({ type: "thinking", text: "thinking " });
      this.push({ type: "thinking", text: "it over" });
      this.push({ type: "thinking", text: "", thinking_duration_ms: 5 });
      this.say(text.slice(4));
      return this.finish("finished");
    }
    if (text === "cmd") {
      this.push({ type: "tool_call", call_id: "call-1", name: "shell", status: "running", args: { command: "ls" } });
      this.push({ type: "tool_call", call_id: "call-1", name: "shell", status: "completed", args: { command: "ls" }, result: { status: "success", value: { exitCode: 0, stdout: "a\nb\n", stderr: "" } } });
      this.say("listed");
      return this.finish("finished");
    }
    if (text === "tools") {
      const args = { providerIdentifier: "stillfail", toolName: "chat_post", args: { to: "x", text: "hi" } };
      this.push({ type: "tool_call", call_id: "call-2", name: "mcp", status: "running", args });
      this.push({ type: "tool_call", call_id: "call-2", name: "mcp", status: "error", args, result: { status: "error", error: "fetch failed: connect ECONNREFUSED 127.0.0.1:4750" } });
      return this.finish("finished");
    }
    if (text === "hold") {
      this.say("waiting");
      const steer = await new Promise((resolve) => (this.steered = resolve));
      if (steer === null) return this.finish("cancelled");
      this.say(`steer:${steer}`);
      return this.finish("finished");
    }
    if (text.startsWith("gate:")) {
      const at = `${dump}.${text.slice(5)}`;
      this.say("first");
      await gate(`${at}.a`);
      this.say("second");
      fs.writeFileSync(`${at}.said`, "");
      await gate(`${at}.b`);
      return this.finish("finished");
    }
    if (text.startsWith("error:")) return this.finish("error", { message: `the model failed (${text.slice(6)})`, code: text.slice(6) });
    if (text === "exit") {
      this.say("bye");
      await new Promise((r) => setTimeout(r, 50));
      process.exit(4);
    }
    this.say(text);
    this.finish("finished");
  }

  async *stream() {
    let i = 0;
    for (;;) {
      while (i < this.messages.length) yield this.messages[i++];
      if (this.finished !== null) return;
      await new Promise((resolve) => (this.wake = resolve));
      this.wake = null;
    }
  }

  async wait() {
    await this.ended;
    return this.finished;
  }

  async steer(text) {
    if (this.finished !== null || this.steered === null) return "revert_to_followup";
    this.push({ type: "user", message: { role: "user", content: [{ type: "text", text }] } });
    const steered = this.steered;
    this.steered = null;
    steered(text);
    return "complete_delivered";
  }

  async cancel() {
    if (this.steered !== null) {
      const steered = this.steered;
      this.steered = null;
      steered(null);
    } else this.finish("cancelled");
  }
}

class FakeAgent {
  constructor(agentId, options) {
    this.agentId = agentId;
    this.options = options;
  }

  async send(text, options) {
    const model = options?.model ?? this.options.model;
    log({ send: text, model });
    if (!process.env.CURSOR_API_KEY || text === "refuse") throw fail("Invalid User API Key", "unauthenticated");
    return new FakeRun(this, text, model);
  }

  close() {}
}

export class Agent {
  static async create(options) {
    const agentId = `agent-${randomUUID()}`;
    fs.mkdirSync(kept(), { recursive: true });
    fs.writeFileSync(path.join(kept(), agentId), JSON.stringify(options));
    log({ create: options, agentId, home: os.homedir(), env: process.env, cwd: process.cwd() });
    return new FakeAgent(agentId, options);
  }

  static async resume(agentId, options) {
    if (!fs.existsSync(path.join(kept(), agentId))) throw fail(`no agent ${agentId}`, "not_found");
    log({ resume: agentId, options, home: os.homedir() });
    return new FakeAgent(agentId, options);
  }
}
