// Claude Code and Codex on this machine (the Rust station's updates.rs): where the station's PATH finds them, how each is
// updated the way it was installed (`claude update`, npm, Homebrew, Vite+, Codex's standalone installer) or installed
// when it is not there, and running those commands.
import { spawn } from "node:child_process";
import { existsSync, realpathSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, delimiter, dirname, join } from "node:path";
import { type Lang, tr } from "../ops/i18n.ts";
import { wall } from "../ops/fibers.ts";
import { grouped } from "../ops/shell.ts";

/// The environment commands run in: the station's own (its PATH says where the runtimes are).
export type Env = Record<string, string | undefined>;

export type Kind = "station" | "claude" | "codex";
export const KINDS: Kind[] = ["station", "claude", "codex"];
export const RUNTIMES: Exclude<Kind, "station">[] = ["claude", "codex"];

export const kindName = (k: Kind) => (k === "station" ? "Station" : k === "claude" ? "Claude Code" : "Codex");
export const kindCommand = (k: Kind) => (k === "station" ? "stillfail-station" : k);
/// Where the latest is said: the npm registry's latest of the runtime's package.
export const kindPackage = (k: Kind) => (k === "claude" ? "@anthropic-ai/claude-code" : k === "codex" ? "@openai/codex" : "");

/// How an update is done: a program and its arguments.
export type How = { program: string; args: string[] };

/// The prefetched build's version in place of `@latest`, keeping the destination and other options; npm's package
/// index revalidated (the prefetched tarball does not refresh it, and a cached index from before this release could
/// reject the pinned version).
export function pinNpmVersion(how: How, pkg: string, version: string): How {
  return { program: how.program, args: [...how.args.map((a) => (a === `${pkg}@latest` ? `${pkg}@${version}` : a)), "--prefer-online"] };
}

/// A command as the station's PATH finds it: where it was found (the link on PATH) and what that is.
export type Found = { onPath: string; real: string };

const executable = (p: string) => {
  try {
    const st = statSync(p);
    return st.isFile() && (st.mode & 0o111) !== 0;
  } catch {
    return false;
  }
};
const real = (p: string) => {
  try {
    return realpathSync(p);
  } catch {
    return null;
  }
};

/// On Windows a command is a file with one of PATHEXT's extensions (no mode bit says it runs): `codex` is found as
/// `codex.cmd`, `claude` as `claude.exe`.
const WINDOWS = process.platform === "win32";
const runnable = (p: string) => {
  try {
    return statSync(p).isFile();
  } catch {
    return false;
  }
};

