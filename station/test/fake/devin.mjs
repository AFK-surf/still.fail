// A fake `devin --config <file> acp [--model <variant>]`: ACP JSON-RPC lines as the Devin CLI 3000.11 speaks them
// (initialize, authenticate, session/new and session/load with their config options, session/set_config_option,
// session/prompt answered when the turn ends, session/cancel; session/update notifications, usage_update said twice;
// session/request_permission asked of the client). Each session is kept in $DEVIN_SESSIONS_DIR/<id>.json, its past said
// again as updates by session/load before it is answered. A prompt given while a turn runs goes into it and is answered
// with it. Without `authenticate` (nor WINDSURF_API_KEY) a prompt fails as the real one does.
// `devin auth status` says it is signed in when $XDG_DATA_HOME/devin/credentials.toml is there; `devin auth login
// --force-manual-token-flow` needs a terminal: prints the page's link (an OSC 8 link, as Devin prints it), reads the code
// in raw mode up to Enter, then writes the credentials (the code "bad" is refused). `devin models list --format json`
// lists the families. A prompt's text says what the turn does:
//   say:<text>  a thought, then a reply in two chunks          fail:auth|acu|quota|model   the prompt answered with an error
//   work        a thought and words, a command (exec), a post through the station's tools (chat_post), a reply
//   tools       a call to the station's tools failing as its server unreachable
//   ask         asks the client's permission, then something it has no answer for
//   hold        waits until cancelled, or until a message is put in (then says it heard it; both prompts answered)
//   late        waits for a message, then ends the turn without it and takes it as a turn of its own
//   exit        exits 4 in the middle of the turn
// FAKE_DUMP: its argv, env and --config file are appended there as a JSON line, every line of stdin to FAKE_DUMP.stdin
// and every line it says to FAKE_DUMP.out. Its version (`--version`) is FAKE_DUMP.version's when there is one, else 3000.11.92.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

const dump = process.env.FAKE_DUMP;
const version = dump && fs.existsSync(`${dump}.version`) ? fs.readFileSync(`${dump}.version`, "utf8").trim() : "3000.11.92";
const args = process.argv.slice(2);
const data = process.env.XDG_DATA_HOME ?? path.join(os.homedir(), ".local", "share");
const credentials = path.join(data, "devin", "credentials.toml");
/// The sign-in page's link, as Devin makes it (its state and challenge fixed here).
const LOGIN_URL = "https://app.devin.ai/auth/cli/continue?state=6f1d2c3b-9a8e-4f70-b1c2-d3e4f5a6b7c8&prompt=select_account&code_challenge=q2W8x_Lm-3kZpRt7Yv0bNcJ4hUeSfAgD1iO5lK9wQyE&code_challenge_method=S256&cli_pkce_marker=1";
const FAMILIES = {
  families: [
    { family_label: "SWE-2", family_uid: "swe-2", slug: "swe-2", aliases: ["swe"], variants: [{ model_uid: "swe-2-high", label: "SWE-2 High" }, { model_uid: "swe-2-medium" }, { model_uid: "swe-2-max" }, { model_uid: "swe-2-medium-lightning" }] },
    { family_label: "Claude Opus 5.5", slug: "claude-opus-5.5", variants: [{ model_uid: "claude-opus-5-5-medium" }, { model_uid: "claude-opus-5-5-low" }, { model_uid: "claude-opus-5-5-high-fast" }] },
    { family_label: "Kimi K2.6", slug: "kimi-k2.6", variants: [{ model_uid: "kimi-k2-6" }] },
    { family_label: "GLM 5.2", slug: "glm-5.2", variants: [{ model_uid: "glm-5-2" }, { model_uid: "glm-5-2-max" }, { model_uid: "glm-5-2-1m" }] },
  ],
};
/// The `model` config option's values.
const MODELS = ["adaptive", "swe-2-high", "swe-2-medium", "swe-2-max", "claude-opus-5-5-medium", "claude-opus-5-5-low", "kimi-k2-6", "glm-5-2", "glm-5-2-max", "glm-5-2-1m"];

