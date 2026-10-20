// The test station's claude for the app's flows: ember's fake claude (station/test/fake/claude.mjs, the next one on
// PATH) for everything it knows, and beside it what the decisions and the execution history need, which it does not
// do. A message the station hands it with one of these in it is answered here (the rest go to ember's fake as they
// come):
//   card:<question>|<label>|<label>*|<label>!   chat_post with an options card ending the turn need_human: the
//                                               question, then the options (`*` recommended, `!` action close)
//   text-card:<question>|<placeholder>          the same with a text card
//   md:<words>                                  chat_post all done: <words>, then a table, a TypeScript block with a long
//                                               line and a bare address (…/e2e/<the words' last word>)
//   steps:<words>                               a turn with tool calls in its transcript (a command and its output, an
//                                               edit), then chat_post <words> ending it all_done
//   serve:<name>|<port>|<words>                 job_start a web service <name> on <port> (a page of two, served by
//                                               python's http.server from the session's workspace), then chat_post
//                                               <words> all_done
// What it writes of a turn goes to its transcript as the real claude's does (<config>/projects/<dir>/<session>.jsonl),
// which is what the station reads an agent's execution history from.
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import readline from "node:readline";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const sessionId = flag("--session-id") || flag("--resume") || "none";
const say = (frame) => fs.writeSync(1, JSON.stringify(frame) + "\n");

// ember's fake: the first claude.mjs on PATH that is not this one
const theirs = (process.env.PATH || "")
  .split(path.delimiter)
  .map((d) => path.join(d, "claude.mjs"))
  .find((f) => path.dirname(f) !== here && fs.existsSync(f));
const child = theirs ? spawn(process.execPath, [theirs, ...args], { stdio: ["pipe", "pipe", "inherit"], env: process.env }) : null;
if (child) {
  // its frames passed on whole, a line at a time (ours are written between its lines, never inside one)
  readline.createInterface({ input: child.stdout }).on("line", (line) => fs.writeSync(1, line + "\n"));
  child.on("exit", (code) => process.exit(code ?? 0));
}

// the transcript, as the real claude keeps it
const config = process.env.CLAUDE_CONFIG_DIR || path.join(process.env.HOME || ".", ".claude");
const transcript = path.join(config, "projects", "e2e", `${sessionId}.jsonl`);
let entry = 0;
function record(type, content) {
  fs.mkdirSync(path.dirname(transcript), { recursive: true });
  const line = { type, uuid: `e2e-${process.pid}-${++entry}`, sessionId, timestamp: new Date().toISOString(), message: { role: type, content } };
  fs.appendFileSync(transcript, JSON.stringify(line) + "\n");
}

let n = 0;
function message(text) {
  const id = `msg_e2e_${++n}`;
  const event = (e) => say({ type: "stream_event", event: e, parent_tool_use_id: null, session_id: sessionId, uuid: `e${n}-${Math.random()}` });
  event({ type: "message_start", message: { id, role: "assistant", content: [] } });
  event({ type: "content_block_start", index: 0, content_block: { type: "text", text: "" } });
  event({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text } });
  event({ type: "content_block_stop", index: 0 });
  event({ type: "message_stop" });
  say({ type: "assistant", message: { id, role: "assistant", content: [{ type: "text", text }] }, session_id: sessionId });
}

