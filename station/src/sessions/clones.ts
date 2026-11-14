// Repositories cloned from git into the station's repository cache (`reposDir`), so a preset can name them: a member
// gives an address (POST /presets/clone), the clone runs in the background and its directory comes into the cache
// whole, as a candidate (presets.ts `candidates`), once it is done. Until then it is cloned into a dot-named directory
// there (`.cloning-<id>`), which nothing that lists the cache takes for a clone; one a station that stopped mid-clone
// left is removed as the next station's first clone starts. What is under way and what failed is kept in memory by
// workspace (GET /presets `clones`), every change told (`changed`) so devices read the presets again.
//
// git is run so that it never waits for a person: no terminal prompt, ssh in batch mode, no `ext::` or `file:`
// transport, the address after `--`, and a deadline; quietly, so that what it says is why it failed, not where it
// clones into and how far it is. An address's name and password (`https://user:token@…`) are
// used for the clone and kept nowhere: not in what is listed, not in an error, not in the log.
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdir, readFile, readdir, rename, rm, stat } from "node:fs/promises";
import { basename, join } from "node:path";
import { log } from "../ops/log.ts";
import { startEnv } from "../ops/agent-env.ts";
import { wall } from "../ops/fibers.ts";
import { type RepoIndex, originIn, repoName } from "./presets.ts";

/// A clone under way or failed, as GET /presets lists it.
export type Clone = { id: string; url: string; repo: string; name: string; state: "cloning" | "failed"; error?: string; by: string; startedAt: number };
/// What POST /presets/clone answers: the clone started (or the one under way of the same repository), or where the
/// station has that repository already.
export type CloneAnswer = Clone | { state: "there"; path: string; repo: string; name: string };

/// git run with `args` (and `env`), its end: whether it succeeded and what it said on stderr; `kill` stops it.
export type GitRun = (args: string[], env: NodeJS.ProcessEnv) => { done: Promise<{ ok: boolean; stderr: string }>; kill: () => void };

/// An address that is not one to clone (the route says so in the asker's words).
export class NoCloneUrl extends Error {
  constructor() {
    super("not a git address that can be cloned");
  }
}

/// How long a clone may take before it is stopped.
export const CLONE_MOST_MS = 30 * 60 * 1000;
/// At most so many kept by workspace (the oldest failed dropped first).
const KEPT_MOST = 20;
/// What of git's last words a failure keeps.
const ERROR_MOST = 300;
/// What of git's stderr is held while it runs (its end).
const STDERR_HELD = 8 * 1024;
const TEMP = ".cloning-";

/// git as a process: no terminal, ssh that never asks, stopped at the deadline.
export const runGit: GitRun = (args, env) => {
  const child = spawn("git", args, { env, stdio: ["ignore", "ignore", "pipe"] });
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (d: string) => {
    stderr = (stderr + d).slice(-STDERR_HELD);
  });
  let late = false;
  // timer: a deadline to a process (git given CLONE_MOST_MS at most)
  const stop = wall.after(CLONE_MOST_MS, () => {
    late = true;
    child.kill("SIGKILL");
  });
  const done = new Promise<{ ok: boolean; stderr: string }>((resolve) => {
    child.on("error", (e) => resolve({ ok: false, stderr: `${stderr}\n${e.message}` }));
    child.on("close", (code) => resolve({ ok: code === 0, stderr: late ? `${stderr}\ngit clone took longer than ${CLONE_MOST_MS / 60_000} minutes and was stopped` : stderr }));
  }).finally(stop);
  return { done, kill: () => void child.kill("SIGKILL") };
};

const PART = /^[A-Za-z0-9._-]+$/;

