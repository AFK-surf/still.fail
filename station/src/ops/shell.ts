// The shell jobs and device commands run under: /bin/sh, or on Windows the one Git for Windows brings (Git Bash's).
// What runs there is what agents write, and Claude Code on Windows itself runs its commands under Git Bash; jobs' own
// wrapper and `stillfail-job` are sh scripts too.
import { existsSync, readFileSync, statSync } from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { runnerBinary } from "../agents/runner.ts";
import { findCommand } from "../updates/runtimes.ts";

export const WINDOWS = process.platform === "win32";

let found: string | null | undefined;

/// The shell's path. On Windows: CLAUDE_CODE_GIT_BASH_PATH (Claude Code's own setting), else Git's sh beside the git
/// on PATH, else where Git installs by default; never System32's bash (WSL's, another machine's files).
export function posixShell(env: NodeJS.ProcessEnv = process.env): string {
  if (!WINDOWS) return "/bin/sh";
  if (found === undefined) found = gitShell(env);
  if (found === null) throw new Error("jobs and commands on Windows run under Git Bash: install Git for Windows (git-scm.com), or set CLAUDE_CODE_GIT_BASH_PATH");
  return found;
}

function gitShell(env: NodeJS.ProcessEnv): string | null {
  const candidates: string[] = [];
  if (env.CLAUDE_CODE_GIT_BASH_PATH) candidates.push(env.CLAUDE_CODE_GIT_BASH_PATH);
  for (const dir of pathOf(env).split(delimiter)) {
    if (dir === "" || /\\system32\\?$/i.test(dir)) continue;
    // Git's cmd\ (git.exe) is what an installer puts on PATH; its sh is in bin\.
    if (existsSync(join(dir, "git.exe"))) candidates.push(join(dirname(dir), "bin", "sh.exe"));
    candidates.push(join(dir, "sh.exe"));
  }
  for (const root of [env.ProgramFiles, env["ProgramFiles(x86)"], env.LOCALAPPDATA && join(env.LOCALAPPDATA, "Programs")]) {
    if (root) candidates.push(join(root, "Git", "bin", "sh.exe"));
  }
  return candidates.find((p) => existsSync(p)) ?? null;
}

/// A command as a group of its own: as it is on Unix (spawned detached, it leads one); on Windows under
/// `stillfail-runner --job`, whose job holds it and all it starts (what a shell execs, its parent gone, too), ended
/// whole when the runner is (see jobs/group.ts).
export function grouped(program: string, args: string[]): [string, string[]] {
  return WINDOWS ? [runnerBinary(), ["--job", "--", program, ...args]] : [program, args];
}

/// How Node runs a runtime's CLI (`claude`, `codex`: a name on `env`'s PATH, or a path) with fixed `args`. On Windows a
/// bare name is found with PATHEXT (libuv adds .exe and .com only), and a .cmd or .bat (npm's shims) runs through cmd,
/// which Node refuses to do by itself: each argument quoted, and one cmd would read into (a quote, a %) refused.
export function runnable(command: string, args: string[], env: NodeJS.ProcessEnv): { file: string; args: string[]; windowsVerbatimArguments?: true } {
  if (!WINDOWS) return { file: command, args };
  const file = /[\\/]/.test(command) ? command : (findCommand(command, env)?.onPath ?? command);
  if (!/\.(cmd|bat)$/i.test(file)) return { file, args };
  const shim = unshim(file, env);
  if (shim !== null) return { file: shim.node, args: [shim.script, ...args] };
  for (const a of [file, ...args]) if (/["%\r\n]/.test(a)) throw new Error(`cannot pass ${JSON.stringify(a)} through cmd`);
  const line = [file, ...args].map((a) => `"${a}"`).join(" ");
  return { file: env.ComSpec ?? process.env.ComSpec ?? "cmd.exe", args: ["/d", "/s", "/c", `"${line}"`], windowsVerbatimArguments: true };
}

/// What a `.cmd` shim runs when its arguments can go around cmd (as the runner's `unshim`, native/runner): npm's
/// (`"%_prog%" "%dp0%\…\cli.js" %*`) as Node and the script; one that only hands on to another `.cmd` (Vite+'s) as
/// what that one runs. Null for anything else.
export function unshim(path: string, env: NodeJS.ProcessEnv = process.env): { node: string; script: string } | null {
  for (let i = 0; i < 4; i++) {
    if (!/\.cmd$/i.test(path)) return null;
    let text: string;
    try {
      const st = statSync(path);
      if (!st.isFile() || st.size > 16 * 1024) return null;
      text = readFileSync(path, "utf8");
    } catch {
      return null;
    }
    const dir = dirname(path);
    const npm = text.match(/"%_prog%"\s+"%dp0%\\([^"]+)"\s+%\*/);
    if (npm) {
      const beside = join(dir, "node.exe");
      const node = existsSync(beside) ? beside : (findCommand("node", env)?.onPath ?? "node");
      return { node, script: join(dir, npm[1]!) };
    }
    const lines = text
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l !== "" && l.toLowerCase() !== "@echo off" && !l.toLowerCase().startsWith("exit /b"));
    const on = lines.length === 1 ? lines[0]!.match(/^"([^"]+)"\s+%\*$/) : null;
    if (!on) return null;
    path = on[1]!;
  }
  return null;
}

/// PATH as Windows spells it in an environment copied from process.env (`Path`, as often as not).
export function pathOf(env: NodeJS.ProcessEnv): string {
  const key = Object.keys(env).find((k) => k.toUpperCase() === "PATH");
  return (key && env[key]) ?? "";
}

/// `env` with `dir` first on its PATH. On Windows the variable is one whatever its case: the others are dropped, so a
/// child is not given two.
export function prependPath(env: NodeJS.ProcessEnv, dir: string): NodeJS.ProcessEnv {
  const rest = pathOf(env);
  const out: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(env)) if (!(WINDOWS && k.toUpperCase() === "PATH")) out[k] = v;
  out.PATH = `${dir}${delimiter}${rest}`;
  return out;
}