if (args[0] === "--version") {
  console.log(`devin ${version}`);
  process.exit(0);
}
const flag = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
if (dump) {
  const config = flag("--config");
  fs.appendFileSync(dump, JSON.stringify({ argv: args, env: process.env, cwd: process.cwd(), pid: process.pid, config: config && fs.existsSync(config) ? fs.readFileSync(config, "utf8") : null }) + "\n");
}
if (args[0] === "auth" && args[1] === "status") {
  if (!fs.existsSync(credentials)) {
    console.log(`Not logged in.\n  Credentials path: ${credentials}\nRun \`devin auth login\` to authenticate.`);
    process.exit(1);
  }
  console.log(`Logged in (via Devin).\n\nCredentials:\n  File:              ${credentials}\n  API server:        https://server.codeium.com\n  Devin webapp:      https://app.devin.ai\n  Devin API:         https://api.devin.ai\n\nUser:\n  Name:              Someone\n  Email:             someone@example.com\n  User ID:           user-0123456789abcdef`);
  process.exit(0);
} else if (args[0] === "auth" && args[1] === "login") {
  login();
} else if (args[0] === "models" && args[1] === "list") {
  console.log(JSON.stringify(FAMILIES));
  process.exit(0);
} else if (args[0] === "update") {
  console.log("Already up to date.");
  process.exit(0);
} else if (args.includes("acp")) {
  agent();
} else {
  console.error(`unknown command: ${args.join(" ")}`);
  process.exit(2);
}

function login() {
  if (!process.stdin.isTTY) {
    console.error("Error: Failed to read code - user canceled");
    process.exit(1);
  }
  process.stdout.write(`Visit \u001b]8;;${LOGIN_URL}\u001b\\${LOGIN_URL}\u001b]8;;\u001b\\ to sign in, then copy the code and paste it below.\n\n Code:\n ❭ Paste the code from the sign-in page\n ↵ submit · esc cancel\n`);
  process.stdin.setRawMode(true);
  let typed = "";
  process.stdin.on("data", (chunk) => {
    typed += chunk.toString("utf8");
    const enter = typed.search(/[\r\n]/);
    if (enter < 0) return;
    const code = typed.slice(0, enter).trim();
    if (code === "bad") {
      process.stdout.write("✗ Invalid code\n");
      process.exit(1);
    }
    fs.mkdirSync(path.dirname(credentials), { recursive: true });
    fs.writeFileSync(credentials, `windsurf_api_key = "devin-${code}"\napi_server_url = "https://server.codeium.com"\ndevin_webapp_host = "https://app.devin.ai"\ndevin_api_url = "https://api.devin.ai"\n`);
    process.stdout.write("✓ Account verified\n");
    process.exit(0);
  });
}

