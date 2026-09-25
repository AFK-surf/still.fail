// Spike 4: archive a session's runtime transcript (zstd) and its workspace away,
// then restore to the original paths and resume. A control step resumes BEFORE
// restoring and must fail, proving the archive removed what resume depends on.
// Usage: node spike/archive-resume.ts
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { zstdCompressSync, zstdDecompressSync } from "node:zlib";
import { claudeEnv, codexEnv, MODEL, report, run, SPIKE_ROOT, startAppServer } from "./lib.ts";

const rows: Record<string, unknown>[] = [];
const workRoot = join(SPIKE_ROOT, "archive-spike");
rmSync(workRoot, { recursive: true, force: true });

interface Archived { path: string; bytes: number; zstdBytes: number; data: Buffer }
function archive(paths: string[]): Archived[] {
  return paths.map((path) => {
    const raw = readFileSync(path);
    const data = zstdCompressSync(raw);
    rmSync(path);
    return { path, bytes: raw.length, zstdBytes: data.length, data };
  });
}
function restore(files: Archived[]): void {
  for (const file of files) {
    mkdirSync(dirname(file.path), { recursive: true });
    writeFileSync(file.path, zstdDecompressSync(file.data));
  }
}
function filesUnder(dir: string, match: (name: string) => boolean): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && match(entry.name))
    .map((entry) => join(entry.parentPath, entry.name));
}

// ── Claude ────────────────────────────────────────────────────────────────
{
  const workspace = join(workRoot, "claude-ws");
  mkdirSync(workspace, { recursive: true });
  const env = claudeEnv("ember-spike-archive-claude");
  const sessionId = randomUUID();
  const ask = (args: string[]) => run("claude", ["-p", ...args, "--dangerously-skip-permissions", "--model", MODEL,
    "--output-format", "json"], { cwd: workspace, env, timeout: 180_000 }).then((r) => JSON.parse(r.stdout));

  const first = await ask(["--session-id", sessionId, "Remember the codeword PELICAN-42. Reply with only: OK"]);
  const transcripts = filesUnder(join(env.CLAUDE_CONFIG_DIR!, "projects"), () => true)
    .filter((path) => path.includes(sessionId));
  const files = archive(transcripts);
  rmSync(workspace, { recursive: true, force: true });

  let control: string;
  try {
    mkdirSync(workspace, { recursive: true });
    const r = await ask(["--resume", sessionId, "What was the codeword? Reply with only the codeword."]);
    control = r.is_error ? `failed as expected: ${String(r.result).slice(0, 80)}` : `UNEXPECTED success: ${r.result}`;
  } catch (error: any) {
    control = `failed as expected: ${String(error.stderr ?? error.message).slice(-120)}`;
  }
  // The control run may have created a fresh transcript under the same id; drop it before restoring.
  for (const path of filesUnder(join(env.CLAUDE_CONFIG_DIR!, "projects"), () => true).filter((p) => p.includes(sessionId))) rmSync(path);

  restore(files);
  const resumed = await ask(["--resume", sessionId, "What was the codeword? Reply with only the codeword."]);
  rows.push({
    runtime: "claude", firstTurn: first.is_error ? "ERROR" : "ok",
    archivedFiles: files.map((f) => f.path.replace(env.CLAUDE_CONFIG_DIR!, "$CLAUDE_CONFIG_DIR")).join(" "),
    bytes: files.reduce((s, f) => s + f.bytes, 0), zstdBytes: files.reduce((s, f) => s + f.zstdBytes, 0),
    controlWithoutRestore: control,
    afterRestore: resumed.is_error ? `ERROR ${resumed.result}` : String(resumed.result).trim(),
  });
}

// ── Codex ─────────────────────────────────────────────────────────────────
{
  const workspace = join(workRoot, "codex-ws");
  mkdirSync(workspace, { recursive: true });
  const env = codexEnv("ember-spike-archive-codex");
  const sessionsDir = join(env.CODEX_HOME!, "sessions");
  const lastMessage = (items: any[]) => String(items.filter((i) => i?.type === "agentMessage").at(-1)?.text ?? "").trim();

  let app = await startAppServer(workspace, env);
  const threadId = (await app.request("thread/start", { cwd: workspace, model: MODEL, approvalPolicy: "never" })).thread.id as string;
  const first = lastMessage(await app.runTurn(threadId, "Remember the codeword OSPREY-7. Reply with only: OK"));
  app.killTree();

  const rollouts = filesUnder(sessionsDir, (name) => name.includes(threadId));
  const files = archive(rollouts);
  rmSync(workspace, { recursive: true, force: true });

  let control: string;
  mkdirSync(workspace, { recursive: true });
  app = await startAppServer(workspace, env);
  try {
    await app.request("thread/resume", { threadId, cwd: workspace, approvalPolicy: "never" });
    control = `UNEXPECTED: resume accepted without the rollout`;
  } catch (error) {
    control = `failed as expected: ${String(error).slice(0, 120)}`;
  }
  app.killTree();

  restore(files);
  app = await startAppServer(workspace, env);
  let afterRestore: string;
  try {
    await app.request("thread/resume", { threadId, cwd: workspace, approvalPolicy: "never" });
    afterRestore = lastMessage(await app.runTurn(threadId, "What was the codeword? Reply with only the codeword."));
  } catch (error) {
    afterRestore = `ERROR ${String(error).slice(0, 200)}`;
  } finally {
    app.killTree();
  }
  rows.push({
    runtime: "codex", firstTurn: first,
    archivedFiles: files.map((f) => f.path.replace(env.CODEX_HOME!, "$CODEX_HOME")).join(" "),
    bytes: files.reduce((s, f) => s + f.bytes, 0), zstdBytes: files.reduce((s, f) => s + f.zstdBytes, 0),
    controlWithoutRestore: control, afterRestore,
  });
}

report(`archive → restore → resume (model ${MODEL})`, rows);
console.log(JSON.stringify(rows, null, 2));
