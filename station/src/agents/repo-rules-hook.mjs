// A PostToolUse hook of Claude Code's and Codex's: the rules a repository keeps for agents (AGENTS.md, else CLAUDE.md,
// in its root and in each directory down to the one a tool touched), told to the agent the first time it touches that
// directory. Claude Code reads them itself only from its working directory up and, below it, when its Read tool opens
// a file there (Codex never below it); a station session works in its workspace, its clones and worktrees below it,
// and mostly through the shell, so it read a repository's rules only now and then (25 of 55 subagents on mbui,
// 2026-11-08).
// After a compaction (Claude Code's SessionStart of "compact", Codex's PostCompact) it forgets what the session was
// told: the summary keeps little of it, so the next tool to touch a directory tells its rules again. A rules file a
// tool itself names (the agent editing it) is not told again for that change: the agent has just written it.
import { existsSync, mkdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";

const MAX = 60_000;

let input;
try {
  input = JSON.parse(readFileSync(0, "utf8"));
} catch {
  process.exit(0);
}
const cwd = typeof input.cwd === "string" ? input.cwd : process.cwd();
const tool = input.tool_input ?? {};

/// The paths the tool was given: its file or path, or what in a shell command reads as one.
function paths() {
  const out = [];
  for (const key of ["file_path", "path", "notebook_path"]) if (typeof tool[key] === "string") out.push(tool[key]);
  if (typeof tool.command === "string") {
    for (const word of tool.command.split(/[\s;&|()<>`'"=]+/)) {
      if (word.includes("/") && !word.includes("://")) out.push(word.replace(/^[~]/, process.env.HOME ?? "~"));
    }
  }
  if (out.length === 0 && typeof tool.command === "string") out.push(cwd);
  return out;
}

/// The nearest existing directory of `path`.
function dirOf(path) {
  let p = isAbsolute(path) ? path : resolve(cwd, path);
  for (let i = 0; i < 64 && !existsSync(p); i++) p = dirname(p);
  try {
    p = realpathSync(p);
    return statSync(p).isDirectory() ? p : dirname(p);
  } catch {
    return null;
  }
}

/// The rule files from `dir`'s repository root down to `dir` (none outside a repository).
function rulesFor(dir) {
  const chain = [];
  let root = null;
  for (let p = dir; ; p = dirname(p)) {
    chain.unshift(p);
    if (existsSync(join(p, ".git"))) {
      root = p;
      break;
    }
    if (dirname(p) === p) break;
  }
  if (root === null) return [];
  const files = [];
  for (const d of chain) {
    const agents = join(d, "AGENTS.md");
    const claude = join(d, "CLAUDE.md");
    if (existsSync(agents)) files.push(agents);
    else if (existsSync(claude)) files.push(claude);
  }
  return files;
}

const who = `${input.session_id ?? "none"}-${input.agent_id ?? "main"}`.replace(/[^\w.-]/g, "_");
const stateDir = join(tmpdir(), "stillfail-repo-rules");
const stateFile = join(stateDir, `${who}.json`);
if (input.hook_event_name === "SessionStart" || input.hook_event_name === "PostCompact") {
  if (input.hook_event_name === "PostCompact" || input.source === "compact") rmSync(stateFile, { force: true });
  process.exit(0);
}
let seen = {};
try {
  seen = JSON.parse(readFileSync(stateFile, "utf8"));
} catch {}
const kept = JSON.stringify(seen);

const told = [];
let size = 0;
const named = paths();
const dirs = new Set(named.map(dirOf).filter((d) => d !== null));
/// The files the tool named itself, as they are on the disk.
const own = new Set(named.map((p) => { try { return realpathSync(isAbsolute(p) ? p : resolve(cwd, p)); } catch { return null; } }).filter((p) => p !== null));
for (const dir of dirs) {
  for (const file of rulesFor(dir)) {
    let text;
    try {
      const mtime = statSync(file).mtimeMs;
      if (seen[file] === mtime) continue;
      const before = seen[file];
      seen[file] = mtime;
      if (before !== undefined && own.has(file)) continue;
      text = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    // A CLAUDE.md that only points at the AGENTS.md beside it says nothing more.
    if (text.trim() === "@AGENTS.md") continue;
    if (size + text.length > MAX) text = text.slice(0, Math.max(0, MAX - size)) + "\n[cut: read the rest of the file]";
    size += text.length;
    told.push(`Contents of ${file} (the repository's rules for agents working in ${dirname(file)}${sep}; follow them):\n\n${text}`);
    if (size >= MAX) break;
  }
}
if (JSON.stringify(seen) !== kept) {
  try {
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(stateFile, JSON.stringify(seen));
  } catch {}
}
if (told.length === 0) process.exit(0);
process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: told.join("\n\n---\n\n") } }));