/// The address `given` is cloned from: http(s), ssh, git, scp's `user@host:path`, or `owner/name` (GitHub's). Refused
/// (NoCloneUrl): empty, an option (`-…`), a local path or `file:`, any other transport (`ext::`), a space or a control
/// character in it.
export function cloneUrl(given: unknown): string {
  const url = typeof given === "string" ? given.trim() : "";
  if (url === "" || url.startsWith("-") || /[\s\x00-\x1f\x7f]/.test(url)) throw new NoCloneUrl();
  const parts = url.split("/");
  if (parts.length === 2 && parts.every((p) => PART.test(p) && !/^\.+$/.test(p))) return `https://github.com/${parts[0]}/${parts[1]!.replace(/\.git$/, "")}.git`;
  const scheme = /^(https?|ssh|git):\/\/([^/?#]+)\/(.+)$/i.exec(url);
  if (scheme) {
    const host = scheme[2]!.replace(/^[^@]*@/, "");
    if (host === "" || host.startsWith("-")) throw new NoCloneUrl();
    return url;
  }
  // (scp's: a user, a host, a path after one colon)
  if (/^[A-Za-z0-9._-]+@[A-Za-z0-9][A-Za-z0-9.-]*:(?!:)\S+$/.test(url)) return url;
  throw new NoCloneUrl();
}

/// `url` without a password in it, and an http address without its name either (a token is often given as one).
export function safeUrl(url: string): string {
  return url.replace(/^(https?:\/\/)[^/@]*@/i, "$1").replace(/^([a-z][a-z0-9+.-]*:\/\/[^/:@]*):[^/@]*@/i, "$1@");
}

/// `text` with no address's name and password in it.
function scrubbed(text: string): string {
  return text.replace(/([a-z][a-z0-9+.-]*:\/\/)[^\s/@]+@/gi, "$1");
}

/// What a failed clone says: git's last lines that say something, at most ERROR_MOST characters.
function errorOf(stderr: string): string {
  const lines = scrubbed(stderr).split(/\r?\n|\r/).map((l) => l.trim()).filter((l) => l !== "");
  let out = "";
  for (let i = lines.length - 1; i >= 0; i--) {
    const next = out === "" ? lines[i]! : `${lines[i]}\n${out}`;
    if (next.length > ERROR_MOST) {
      if (out === "") out = lines[i]!.slice(-ERROR_MOST);
      break;
    }
    out = next;
  }
  return out || "git clone failed";
}

/// A directory's name for repository `repo` (`host/owner/name`): its last part, as a name the cache shows.
function dirName(part: string): string {
  const name = part.replace(/[^A-Za-z0-9._-]/g, "-").replace(/^\.+/, "");
  return name === "" ? "repo" : name;
}

type Held = Clone & { kill?: () => void; dropped?: boolean; changed: () => void };

export class Clones {
  readonly reposDir: () => string;
  readonly now: () => number;
  readonly index: RepoIndex | null;
  readonly run: GitRun;
  /// By workspace (`""` for none), oldest first.
  #held = new Map<string, Held[]>();
  /// The leftovers of a station that stopped mid-clone, removed as the first clone starts.
  #swept: Promise<void> | null = null;

  constructor(o: { reposDir: () => string; now: () => number; index?: RepoIndex | null; run?: GitRun }) {
    this.reposDir = o.reposDir;
    this.now = o.now;
    this.index = o.index ?? null;
    this.run = o.run ?? runGit;
  }

  /// The clones under way and failed of workspace `ws`, newest first.
  list(ws: string | null): Clone[] {
    return [...(this.#held.get(ws ?? "") ?? [])].reverse().map(shown);
  }

  /// `given` cloned into the cache for workspace `ws` by `by`, answered at once: where the cache or the machine has the
  /// repository already, the clone of it under way, or the one started; `changed` told as it goes.
  async start(ws: string | null, given: unknown, by: string, changed: () => void = () => {}): Promise<CloneAnswer> {
    const url = cloneUrl(given);
    const kept = safeUrl(url);
    const repo = repoName(kept);
    const there = await this.#there(repo, changed);
    if (there !== null) return { state: "there", path: there, repo, name: basename(there) };
    const key = ws ?? "";
    const all = this.#held.get(key) ?? [];
    const running = all.find((c) => c.repo === repo && c.state === "cloning");
    if (running) return shown(running);
    // (one of it that failed: this one in its place)
    const rest = all.filter((c) => c.repo !== repo);
    while (rest.length >= KEPT_MOST) {
      const failed = rest.findIndex((c) => c.state === "failed");
      if (failed < 0) break;
      rest.splice(failed, 1);
    }
    const parts = repo.split("/");
    const clone: Held = { id: `c-${randomBytes(5).toString("hex")}`, url: kept, repo, name: dirName(parts.at(-1) ?? repo), state: "cloning", by, startedAt: this.now(), changed };
    this.#held.set(key, [...rest, clone]);
    log.info("presets", "clone started", { id: clone.id, repo, by });
    changed();
    void this.#clone(clone, url, dirName(parts.at(-2) ?? "")).catch((e) => this.#failed(clone, (e as Error).message));
    return shown(clone);
  }

  /// Clone `id` of workspace `ws` forgotten, stopped first if it is under way; false for none.
  drop(ws: string | null, id: string): boolean {
    const key = ws ?? "";
    const all = this.#held.get(key) ?? [];
    const clone = all.find((c) => c.id === id);
    if (!clone) return false;
    this.#held.set(key, all.filter((c) => c !== clone));
    clone.dropped = true;
    clone.kill?.();
    log.info("presets", clone.state === "cloning" ? "clone stopped" : "clone dropped", { id, repo: clone.repo });
    clone.changed();
    return true;
  }

  /// Where the station has repository `repo` already: a clone in the cache, or one found on the machine.
  async #there(repo: string, changed: () => void): Promise<string | null> {
    const dir = this.reposDir();
    for (const name of await readdir(dir).catch(() => [] as string[])) {
      if (name.startsWith(".")) continue;
      const config = await readFile(join(dir, name, ".git", "config"), "utf8").catch(() => "");
      if (config !== "" && originIn(config) === repo) return join(dir, name);
    }
    const found = this.index ? await this.index.repos(changed).catch(() => []) : [];
    return found.find((c) => c.repo === repo)?.path ?? null;
  }

  async #clone(clone: Held, url: string, owner: string): Promise<void> {
    const dir = this.reposDir();
    await mkdir(dir, { recursive: true });
    await (this.#swept ??= this.#sweep(dir));
    if (clone.dropped) return;
    const temp = join(dir, `${TEMP}${clone.id}`);
    // (the agents' variables over the station's own, as everything it starts for them has: the proxy the machine's
    // network needs, a token a member set for them; an agent cloning the same repository would reach it the same way)
    const env = { ...startEnv(), GIT_TERMINAL_PROMPT: "0", GIT_SSH_COMMAND: "ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new" };
    const run = this.run(["-c", "protocol.ext.allow=never", "-c", "protocol.file.allow=never", "clone", "--quiet", "--", url, temp], env);
    clone.kill = run.kill;
    const { ok, stderr } = await run.done;
    clone.kill = undefined;
    if (!ok || clone.dropped) {
      await rm(temp, { recursive: true, force: true }).catch(() => {});
      if (!clone.dropped) this.#failed(clone, stderr);
      return;
    }
    const path = await this.#place(temp, dir, clone.name, owner).catch(() => null);
    if (path === null) {
      await rm(temp, { recursive: true, force: true }).catch(() => {});
      this.#failed(clone, "the clone could not be put in the repository cache");
      return;
    }
    this.#forget(clone);
    log.info("presets", "clone done", { id: clone.id, repo: clone.repo, path });
    clone.changed();
  }

  /// `temp` moved to `dir/<name>`, or where that is taken `dir/<owner>-<name>`, then `-2`, `-3`…: where it went.
  async #place(temp: string, dir: string, name: string, owner: string): Promise<string | null> {
    const base = owner === "" ? name : `${owner}-${name}`;
    for (let i = 0; i < 100; i++) {
      const to = join(dir, i === 0 ? name : i === 1 ? base : `${base}-${i}`);
      if (await stat(to).then(() => true, () => false)) continue;
      try {
        await rename(temp, to);
        return to;
      } catch (e) {
        const code = (e as NodeJS.ErrnoException).code;
        if (code !== "EEXIST" && code !== "ENOTEMPTY") throw e;
      }
    }
    return null;
  }

  /// Clone `clone` failed, git's (or the station's) words `said`.
  #failed(clone: Held, said: string): void {
    if (clone.dropped || clone.state === "failed") return;
    clone.state = "failed";
    clone.error = errorOf(said);
    log.info("presets", "clone failed", { id: clone.id, repo: clone.repo, error: clone.error });
    clone.changed();
  }

  #forget(clone: Held): void {
    for (const [key, all] of this.#held) if (all.includes(clone)) this.#held.set(key, all.filter((c) => c !== clone));
  }

  async #sweep(dir: string): Promise<void> {
    const left = (await readdir(dir).catch(() => [] as string[])).filter((n) => n.startsWith(TEMP));
    await Promise.all(left.map((n) => rm(join(dir, n), { recursive: true, force: true }).catch(() => {})));
    if (left.length > 0) log.info("presets", "unfinished clones removed", { count: left.length });
  }
}

function shown(c: Held): Clone {
  return { id: c.id, url: c.url, repo: c.repo, name: c.name, state: c.state, ...(c.error !== undefined ? { error: c.error } : {}), by: c.by, startedAt: c.startedAt };
}