export function findCommand(name: string, env: Env): Found | null {
  const pathKey = WINDOWS ? Object.keys(env).find((k) => k.toUpperCase() === "PATH") : "PATH";
  const path = pathKey === undefined ? undefined : env[pathKey];
  if (path === undefined) return null;
  const exts = WINDOWS ? (env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD").split(";").filter((e) => e !== "").map((e) => e.toLowerCase()) : [""];
  for (const dir of path.split(delimiter)) {
    for (const ext of exts) {
      // An empty entry is the current directory, as split_paths has it.
      const onPath = join(dir === "" ? "." : dir, name + ext);
      if (WINDOWS ? runnable(onPath) : executable(onPath)) return { onPath, real: real(onPath) ?? onPath };
    }
  }
  return null;
}

/// Why a runtime cannot be updated from here: said in the language it is read in.
export class Unable {
  readonly key: string;
  readonly args: Record<string, unknown>;
  constructor(key: string, args: Record<string, unknown> = {}) {
    this.key = key;
    this.args = args;
  }
  say(lang: Lang) {
    return tr(lang, this.key, this.args);
  }
}

/// How a runtime installed as `found` is updated, or why it cannot be from here.
export function howToUpdate(kind: Kind, found: Found, env: Env): How | Unable {
  // The markers below are written with `/`: a Windows path is read with them too.
  const realPath = WINDOWS ? found.real.replaceAll("\\", "/") : found.real;
  const name = kindName(kind);
  // Vite+ global commands are shims pointing to vp itself. Its packages are separate from npm's; `claude update` can
  // report success after updating a different installation.
  // On Windows a Vite+ command is a shim of its own (codex.cmd, codex.exe) beside vp.exe.
  if (WINDOWS && kind !== "station" && existsSync(join(dirname(found.onPath), "vp.exe"))) {
    return { program: join(dirname(found.onPath), "vp.exe"), args: ["install", "-g", `${kindPackage(kind)}@latest`] };
  }
  if (kind !== "station" && basename(realPath) === "vp") {
    const beside = join(dirname(found.onPath), "vp");
    let vp: string | null = real(beside) === realPath ? beside : null;
    if (vp === null) {
      const other = findCommand("vp", env);
      if (other !== null && other.real === realPath) vp = other.onPath;
    }
    if (vp === null) return new Unable("station.updates.noVp", { name });
    return { program: vp, args: ["install", "-g", `${kindPackage(kind)}@latest`] };
  }
  const brew = (): string | Unable => findCommand("brew", env)?.onPath ?? new Unable("station.updates.noBrew", { name });
  const npm = (): string | Unable => {
    // The npm of the Node the command is installed in (…/lib/node_modules/… → …/bin/npm): the link on PATH can sit
    // beside another Node's npm (~/.local/bin with links into two Nodes), which installs where PATH does not look.
    const at = realPath.indexOf("/lib/node_modules/");
    const own = at >= 0 ? join(found.real.slice(0, at), "bin/npm") : null;
    if (own !== null && existsSync(own)) return own;
    const beside = join(dirname(found.onPath), "npm");
    if (existsSync(beside)) return beside;
    return findCommand("npm", env)?.onPath ?? new Unable("station.updates.noNpm", { name });
  };
  const using = (program: string | Unable, args: string[]): How | Unable => (program instanceof Unable ? program : { program, args });
  const pkg = `${kindPackage(kind)}@latest`;
  if (kind === "station") return new Unable("");
  // npm on Windows: the command a .cmd shim in the global prefix, the package in its node_modules beside it.
  if (WINDOWS && /\.cmd$/i.test(found.onPath) && existsSync(join(dirname(found.onPath), "node_modules", ...kindPackage(kind).split("/")))) {
    const prefix = dirname(found.onPath);
    const own = join(prefix, "npm.cmd");
    return using(existsSync(own) ? own : (findCommand("npm", env)?.onPath ?? new Unable("station.updates.noNpm", { name })), ["install", "-g", pkg, "--prefix", prefix]);
  }
  if (realPath.includes("/Caskroom/")) return using(brew(), ["upgrade", "--cask", kind === "claude" ? "claude-code" : "codex"]);
  if (realPath.includes("/Cellar/")) return using(brew(), ["upgrade", kind === "claude" ? "claude-code" : "codex"]);
  if (realPath.includes("/node_modules/")) {
    // npm's shebang uses PATH's node; even the right npm can therefore choose another Node's global prefix. Explicitly
    // target the installation the station actually uses.
    const at = realPath.indexOf("/lib/node_modules/");
    if (at < 0) return new Unable("station.updates.npmRootUnknown", { path: realPath });
    // The prefix as the machine writes it (realPath has the same length: only its separators are changed).
    return using(npm(), ["install", "-g", pkg, "--prefix", found.real.slice(0, at)]);
  }
  if (kind === "claude") return { program: found.onPath, args: ["update"] };
  // Its installer is a shell script (install.sh): not Windows'.
  if (!WINDOWS && realPath.includes("/packages/standalone/releases/")) return standaloneCodexUpdate(found);
  return new Unable("station.updates.codexElsewhere", { path: realPath });
}

/// Codex's standalone install, updated by its own installer (its checksums, versioned releases and atomic link
/// switch), keeping both the package home and the visible command where this station has them.
function standaloneCodexUpdate(found: Found): How | Unable {
  const invalid = new Unable("station.updates.standaloneUnknown", { path: found.onPath });
  const marker = "/packages/standalone/releases/";
  const at = found.real.lastIndexOf(marker);
  if (at < 0) return invalid;
  const home = found.real.slice(0, at);
  const release = found.real.slice(at + marker.length);
  const slash = release.indexOf("/");
  if (slash < 0) return invalid;
  const binary = release.slice(slash + 1);
  const bin = dirname(found.onPath);
  const standalone = join(home, "packages/standalone");
  // Never replace a binary inside an immutable release, or make current/bin link into itself.
  if (!(binary === "bin/codex" || binary === "codex") || bin === standalone || bin.startsWith(`${standalone}/`)) return invalid;
  const script = `set -eu
installer=$(curl -fsSL https://chatgpt.com/codex/install.sh)
CODEX_HOME="$1" CODEX_INSTALL_DIR="$2" CODEX_NON_INTERACTIVE=1 sh -c "$installer" -- --release latest`;
  return { program: "/bin/sh", args: ["-c", script, "stillfail-codex-update", home, bin] };
}

/// How a runtime the machine has not is installed, or why it cannot be from here: Claude Code by its own installer
/// (into ~/.local/bin, on the station's PATH as install.ts sets it), Codex by npm, else Homebrew.
export function howToInstall(kind: Kind, env: Env): How | Unable {
  if (kind === "station") return new Unable("");
  if (kind === "claude") return WINDOWS ? CLAUDE_WINDOWS_INSTALL : { program: "/bin/sh", args: ["-c", "curl -fsSL https://claude.ai/install.sh | bash"] };
  const npm = findCommand("npm", env);
  if (npm) return { program: npm.onPath, args: ["install", "-g", "@openai/codex@latest"] };
  const brew = findCommand("brew", env);
  if (brew) return { program: brew.onPath, args: ["install", "--cask", "codex"] };
  return new Unable("station.updates.noNpmNoBrew");
}

/// Claude Code's own installer on Windows (into ~\\.local\\bin), as its documentation gives it.
export const CLAUDE_WINDOWS_INSTALL: How = {
  program: "powershell",
  args: ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "irm https://claude.ai/install.ps1 | iex"],
};

