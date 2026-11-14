// A PostToolUse hook of Claude Code's and Codex's: the rules a repository keeps for agents (AGENTS.md, else CLAUDE.md,
// in its root and in each directory down to the one a tool touched), told to the agent the first time it touches that
// directory. Claude Code reads them itself only from its working directory up and, below it, when its Read tool opens
// a file there (Codex never below it); a station session works in its workspace, its clones and worktrees below it,
// and mostly through the shell, so it read a repository's rules only now and then (25 of 55 subagents on mbui,
// 2026-11-08).
// After a compaction (Claude Code's SessionStart of "compact", Codex's PostCompact) it forgets what the session was
// told: the summary keeps little of it, so the next tool to touch a directory tells its rules again. A rules file a
// tool itself names (the agent editing it) is not told again for that change: the agent has just written it.
// What one tool's hook tells is kept under what Claude Code takes of a hook whole (10,000 characters, each hook's own:
// more is put in a file and the agent shown its first 2,000, so three of this repository's files told at once, 35,000,
// reached it as a quarter of the first; 2026-11-10). The files wait in a line, root first: each call tells what fits, a file longer
// than a call's room in pieces cut between its paragraphs, and the next tool, whatever it touches, is told what follows.
import { existsSync, mkdirSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve, sep } from "node:path";

/// What one call tells at most, its headings included: under Claude Code's 10,000.
const MAX = 9_800;
/// A piece of a file is begun only with this much room left; with less the file waits for the next call.
const LEAST = 1_500;
/// Between two files told in one call.
const BETWEEN = "\n\n---\n\n";

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
/// The files waiting to be told, in order: `at` is how far into `file` (as it was at `mtime`) the session was told.
/// Kept in the record under a name no file has (every file's is absolute).
const line = Array.isArray(seen.waiting) ? seen.waiting.filter((w) => typeof w?.file === "string" && typeof w.at === "number") : [];

const named = paths();
const dirs = new Set(named.map(dirOf).filter((d) => d !== null));
/// The files the tool named itself, as they are on the disk.
const own = new Set(named.map((p) => { try { return realpathSync(isAbsolute(p) ? p : resolve(cwd, p)); } catch { return null; } }).filter((p) => p !== null));
for (const dir of dirs) {
  for (const file of rulesFor(dir)) {
    try {
      const mtime = statSync(file).mtimeMs;
      if (seen[file] === mtime) continue;
      const before = seen[file];
      seen[file] = mtime;
      const waiting = line.findIndex((w) => w.file === file);
      if (before !== undefined && own.has(file)) {
        if (waiting >= 0) line.splice(waiting, 1);
        continue;
      }
      if (waiting < 0) line.push({ file, mtime, at: 0 });
      else Object.assign(line[waiting], { mtime, at: 0 });
    } catch {}
  }
}

/// Where to cut `text` at `room` characters or fewer: before a heading, a list's item or a paragraph when one begins
/// in the second half of the room, else at a line's end, else at the room.
function cut(text, room) {
  for (let i = room; i > room / 2; i--) if (text[i - 1] === "\n" && /^(#|[-*>] |\d+\. |\n)/.test(text.slice(i, i + 4))) return i;
  const end = text.lastIndexOf("\n", room - 1);
  return end > 0 ? end + 1 : room;
}

const told = [];
let room = MAX;
while (line.length > 0) {
  const next = line[0];
  let text;
  try {
    // Changed since it was put in the line: told from its start, as it is now.
    const mtime = statSync(next.file).mtimeMs;
    if (mtime !== next.mtime) Object.assign(next, { mtime, at: 0 });
    seen[next.file] = mtime;
    text = readFileSync(next.file, "utf8");
  } catch {
    line.shift();
    continue;
  }
  // A CLAUDE.md that only points at the AGENTS.md beside it says nothing more.
  if (text.trim() === "@AGENTS.md") {
    line.shift();
    continue;
  }
  /// How many lines of the file end at or before `to`.
  const lines = (to) => text.slice(0, to).split("\n").length - (to === 0 || text[to - 1] === "\n" ? 1 : 0);
  const head = (which) => `Contents of ${next.file} (the repository's rules for agents working in ${dirname(next.file)}${sep}; follow them)${which}:\n\n`;
  const last = head(next.at === 0 ? "" : `, lines ${lines(next.at) + 1} to ${lines(text.length)}, the last of it`);
  if (last.length + text.length - next.at <= room) {
    told.push(last + text.slice(next.at));
    room -= told.at(-1).length + BETWEEN.length;
    line.shift();
    continue;
  }
  // It does not fit in what is left of this call. One that fits a call of its own waits for it, whole; a longer one is
  // told as far as it fits, when that is worth beginning.
  const more = "\n[more of this file follows after your next tool call]";
  const within = room - head(", lines 00000 to 00000 of 00000").length - more.length;
  if (told.length > 0 && (last.length + text.length - next.at <= MAX || within < LEAST)) break;
  const to = next.at + cut(text.slice(next.at), Math.max(within, 1));
  told.push(head(`, lines ${lines(next.at) + 1} to ${lines(to)} of ${lines(text.length)}`) + text.slice(next.at, to) + more);
  next.at = to;
  break;
}
if (line.length > 0) seen.waiting = line;
else delete seen.waiting;
if (JSON.stringify(seen) !== kept) {
  try {
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(stateFile, JSON.stringify(seen));
  } catch {}
}
if (told.length === 0) process.exit(0);
process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: told.join(BETWEEN) } }));
