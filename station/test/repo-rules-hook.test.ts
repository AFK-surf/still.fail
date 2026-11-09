// The hook a Claude Code session runs after each tool (src/agents/repo-rules-hook.mjs): a repository's rules for agents
// (AGENTS.md, else CLAUDE.md, from its root down to the directory touched) told the first time a tool touches it, by
// the shell too, once per session and per subagent, again when a file changed (not to the tool that changed it) and
// after a compaction; nothing outside a repository.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

// (the file claude.ts names as REPO_RULES_HOOK: test/claude.test.ts holds that it is the one started)
const REPO_RULES_HOOK = fileURLToPath(new URL("../src/agents/repo-rules-hook.mjs", import.meta.url));

const root = mkdtempSync(join(tmpdir(), "repo-rules-"));
after(() => rmSync(root, { recursive: true, force: true }));
const workspace = join(root, "workspace");
const repo = join(workspace, "wt");
mkdirSync(join(repo, ".git"), { recursive: true });
mkdirSync(join(repo, "apps", "x", "src"), { recursive: true });
mkdirSync(join(repo, "other"), { recursive: true });
writeFileSync(join(repo, "AGENTS.md"), "root rule HERON");
writeFileSync(join(repo, "CLAUDE.md"), "@AGENTS.md");
writeFileSync(join(repo, "apps", "x", "CLAUDE.md"), "x rule OSPREY");
writeFileSync(join(repo, "apps", "x", "src", "a.txt"), "a");
mkdirSync(join(workspace, "notes"), { recursive: true });
writeFileSync(join(workspace, "AGENTS.md"), "not a repository's");

/// The context the hook adds after `tool` with `input`, "" when none.
function told(input: object, session = "s1", agent?: string, event = "PostToolUse"): string {
  const out = execFileSync(process.execPath, [REPO_RULES_HOOK], {
    input: JSON.stringify({ session_id: session, ...(agent === undefined ? {} : { agent_id: agent }), cwd: workspace, hook_event_name: event, ...input }),
    env: { ...process.env, TMPDIR: root, TEMP: root, TMP: root },
  }).toString();
  return out === "" ? "" : JSON.parse(out).hookSpecificOutput.additionalContext;
}

test("a shell command into a repository tells its rules from the root down, once", () => {
  const first = told({ tool_name: "Bash", tool_input: { command: "cat wt/apps/x/src/a.txt | head -3" } });
  assert.match(first, /root rule HERON[\s\S]*x rule OSPREY/);
  assert.doesNotMatch(first, /not a repository's/);
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "grep -rn foo wt/apps/x" } }), "");
  // A directory of the repository not touched before: only what is new.
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "ls wt/other" } }), "");
});

test("a file tool's path, a subagent and a changed rule are told again; outside a repository nothing", () => {
  assert.match(told({ tool_name: "Read", tool_input: { file_path: join(repo, "apps", "x", "src", "a.txt") } }, "s2"), /OSPREY/);
  assert.match(told({ tool_name: "Grep", tool_input: { pattern: "x", path: join(repo, "apps", "x") } }, "s2", "agent-1"), /HERON[\s\S]*OSPREY/);
  const later = new Date(Date.now() + 10_000);
  writeFileSync(join(repo, "apps", "x", "CLAUDE.md"), "x rule KESTREL");
  utimesSync(join(repo, "apps", "x", "CLAUDE.md"), later, later);
  const again = told({ tool_name: "Bash", tool_input: { command: `cat ${join(repo, "apps", "x", "src", "a.txt")}` } }, "s2");
  assert.match(again, /KESTREL/);
  assert.doesNotMatch(again, /HERON/);
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "ls notes/ && echo done" } }, "s3"), "");
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "curl -s https://example.com/a/b" } }, "s3"), "");
});

test("a rules file the tool itself wrote is not told again; after a compaction every one is", () => {
  const rules = join(repo, "apps", "x", "CLAUDE.md");
  assert.match(told({ tool_name: "Read", tool_input: { file_path: join(repo, "apps", "x", "src", "a.txt") } }, "s4"), /HERON[\s\S]*rule/);
  const later = new Date(Date.now() + 20_000);
  writeFileSync(rules, "x rule MERLIN");
  utimesSync(rules, later, later);
  assert.equal(told({ tool_name: "Edit", tool_input: { file_path: rules } }, "s4"), "");
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "ls wt/apps/x/src" } }, "s4"), "");
  // A file never told is told even to the tool that wrote it.
  assert.match(told({ tool_name: "Write", tool_input: { file_path: rules } }, "s5"), /HERON[\s\S]*MERLIN/);
  // Compacted: told again, a subagent's own record left as it was.
  assert.match(told({ tool_name: "Bash", tool_input: { command: "ls wt/apps/x" } }, "s4", "agent-2"), /MERLIN/);
  assert.equal(told({ source: "compact" }, "s4", undefined, "SessionStart"), "");
  assert.match(told({ tool_name: "Bash", tool_input: { command: "ls wt/apps/x" } }, "s4"), /HERON[\s\S]*MERLIN/);
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "ls wt/apps/x" } }, "s4", "agent-2"), "");
});