/// A command that did not end in time.
export class NotFinished extends Error {}

/// Runs a command to its end: whether it succeeded, and what it said (stdout and stderr), each line told as it is said.
/// Out of any repository (npm and claude look around them) and in its own process group (npm's children end with it
/// when it runs too long). The environment is exactly `env`.
export function runLines(program: string, args: string[], env: Env, timeoutMs: number, onLine: (line: string) => void = () => {}, lang: Lang = "zh"): Promise<[boolean, string]> {
  return runBoth(program, args, env, timeoutMs, onLine, lang).then(([ok, said]) => [ok, said]);
}

/// Runs a command to its end as `runLines` does; what it said as `run` has it: stdout, then stderr.
export function run(program: string, args: string[], env: Env, timeoutMs: number, lang: Lang = "zh"): Promise<[boolean, string]> {
  return runBoth(program, args, env, timeoutMs, () => {}, lang).then(([ok, , out, err]) => [ok, out + err]);
}

function runBoth(program: string, args: string[], env: Env, timeoutMs: number, onLine: (line: string) => void, lang: Lang): Promise<[boolean, string, string, string]> {
  return new Promise((resolve, reject) => {
    const clean: Record<string, string> = {};
    for (const [k, v] of Object.entries(env)) if (v !== undefined) clean[k] = v;
    // On Windows under `stillfail-runner --job`: what npm starts ends with it, and a .cmd (npm's) is run through cmd,
    // escaped, by the runner.
    const child = spawn(...grouped(program, args), { env: clean, cwd: tmpdir(), stdio: ["ignore", "pipe", "pipe"], detached: true, windowsHide: true });
    let said = "";
    const whole = ["", ""];
    const take = (stream: NodeJS.ReadableStream, which: 0 | 1) => {
      let carry = "";
      stream.setEncoding("utf8");
      stream.on("data", (chunk: string) => {
        whole[which] += chunk;
        carry += chunk;
        for (let at = carry.indexOf("\n"); at >= 0; at = carry.indexOf("\n")) {
          const line = carry.slice(0, at);
          carry = carry.slice(at + 1);
          onLine(line);
          said += `${line}\n`;
        }
      });
      return new Promise<void>((done) =>
        stream.on("end", () => {
          if (carry !== "") {
            onLine(carry);
            said += `${carry}\n`;
          }
          done();
        }),
      );
    };
    const ends = Promise.all([take(child.stdout!, 0), take(child.stderr!, 1)]);
    const timer = wall.after(timeoutMs, () => {
      try {
        if (WINDOWS) child.kill("SIGKILL");
        else process.kill(-child.pid!, "SIGKILL");
      } catch {}
      reject(new NotFinished(tr(lang, "station.updates.notFinished", { program })));
    });
    child.on("error", (e) => {
      timer();
      reject(e);
    });
    child.on("close", (code) => {
      timer();
      void ends.then(() => resolve([code === 0, said, whole[0]!, whole[1]!]));
    });
  });
}
