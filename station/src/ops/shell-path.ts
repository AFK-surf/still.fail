// A service may start without the PATH a person's interactive shell sets (a version manager or a custom bin). Read
// only that PATH, and use it only for a command absent from the given environment. The shell is time-bounded and its
// output other than the probe's own line is ignored; no shell credentials are brought into a runtime's environment.
import { createHash, randomBytes } from "node:crypto";
import { wall } from "./fibers.ts";
import { endCommand, startCommand } from "./processes.ts";
import { platform, type Env } from "../platform/index.ts";

const KEEP_MS = 30_000;
const PROBE_MS = 8_000;
const MAX_OUTPUT = 256 * 1024;
const CODE = `const fs = require('node:fs'), path = require('node:path');
const dirs = (process.env.PATH || '').split(path.delimiter).filter(path.isAbsolute).map(p => {
  try { return fs.realpathSync(p); } catch { return p; }
});
process.stdout.write('\\n' + process.env.STILLFAIL_SHELL_MARK + Buffer.from(JSON.stringify(dirs)).toString('base64') + '\\n');`;

type Reading = { at: number; value: Promise<string[] | null> };
const readings = new Map<string, Reading>();

/// A software recheck asks the shell again, so a PATH edited after the station started can be picked up at once.
export function forgetShellPaths() {
  readings.clear();
}

/// Keep account credentials out of the probe, including those supplied by a profile for its own process.
function probeEnv(env: Env): Record<string, string> {
  return Object.fromEntries(Object.entries(env).filter((e): e is [string, string] =>
    e[1] !== undefined && !/(TOKEN|SECRET|PASSWORD|AUTH|(^|_)KEY($|_))/i.test(e[0]) && !["CODEX_HOME", "CLAUDE_CONFIG_DIR"].includes(e[0]),
  ));
}

/// A shell's PATH with directory links resolved while it still runs (fnm's multishell link can go away afterward).
export function readShellPath(shell: string, login: boolean, source: Env, timeoutMs = PROBE_MS): Promise<string[] | null> {
  const marker = `__STILLFAIL_PATH_${randomBytes(16).toString("hex")}__`;
  const env = { ...probeEnv(source), STILLFAIL_SHELL_MARK: marker, STILLFAIL_SHELL_NODE: process.execPath, STILLFAIL_SHELL_CODE: CODE };
  const args = ["-i", ...(login ? ["-l"] : []), "-c", '"$STILLFAIL_SHELL_NODE" -e "$STILLFAIL_SHELL_CODE"'];
  return new Promise((resolve) => {
    let child;
    try {
      child = startCommand(shell, args, { env, cwd: platform.home(source), stdio: ["ignore", "pipe", "ignore"] });
    } catch {
      resolve(null);
      return;
    }
    let output = "";
    let done = false;
    const finish = (value: string[] | null) => {
      if (done) return;
      done = true;
      stop();
      resolve(value);
    };
    const stop = wall.after(timeoutMs, () => { endCommand(child, "SIGKILL"); finish(null); });
    child.stdout!.on("data", (chunk: Buffer) => {
      output += chunk.toString("utf8");
      if (Buffer.byteLength(output) > MAX_OUTPUT) { endCommand(child, "SIGKILL"); finish(null); }
    });
    child.on("error", () => finish(null));
    child.on("close", (code) => {
      if (code !== 0) return finish(null);
      const line = output.split(/\r?\n/).find((s) => s.startsWith(marker));
      try {
        const found: unknown = line ? JSON.parse(Buffer.from(line.slice(marker.length), "base64").toString("utf8")) : null;
        finish(Array.isArray(found) && found.every((p) => typeof p === "string") ? found : null);
      } catch {
        finish(null);
      }
    });
  });
}

function shellPath(shell: string, login: boolean, env: Env): Promise<string[] | null> {
  const clean = probeEnv(env);
  const key = createHash("sha256").update(JSON.stringify([shell, login, Object.entries(clean).sort(([a], [b]) => a.localeCompare(b))])).digest("hex");
  const now = wall.now();
  const known = readings.get(key);
  if (known && now - known.at < KEEP_MS) return known.value;
  const value = readShellPath(shell, login, clean);
  if (readings.size >= 32) readings.delete(readings.keys().next().value!);
  readings.set(key, { at: now, value });
  return value;
}

/// `lookup` can retain directory variables a login itself must not inherit. Existing PATH commands always win.
export async function withShellCommand(name: string, env: Env, lookup: Env = env): Promise<Env> {
  if (/[\\/]/.test(name) || platform.findCommand(name, env) !== null) return env;
  const shell = platform.userShell(lookup);
  if (!shell) return env;
  // A non-login interactive shell may read a different startup file from a login shell. Prefer what an ordinary
  // terminal uses, then try the login environment if the command was not there.
  for (const login of [false, true]) {
    const dirs = await shellPath(shell, login, lookup);
    if (dirs === null) continue;
    const candidate = dirs.reduceRight((e, dir) => platform.prependPath(e, dir), env);
    if (platform.findCommand(name, candidate) !== null) return candidate;
  }
  return env;
}
