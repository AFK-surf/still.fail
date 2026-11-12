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

// (the file repo-rules.ts names as REPO_RULES_HOOK: test/claude.test.ts and codex.test.ts hold that it is the one started)
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
  // Codex's: its compaction is a PostCompact of its own.
  assert.equal(told({ trigger: "manual" }, "s4", undefined, "PostCompact"), "");
  assert.match(told({ tool_name: "Bash", tool_input: { command: "ls wt/apps/x" } }, "s4"), /HERON[\s\S]*MERLIN/);
});

test("what one call tells stays under what Claude Code takes whole; the rest follows on the next tools, in order, all of it", () => {
  // As this repository's are: a root file near a call's room, one below it longer than a call, one below that short.
  const big = join(workspace, "big");
  mkdirSync(join(big, ".git"), { recursive: true });
  mkdirSync(join(big, "app", "lib"), { recursive: true });
  const paragraphs = (name: string, n: number) => Array.from({ length: n }, (_, i) => `- ${name} rule ${i}: ${"words of it ".repeat(20)}`).join("\n") + "\n";
  const rootRules = `# Root\n\n${paragraphs("ROOT", 32)}`;
  const appRules = `# App\n\n${paragraphs("APP", 52)}`;
  const libRules = "# Lib\n\n- LIB rule, the only one.\n";
  assert.ok(rootRules.length > 8_000 && rootRules.length < 8_700 && appRules.length > 13_000);
  writeFileSync(join(big, "AGENTS.md"), rootRules);
  writeFileSync(join(big, "app", "AGENTS.md"), appRules);
  writeFileSync(join(big, "app", "lib", "AGENTS.md"), libRules);

  const calls: string[] = [told({ tool_name: "Bash", tool_input: { command: "ls big/app/lib" } }, "s6")];
  // The tools after it touch nothing of the repository: what waits is told all the same.
  for (let i = 0; i < 8; i++) calls.push(told({ tool_name: "Bash", tool_input: { command: "ls notes/" } }, "s6"));
  const spoke = calls.filter((c) => c !== "");
  assert.equal(spoke.length, 3);
  assert.deepEqual(calls.slice(3), ["", "", "", "", "", ""]);
  for (const call of spoke) assert.ok(call.length <= 10_000, `a call told ${call.length} characters`);
  assert.match(spoke[0]!, /^Contents of \S+big\/AGENTS\.md \([^)]*\):\n\n# Root/);
  assert.doesNotMatch(spoke[0]!, /APP rule/);
  assert.match(spoke[1]!, /app\/AGENTS\.md \([^)]*\), lines 1 to \d+ of 54:\n\n# App[\s\S]*\[more of this file follows after your next tool call\]$/);
  assert.match(spoke[2]!, /app\/AGENTS\.md \([^)]*\), lines \d+ to 54, the last of it:\n\n- APP rule[\s\S]*---[\s\S]*lib\/AGENTS\.md \([^)]*\):\n\n# Lib/);
  // Every rule of every file reached the session once, whole, in the files' order.
  const body = spoke.join("\n").split("\n").filter((l) => /^- (ROOT|APP|LIB) rule/.test(l));
  assert.deepEqual(body, [rootRules, appRules, libRules].flatMap((t) => t.split("\n").filter((l) => l.startsWith("- "))));

  // A file changed while part of it waits is told from its start; one the tool itself rewrote waits no more.
  assert.match(told({ tool_name: "Bash", tool_input: { command: "ls big/app" } }, "s7"), /# Root/);
  assert.match(told({ tool_name: "Bash", tool_input: { command: "ls notes/" } }, "s7"), /lines 1 to \d+ of 54/);
  const later = new Date(Date.now() + 30_000);
  writeFileSync(join(big, "app", "AGENTS.md"), `# App again\n\n${paragraphs("APP", 52)}`);
  utimesSync(join(big, "app", "AGENTS.md"), later, later);
  assert.match(told({ tool_name: "Bash", tool_input: { command: "ls notes/" } }, "s7"), /lines 1 to \d+ of 54:\n\n# App again/);
  const edited = new Date(Date.now() + 60_000);
  writeFileSync(join(big, "app", "AGENTS.md"), `# App rewritten\n\n${paragraphs("APP", 52)}`);
  utimesSync(join(big, "app", "AGENTS.md"), edited, edited);
  assert.equal(told({ tool_name: "Edit", tool_input: { file_path: join(big, "app", "AGENTS.md") } }, "s7"), "");
  assert.equal(told({ tool_name: "Bash", tool_input: { command: "ls notes/" } }, "s7"), "");
});
