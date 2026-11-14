// The hook that tells a session a repository's rules (its AGENTS.md files) as its tools first touch the repository
// (./repo-rules-hook.mjs), as Claude Code and Codex run it: neither reads them below where it was started up but now and
// then (Claude Code as its Read tool opens a file there; Codex never), and a session starts in its workspace, its clones
// below it, and mostly reads them with the shell.
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const REPO_RULES_HOOK = fileURLToPath(new URL("./repo-rules-hook.mjs", import.meta.url));
const quoted = (s: string) => `'${s.replaceAll("'", `'\\''`)}'`;

/// The Node a hook's command names, which must be there for as long as the agent's process given the command runs, an
/// update of the station later too: the release's own, beside the hook's file where the release is (<app>/station/ the
/// file, <app>/node the Node: a link to node/v<version> made by cloud/src/install.ts, a copy by install-windows.ts,
/// where the launcher finds it), which an update puts the next release's in the place of. Not process.execPath there:
/// that is what the link led to as the station started (node/v<version>/bin/node), which the installer prunes once a
/// release runs on another version, so a Claude Code or Codex process started before kept a command whose Node was
/// gone, and its hooks failed unseen (`|| true`) from then on. A checkout and the tests have no Node beside them and
/// run the hook on their own.
export function hookNode(file: string, has: (path: string) => boolean = existsSync): string {
  const own = join(dirname(dirname(file)), "node", process.platform === "win32" ? "node.exe" : join("bin", "node"));
  return has(own) ? own : process.execPath; // sync: one stat as the module loads, before the station serves
}

/// A hook's file as a command, run by the station's Node (`hookNode`) with `args` (failing quietly where the station's
/// files are not, in a sandbox elsewhere). Claude Code and Codex run it in a POSIX shell (Git Bash on Windows): each
/// word in single quotes, so nothing in a path or an argument is the shell's to read.
export const hookCommand = (file: string, ...args: string[]) => `${[hookNode(file), file, ...args].map(quoted).join(" ")} 2>/dev/null || true`;
export const REPO_RULES_COMMAND = hookCommand(REPO_RULES_HOOK);
