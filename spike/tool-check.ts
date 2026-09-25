// Do claude and codex actually call tools with the spike model? Memory numbers
// from turns that never ran a tool would be meaningless. Usage: node spike/tool-check.ts [cwd]
import { spawn } from "node:child_process";
import { claudeEnv, codexEnv, MODEL, report } from "./lib.ts";

/** Runs a command with stdin closed (both CLIs otherwise wait on it). Rejects on non-zero exit. */
function run(command: string, args: string[], options: { cwd: string; env: NodeJS.ProcessEnv; timeout: number }):
  Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const child = spawn(command, args, { cwd: options.cwd, env: options.env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    const timer = setTimeout(() => child.kill("SIGTERM"), options.timeout);
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      const elapsed = `${Math.round((Date.now() - started) / 1000)}s`;
      if (code === 0) resolve({ stdout, stderr });
      else reject(Object.assign(new Error(`exit ${code ?? signal} after ${elapsed}`), { stderr: `exit ${code ?? signal} after ${elapsed}: ${stderr}` }));
    });
  });
}
const cwd = process.argv[2] ?? process.cwd();
const ask = "Use your shell tool to run `ls -la`, then reply with only the number of entries it printed.";
const rows: Record<string, unknown>[] = [];

try {
  const { stdout } = await run("claude", ["-p", ask, "--dangerously-skip-permissions", "--model", MODEL,
    "--output-format", "stream-json", "--verbose"], { cwd, env: claudeEnv("ember-spike-toolcheck"), timeout: 240_000 });
  const frames = stdout.trim().split("\n").map((line) => JSON.parse(line));
  const init = frames.find((f) => f.type === "system" && f.subtype === "init");
  const blocks = frames.filter((f) => f.type === "assistant").flatMap((f) => f.message.content);
  const result = frames.find((f) => f.type === "result");
  rows.push({
    runtime: "claude", toolsOffered: init?.tools?.length,
    toolCalls: blocks.filter((b: any) => b.type === "tool_use").map((b: any) => b.name).join(",") || "none",
    answer: String(result?.result ?? "").slice(0, 120), outcome: result?.subtype,
  });
} catch (error: any) {
  rows.push({ runtime: "claude", answer: `FAILED: ${String(error.stderr || error.message).slice(-300)}` });
}

try {
  const { stdout } = await run("codex", ["exec", "--json", "--skip-git-repo-check",
    "--dangerously-bypass-approvals-and-sandbox", ask], { cwd, env: codexEnv("ember-spike-toolcheck"), timeout: 240_000 });
  const events = stdout.trim().split("\n").flatMap((line) => { try { return [JSON.parse(line)]; } catch { return []; } });
  const items = events.filter((e) => e.type === "item.completed").map((e) => e.item);
  rows.push({
    runtime: "codex",
    toolCalls: items.filter((i: any) => i.type !== "agent_message" && i.type !== "reasoning").map((i: any) => i.type).join(",") || "none",
    answer: String(items.filter((i: any) => i.type === "agent_message").at(-1)?.text ?? "").slice(0, 120),
    outcome: events.at(-1)?.type,
  });
} catch (error: any) {
  rows.push({ runtime: "codex", answer: `FAILED: ${String(error.stderr || error.message).slice(-300)}` });
}

report(`tool calls with ${MODEL}`, rows);