function agent() {
  const say = (msg) => {
    const line = JSON.stringify({ jsonrpc: "2.0", ...msg }) + "\n";
    if (dump) fs.appendFileSync(dump + ".out", line);
    fs.writeSync(1, line);
  };
  const store = process.env.DEVIN_SESSIONS_DIR ?? path.join(data, "devin", "sessions");
  let authed = (process.env.WINDSURF_API_KEY ?? "") !== "";
  let n = 0;
  const startModel = flag("--model") ?? "swe-2-high";
  /// sessionId → { id, file, mode, model, level, running, steers, next, cancel, wake, call, titled }
  const sessions = new Map();
  const answers = new Map();
  const waits = new Map();

  const configOptions = (s) => [
    { id: "mode", name: "Mode", type: "select", currentValue: s.mode, options: ["normal", "accept-edits", "plan", "bypass"].map((value) => ({ value, name: value })) },
    { id: "model", name: "Model", type: "select", currentValue: s.model, options: MODELS.map((value) => ({ value, name: value })) },
    { id: "thought_level", name: "Thinking", type: "select", currentValue: s.level, options: levels(s.model).map((value) => ({ value, name: value })) },
    { id: "speed", name: "Speed", type: "select", currentValue: "standard", options: [{ value: "standard" }, { value: "fast" }] },
  ];
  /// The thinking levels of the current model's family.
  const levels = (model) => (model.startsWith("swe-2") ? ["medium", "high", "max"] : model.startsWith("claude-opus-5-5") ? ["low", "medium"] : model.startsWith("glm-5-2") ? ["max"] : []);
  const modes = (s) => ({ currentModeId: s.mode, availableModes: [{ id: "normal" }, { id: "accept-edits" }, { id: "plan" }, { id: "bypass" }] });
  const words = ["foul", "calm", "bold", "pale", "wide", "keen"];
  const things = ["taxi", "river", "lamp", "fern", "moon", "reef"];

  function open(id) {
    fs.mkdirSync(store, { recursive: true });
    const file = path.join(store, `${id}.json`);
    if (!fs.existsSync(file)) fs.writeFileSync(file, "[]");
    const s = { id, file, mode: "accept-edits", model: startModel, level: "medium", running: false, steers: [], next: null, cancel: null, wake: null, call: 0, titled: false };
    sessions.set(id, s);
    return s;
  }
  /// Kept for session/load to say again.
  const keep = (s, u) => fs.writeFileSync(s.file, JSON.stringify([...JSON.parse(fs.readFileSync(s.file, "utf8")), u]));
  /// An update of the session's, said and (unless `kept` is false) kept.
  function update(s, u, kept = true) {
    say({ method: "session/update", params: { sessionId: s.id, update: u } });
    if (kept) keep(s, u);
  }
  const notify = (s, method, params = {}) => say({ method, params: { sessionId: s.id, ...params } });
  /// A model call's counts, said once and again as its agent's: its input with what the cache read.
  function usage(s) {
    const c = s.call++;
    const [input, output] = [1000 + 100 * c, 50 + c];
    const meta = { "cognition.ai/inputTokens": input, "cognition.ai/outputTokens": output, "cognition.ai/cachedReadTokens": 400 };
    update(s, { sessionUpdate: "usage_update", used: input + output, size: 262000, _meta: meta }, false);
    update(s, { sessionUpdate: "usage_update", used: input + output, size: 262000, _meta: { ...meta, "cognition.ai/subagent_context": { parentAgentId: "root" } } }, false);
    notify(s, "_cognition.ai/thinking_complete");
  }
  function reply(s, text, thought) {
    if (thought) update(s, { sessionUpdate: "agent_thought_chunk", content: { type: "text", text: thought } });
    const half = Math.ceil(text.length / 2);
    update(s, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: text.slice(0, half) } });
    update(s, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: text.slice(half) } });
    usage(s);
  }
  const textOf = (msg) => (msg.params?.prompt ?? []).map((p) => p.text ?? "").join("");
  const rpcError = (code, message, data) => Object.assign(new Error(message), { rpc: { code, message, ...(data === undefined ? {} : { data }) } });
  /// Until the turn is cancelled or a message is put in it.
  const waitFor = (s) =>
    new Promise((r) => {
      s.cancel = () => r("cancelled");
      s.wake = () => r("steered");
      if (s.steers.length > 0) r("steered");
    }).finally(() => {
      s.cancel = null;
      s.wake = null;
    });

  async function turn(s, text) {
    if (!authed) throw rpcError(-32603, "Internal error", "ACP host has not authenticated: call authenticate first");
    keep(s, { sessionUpdate: "user_message_chunk", content: { type: "text", text } });
    if (!s.titled) {
      s.titled = true;
      update(s, { sessionUpdate: "session_info_update", title: "A session" }, false);
    }
    if (text === "fail:auth") throw rpcError(-32603, "Internal error: 401 Unauthorized: the API key is invalid");
    if (text === "fail:acu") throw rpcError(-32603, "Internal error: Monthly ACU limit reached. Upgrade your plan to keep going.");
    if (text === "fail:quota") throw rpcError(-32603, "Internal error", "Your usage quota has been exhausted");
    if (text === "fail:model") throw rpcError(-32603, "Internal error: model glm-9 is not available");
    if (text === "exit") {
      update(s, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "partial" } });
      process.exit(4);
    }
    if (text === "work") {
      update(s, { sessionUpdate: "agent_thought_chunk", content: { type: "text", text: "thinking it over" } });
      update(s, { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "Running." } });
      const exec = `exec:0#c06b${++n}`;
      update(s, { sessionUpdate: "tool_call", toolCallId: exec, title: "Ran sleep, echo", kind: "execute", status: "pending", rawInput: { command: "sleep 1; echo done" }, _meta: { "cognition.ai/inferenceToolName": "exec" } });
      usage(s);
      for (let i = 0; i < 2; i++) update(s, { sessionUpdate: "tool_call_update", toolCallId: exec, status: "in_progress" });
      update(s, { sessionUpdate: "tool_call_update", toolCallId: exec, status: "completed", content: [{ type: "content", content: { type: "text", text: "done" } }], _meta: { "cognition.ai/inferenceToolName": "exec" } });
      const post = `mcp:1#d17e${++n}`;
      const meta = { "cognition.ai/toolName": "mcp__stillfail__chat_post", "cognition.ai/eventType": "mcp_tool_call", "cognition.ai/inferenceToolName": "mcp__stillfail__chat_post" };
      update(s, { sessionUpdate: "tool_call", toolCallId: post, title: "Calling chat_post from stillfail", kind: "other", status: "pending", rawInput: { to: "here", text: "posted words" }, _meta: meta });
      usage(s);
      update(s, { sessionUpdate: "tool_call_update", toolCallId: post, status: "completed", content: [{ type: "content", content: { type: "text", text: "Posted." } }], _meta: meta });
      reply(s, "done");
      notify(s, "_cognition.ai/turn_stats", { steps: 3 });
      notify(s, "_cognition.ai/agent_stopped");
      return "end_turn";
    }
    if (text === "tools") {
      const post = `mcp:0#e28f${++n}`;
      const meta = { "cognition.ai/toolName": "mcp__stillfail__chat_post", "cognition.ai/eventType": "mcp_tool_call", "cognition.ai/inferenceToolName": "mcp__stillfail__chat_post" };
      update(s, { sessionUpdate: "tool_call", toolCallId: post, title: "Calling chat_post from stillfail", kind: "other", status: "pending", rawInput: { text: "hi" }, _meta: meta });
      usage(s);
      update(s, { sessionUpdate: "tool_call_update", toolCallId: post, status: "failed", content: [{ type: "content", content: { type: "text", text: "Failed to connect to MCP server 'stillfail'. Please try again." } }], _meta: meta });
      reply(s, "could not post");
      return "end_turn";
    }
    if (text === "ask") {
      say({ id: "perm-1", method: "session/request_permission", params: { sessionId: s.id, toolCall: { toolCallId: "exec:0#x" }, options: [{ optionId: "reject-once", kind: "reject_once", name: "No" }, { optionId: "allow-once", kind: "allow_once", name: "Yes" }, { optionId: "allow-always", kind: "allow_always", name: "Always" }] } });
      if (!answers.has("perm-1")) await new Promise((r) => waits.set("perm-1", r));
      say({ id: "question-1", method: "_cognition.ai/ask_user_question", params: { sessionId: s.id, question: "Which one?" } });
      if (!answers.has("question-1")) await new Promise((r) => waits.set("question-1", r));
      reply(s, "allowed");
      return "end_turn";
    }
    if (text === "hold") {
      reply(s, "holding");
      if ((await waitFor(s)) === "cancelled") return "cancelled";
      // Read at its next step, as the model's own: the turn goes on with it.
      const heard = s.steers.map(textOf).join(" ");
      keep(s, { sessionUpdate: "user_message_chunk", content: { type: "text", text: heard } });
      reply(s, `heard: ${heard}`);
      return "end_turn";
    }
    if (text === "late") {
      reply(s, "first");
      if ((await waitFor(s)) === "cancelled") return "cancelled";
      // Come as the turn was ending: a turn of its own after this one.
      s.next = s.steers.shift();
      return "end_turn";
    }
    if (text.startsWith("late:")) {
      reply(s, `late ${text.slice(5)}`);
      return "end_turn";
    }
    reply(s, text.startsWith("say:") ? text.slice(4) : text, "thinking it over");
    return "end_turn";
  }

  /// A prompt as a turn: answered when it ends, with the messages put in it.
  async function prompted(s, msg) {
    s.running = true;
    s.call = 0;
    let answer;
    try {
      const stopReason = await turn(s, textOf(msg));
      answer = { result: { stopReason, usage: { totalTokens: 1450, inputTokens: 1000, outputTokens: 50, cachedReadTokens: 400 }, _meta: { "cognition.ai/userMessageId": `um-${++n}` } } };
    } catch (e) {
      answer = { error: e.rpc ?? { code: -32603, message: `Internal error: ${e.message}` } };
    }
    s.running = false;
    const steers = s.steers.splice(0);
    say({ id: msg.id, ...answer });
    for (const m of steers) say({ id: m.id, ...answer });
    if (s.next) {
      const next = s.next;
      s.next = null;
      // Its text says what it does, as a turn's own: `late:<text>`.
      await prompted(s, { ...next, params: { ...next.params, prompt: [{ type: "text", text: `late:${textOf(next)}` }] } });
    }
  }

  async function handle(msg) {
    const { id, method, params } = msg;
    const reply = (result) => say({ id, result });
    if (method === undefined) {
      answers.set(id, msg);
      waits.get(id)?.();
      return;
    }
    if (method === "initialize") {
      return reply({
        protocolVersion: 1,
        agentCapabilities: { loadSession: true, promptCapabilities: { image: true, embeddedContext: true }, mcpCapabilities: { http: true, sse: false }, sessionCapabilities: { additionalDirectories: {} } },
        authMethods: [{ id: "devin-browser", name: "Devin", description: "Sign in with Devin" }],
        agentInfo: { name: "devin", version },
      });
    }
    if (method === "authenticate") {
      if (params?.methodId !== "devin-browser" || typeof params?._meta?.api_key !== "string") return say({ id, error: { code: -32602, message: "Invalid params" } });
      authed = true;
      return reply({});
    }
    if (method === "session/new" || method === "session/load") {
      let s;
      if (method === "session/new") {
        fs.mkdirSync(store, { recursive: true });
        const k = fs.readdirSync(store).filter((f) => f.endsWith(".json")).length;
        s = open(`${words[k % words.length]}-${things[Math.floor(k / words.length) % things.length]}`);
      } else {
        if (!fs.existsSync(path.join(store, `${params.sessionId}.json`))) return say({ id, error: { code: -32603, message: "Internal error", data: `Session ${params.sessionId} not found` } });
        s = open(params.sessionId);
        // Its past, said again before it is answered.
        for (const u of JSON.parse(fs.readFileSync(s.file, "utf8"))) update(s, u, false);
      }
      update(s, { sessionUpdate: "config_option_update", configOptions: configOptions(s) }, false);
      update(s, { sessionUpdate: "current_mode_update", currentModeId: s.mode }, false);
      update(s, { sessionUpdate: "available_commands_update", availableCommands: [{ name: "usage", description: "Show usage" }] }, false);
      say({ method: "_cognition.ai/mcp/serversChanged", params: { servers: (params.mcpServers ?? []).map((m) => ({ name: m.name, status: "connected" })) } });
      const answer = { modes: modes(s), configOptions: configOptions(s), _meta: {} };
      return reply(method === "session/new" ? { sessionId: s.id, ...answer } : answer);
    }
    if (method === "session/set_config_option") {
      const s = sessions.get(params.sessionId);
      const option = configOptions(s).find((o) => o.id === params.configId);
      if (!option || !option.options.some((o) => o.value === params.value)) return say({ id, error: { code: -32602, message: "Invalid params", data: `Invalid value '${params.value}' for config option '${params.configId}'` } });
      if (params.configId === "mode") {
        s.mode = params.value;
        update(s, { sessionUpdate: "current_mode_update", currentModeId: s.mode }, false);
      }
      if (params.configId === "model") s.model = params.value;
      if (params.configId === "thought_level") s.level = params.value;
      return reply({ configOptions: configOptions(s) });
    }
    if (method === "session/prompt") {
      const s = sessions.get(params.sessionId);
      if (s.running) {
        // Into the running turn: read at its next step, answered with it.
        s.steers.push(msg);
        s.wake?.();
        return;
      }
      return prompted(s, msg);
    }
    if (method === "session/cancel") {
      sessions.get(params.sessionId)?.cancel?.();
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
