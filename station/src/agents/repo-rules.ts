// The hook that tells a session a repository's rules (its AGENTS.md files) as its tools first touch the repository
// (./repo-rules-hook.mjs), as Claude Code and Codex run it: neither reads them below where it was started up but now and
// then (Claude Code as its Read tool opens a file there; Codex never), and a session starts in its workspace, its clones
// below it, and mostly reads them with the shell.
import { fileURLToPath } from "node:url";

export const REPO_RULES_HOOK = fileURLToPath(new URL("./repo-rules-hook.mjs", import.meta.url));
const quoted = (s: string) => `'${s.replaceAll("'", `'\\''`)}'`;
/// A hook's file as a command, run by the station's own Node (failing quietly where the station's files are not, in a
/// sandbox elsewhere).
export const hookCommand = (file: string) => `${quoted(process.execPath)} ${quoted(file)} 2>/dev/null || true`;
export const REPO_RULES_COMMAND = hookCommand(REPO_RULES_HOOK);