async function tool(name, args) {
  const server = JSON.parse(flag("--mcp-config")).mcpServers.stillfail;
  const call = (id, method, params) =>
    fetch(server.url, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${process.env.STILLFAIL_MCP_TOKEN}` },
      body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
    }).then((r) => r.json());
  await call(1, "initialize", { protocolVersion: "2025-06-18" });
  const answer = await call(2, "tools/call", { name, arguments: args });
  return answer.result?.content?.[0]?.text ?? JSON.stringify(answer.error ?? answer);
}

const post = (to, args) => tool("chat_post", { to, ...args });

// the service's two pages, written where it runs (every word made up)
const PAGE_A = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>端到端测试服务</title><link rel="stylesheet" href="style.css"></head><body><h1>端到端测试服务</h1>
<p id="n">脚本还没有运行</p><p><a href="b.html">去第二页</a></p>
<script>fetch('data.json').then(r=>r.json()).then(d=>{document.getElementById('n').textContent='脚本已运行：'+d.n})</script></body></html>`;
const PAGE_B = `<!doctype html><html><head><meta charset="utf-8"><title>第二页</title><link rel="stylesheet" href="style.css"></head>
<body><h1>这是第二页</h1></body></html>`;
const STYLE = "body{margin:0;padding:24px;font-family:system-ui,sans-serif;background:#fbe6dc;color:#24272b}h1{color:#b9471f}";

async function turn(text) {
  say({ type: "system", subtype: "init", session_id: sessionId, model: flag("--model") || "default", tools: [], mcp_servers: [] });
  record("user", text);
  const to = /thread="([^"]+)"/.exec(text)?.[1] ?? "";
  const line = (key) => text.slice(text.indexOf(key) + key.length).split("\n")[0];
  let said;
  if (text.includes("text-card:")) {
    const [question, placeholder] = line("text-card:").split("|");
    said = await post(to, { text: question, kind: "need_human", need: question, card: { type: "text", placeholder: placeholder ?? "" } });
  } else if (text.includes("card:")) {
    const [question, ...labels] = line("card:").split("|");
    const options = labels.map((l) => {
      const o = { label: l.replace(/[*!]+$/, "") };
      if (/\*/.test(l.slice(o.label.length))) o.recommended = true;
      if (/!/.test(l.slice(o.label.length))) o.action = "close";
      return o;
    });
    said = await post(to, { text: question, kind: "need_human", need: question, card: { type: "options", options } });
  } else if (/(^|\s)md:/.test(text)) {
    // Markdown as an agent writes it: a table, code with a line too long for the message, a bare address
    const words = line("md:");
    const md = [
      words, "",
      "| 页面 | 状态 | 耗时 |", "|:--|:-:|--:|", "| 首页 | 完成 | 1.2 s |", "| 聊天页的列表和输入框 | 进行中 | 3.4 s |", "",
      "```ts",
      "export function placeRows(rows: Row[], from: number): number {",
      "  const visible = rows.filter((r) => r.top >= from && r.top < from + window.innerHeight * 2) // only the rows near the screen",
      "  return visible.length",
      "}",
      "```", "",
      `详见 https://example.com/e2e/${encodeURIComponent(words.split(" ").pop() ?? "x")}`,
    ].join("\n");
    said = await post(to, { text: md, kind: "all_done", done: "answered the question that was asked" });
  } else if (text.includes("serve:")) {
    const [name, port, words] = line("serve:").split("|");
    // a port another process holds (another run's service on the same machine) is said, not served over: the page
    // would be that other server's
    const taken = await new Promise((done) => {
      const probe = net.createServer().once("error", () => done(true));
      probe.listen(Number(port), "127.0.0.1", () => probe.close(() => done(false)));
    });
    if (taken) {
      process.stderr.write(`fake claude: serve: port ${port} is taken by another process\n`);
      said = await post(to, { text: `serve: port ${port} is taken by another process`, kind: "all_done", done: "the port was taken" });
      message(said);
      say({ type: "result", subtype: "success", is_error: false, duration_ms: 1, num_turns: 1, session_id: sessionId, result: said });
      return;
    }
    const dir = path.join(process.cwd(), `e2e-site-${port}`);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "index.html"), PAGE_A);
    fs.writeFileSync(path.join(dir, "b.html"), PAGE_B);
    fs.writeFileSync(path.join(dir, "style.css"), STYLE);
    fs.writeFileSync(path.join(dir, "data.json"), JSON.stringify({ n: 42 }));
    const started = await tool("job_start", { name, port: Number(port), command: `cd '${dir}' && exec python3 -m http.server ${port} --bind 127.0.0.1` });
    record("assistant", [{ type: "text", text: started }]);
    said = await post(to, { text: words ?? name, kind: "all_done", done: "started the service that was asked for" });
  } else {
    // steps: a command and what it printed, an edit, then the answer
    const words = line("steps:");
    const call = (id, name, input) => record("assistant", [{ type: "tool_use", id, name, input }]);
    const result = (id, content) => record("user", [{ type: "tool_result", tool_use_id: id, content }]);
    call("toolu_e2e_1", "Bash", { command: "ls docs", description: "列出 docs 目录" });
    result("toolu_e2e_1", "stillfail-port.md\nstillfail-android-map.md");
    call("toolu_e2e_2", "Edit", { file_path: "/tmp/e2e/notes.md", old_string: "旧的一行", new_string: "新的一行" });
    result("toolu_e2e_2", "The file /tmp/e2e/notes.md has been updated.");
    record("assistant", [{ type: "text", text: "看过了，改好了。" }]);
    said = await post(to, { text: words, kind: "all_done", done: "answered the question that was asked" });
  }
  message(said);
  say({ type: "result", subtype: "success", is_error: false, duration_ms: 1, num_turns: 1, session_id: sessionId, result: said });
}

const ours = (text) => /(^|\s)(card:|text-card:|steps:|serve:|md:)/.test(text);
readline.createInterface({ input: process.stdin }).on("line", (line) => {
  let msg = null;
  try {
    msg = JSON.parse(line);
  } catch {}
  const text = msg?.type === "user" ? (msg.message?.content ?? []).map((c) => c.text ?? "").join("") : "";
  if (msg?.type === "user" && ours(text)) {
    turn(text).catch((e) => {
      fs.writeSync(2, `e2e fake claude: ${e?.stack ?? e}\n`);
      say({ type: "result", subtype: "error_during_execution", is_error: true, session_id: sessionId, result: String(e) });
    });
    return;
  }
  if (child) child.stdin.write(line + "\n");
});
process.stdin.on("end", () => (child ? child.stdin.end() : process.exit(0)));
