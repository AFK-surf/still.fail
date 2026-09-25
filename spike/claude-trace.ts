// Dumps one `claude -p` stream-json run to stdout, for debugging a spike turn.
// Usage: node spike/claude-trace.ts [cwd] "prompt"
import { spawn } from "node:child_process";
import { claudeEnv, MODEL } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const prompt = process.argv[3] ?? "Use your shell tool to run `ls -la`, then reply with only the number of entries it printed.";
const started = Date.now();
const child = spawn("claude", ["-p", prompt, "--dangerously-skip-permissions", "--model", MODEL,
  "--output-format", "stream-json", "--verbose"], { cwd, env: claudeEnv("ember-spike-trace"), stdio: ["ignore", "pipe", "pipe"] });
child.stdout.setEncoding("utf8");
let buffer = "";
child.stdout.on("data", (chunk: string) => {
  buffer += chunk;
  let newline;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, newline);
    buffer = buffer.slice(newline + 1);
    const t = `${((Date.now() - started) / 1000).toFixed(1)}s`;
    try {
      const f = JSON.parse(line);
      const summary = f.type === "assistant"
        ? f.message.content.map((b: any) => `${b.type}:${(b.text ?? b.thinking ?? JSON.stringify(b.input) ?? "").slice(0, 160)}`).join(" | ")
        : f.type === "user" ? JSON.stringify(f.message.content).slice(0, 200)
        : f.type === "result" ? `${f.subtype} is_error=${f.is_error} turns=${f.num_turns} ${String(f.result ?? "").slice(0, 300)}`
        : f.type === "system" ? `${f.subtype} ${f.subtype === "init" ? `tools=${f.tools?.length} model=${f.model}` : JSON.stringify(f).slice(0, 300)}`
        : JSON.stringify(f).slice(0, 300);
      console.log(t, f.type, summary);
    } catch {
      console.log(t, "RAW", line.slice(0, 300));
    }
  }
});
child.stderr.on("data", (chunk) => process.stdout.write(`stderr: ${chunk}`));
child.on("close", (code) => console.log(`exit ${code} after ${((Date.now() - started) / 1000).toFixed(1)}s`));
