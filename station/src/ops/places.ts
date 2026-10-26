// The directories and files people and agents name for the station (a chat's directory continued from a terminal, a
// job's, a task's synced folder, a file attached to a message): looked at, and a file copied, without the station's own
// thread ever touching a folder macOS protects (drive/fs.ts `protectedPlace`, the drive's own classification;
// docs/drive.md "Folders macOS protects"). A station launchd runs that opens ~/Documents, ~/Desktop, ~/Downloads, a disk
// in /Volumes or iCloud Drive makes macOS put up a prompt for its launcher and hold the call until someone answers:
// the station's main thread stopped in `opendir`, the whole station silent (seen on studio, macOS 27).
//
// On macOS a path is walked here link by link with lstat, never stepping into such a folder: what is outside them is
// looked at as before (there, a folder, listable); what is in one (by its name or through a link) is asked of still.fail
// Helper (`files.stat`, a file copied with `files.read`), which holds the grants, or, where the helper has none for it
// (iCloud Drive), there is no helper, or the station itself must read it (`self`: a task's folder it syncs), of a child
// process given a few seconds (`TIMEOUT_MS`) and killed after them: a prompt then holds that process, not the station.
// A grant the helper lacks puts its window up on this Mac (helper/grants.ts: not again while it is up nor for a few
// minutes after, whoever asks) and refuses saying so; an agent is told to ask with the `permissions` tool. Elsewhere
// (Linux, Windows) a path is looked at directly, as before.
//
// The agents' own commands still run as the station's launcher does: macOS may keep them out of these folders, or
// prompt for them (docs/drive.md); only the station's own looking is kept off its thread here.
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { lstatSync, mkdirSync, readlinkSync, realpathSync, rmSync, statSync } from "node:fs";
import { homedir, hostname } from "node:os";
import { basename, join, resolve } from "node:path";
import type { Fs, Grant } from "../drive/fs.ts";
import { protectedPlace } from "../drive/fs.ts";
import { platform } from "../platform/index.ts";
import { type Lang, tr } from "./i18n.ts";
import { unreadableDir, unreadableDirMessage } from "./files.ts";
import { log } from "./log.ts";

/// How long the child process looking at a protected folder is given before it is killed.
export const TIMEOUT_MS = 5_000;

type Where = { top: string; helper: boolean };
/// What a look found: a folder the station may use (`real`: its links followed), or why not; `protected`: the walk
/// stopped at a folder macOS protects (`path`, links followed up to it), to be looked at elsewhere.
export type Look =
  | { state: "ok"; real: string }
  | { state: "gone" | "not_a_directory" | "denied" }
  | ({ state: "protected"; path: string } & Where);

type Code = "gone" | "not_a_directory" | "not_a_file" | "too_large" | "denied" | "grant" | "timeout";

/// Why a directory or file may not be used, in words for whoever asked (`code` for the callers that tell them apart;
/// `grant` and `window` when still.fail Helper lacks the grant for it).
export class PlaceRefused extends Error {
  readonly code: Code;
  readonly grant?: Grant;
  readonly window?: "up" | "closed" | "none";
  constructor(code: Code, message: string, extra: { grant?: Grant; window?: "up" | "closed" | "none" } = {}) {
    super(message);
    this.code = code;
    this.grant = extra.grant;
    this.window = extra.window;
  }
}

/// still.fail Helper's side Places needs (helper/files.ts HelperFiles).
export interface PlaceHelper {
  request(op: Record<string, unknown>): Promise<any>;
  ask(grant: Grant, top: string): Promise<"up" | "closed" | "none">;
  fs(scope: { roots: string[]; protect: string[] }): Fs;
}

/// How a child process runs `script` (CommonJS, `process.argv[1..]` its arguments), which writes its answer as JSON on
/// its last line.
export type Probe = { command: string; args: (script: string, argv: string[]) => string[]; env?: NodeJS.ProcessEnv };

/// The station's own Node.
export const nodeProbe: Probe = { command: process.execPath, args: (script, argv) => ["-e", script, ...argv] };

const codeOf = `const codeOf = (e) => e.code === "ENOENT" || e.code === "ENOTDIR" ? "gone" : e.code === "EPERM" || e.code === "EACCES" ? "denied" : "error";
const say = (o) => process.stdout.write(JSON.stringify(o) + "\\n");`;

/// A folder: there, a folder, listed; its real path.
const DIR_JS = `const fs = require("fs");
${codeOf}
const p = process.argv[1];
try {
  if (!fs.statSync(p).isDirectory()) say({ state: "not_a_directory" });
  else { fs.opendirSync(p).closeSync(); say({ state: "ok", real: fs.realpathSync(p) }); }
} catch (e) { say({ state: codeOf(e), error: String(e.message) }); }`;

/// A file copied to a new file (`to`), unless it is not one or is over `most` bytes.
const COPY_JS = `const fs = require("fs");
${codeOf}
const [, from, to, most] = process.argv;
try {
  const s = fs.statSync(from);
  if (!s.isFile()) say({ state: "not_a_file" });
  else if (s.size > Number(most)) say({ state: "too_large" });
  else { fs.copyFileSync(from, to, fs.constants.COPYFILE_EXCL); say({ state: "ok" }); }
} catch (e) { say({ state: codeOf(e), error: String(e.message) }); }`;

const parts = (path: string) => path.split("/").filter((p) => p !== "" && p !== ".");
const joined = (p: string[]) => `/${p.join("/")}`;

/// `path` walked link by link as the file system follows it, each step looked at with lstat on this thread, but none
/// at or under a folder `locked` names: there the walk stops (`protected`). At the end, being outside them all, it is
/// stated and listed (as `unreadableDir`).
export function walk(path: string, locked: (p: string) => Where | null): Look {
  const found = follow(path, locked);
  if (found.state !== "ok") return found;
  try {
    if (!statSync(found.real).isDirectory()) return { state: "not_a_directory" };
  } catch (e) {
    return { state: errState(e) };
  }
  return unreadableDir(found.real) ? { state: "denied" } : found;
}

/// `path` with its links followed as `walk` follows them (nothing at or under a folder `locked` names touched), not
/// looked at further.
export function follow(path: string, locked: (p: string) => Where | null): Look {
  let pending = parts(resolve(path));
  let done: string[] = [];
  let hops = 0;
  while (pending.length > 0) {
    const name = pending.shift()!;
    if (name === "..") {
      done.pop();
      continue;
    }
    const next = [...done, name];
    const at = joined(next);
    const place = locked(at);
    if (place !== null) return { state: "protected", path: joined([...next, ...pending]), ...place };
    let link: boolean;
    try {
      link = lstatSync(at).isSymbolicLink();
    } catch (e) {
      return { state: errState(e) };
    }
    if (!link) {
      done = next;
      continue;
    }
    if (++hops > 40) return { state: "gone" };
    const target = readlinkSync(at);
    // A relative target is followed from the link's folder (`..` in it as the system works it out).
    if (target.startsWith("/")) done = [];
    pending = [...parts(target), ...pending];
  }
  return { state: "ok", real: joined(done) };
}

/// `path` with its links followed, as realpath has it, on this thread: on macOS without stepping into a folder macOS
/// protects (one in such a folder is said as far as it was followed, by its name); null when it is not there.
export function realOutside(path: string, home = homedir()): string | null {
  if (!platform.hasFolderPermissions) {
    try {
      return realpathSync(path);
    } catch {
      return null;
    }
  }
  const found = follow(path, (p) => protectedPlace(p, home));
  if (found.state === "protected") return found.path;
  if (found.state !== "ok") return null;
  // Its links followed already, outside them all: as realpath names it (its case as the disk has it).
  try {
    return realpathSync(found.real);
  } catch {
    return null;
  }
}

const errState = (e: unknown): "gone" | "denied" => {
  const code = (e as NodeJS.ErrnoException).code;
  if (code === "EPERM" || code === "EACCES") return "denied";
  return "gone";
};

export type PlacesOptions = {
  /// Whether macOS's privacy protection applies here (default: the platform's).
  mac?: boolean;
  home?: string;
  /// still.fail Helper's files (null: no helper here).
  helper?: PlaceHelper | null;
  probe?: Probe;
  timeoutMs?: number;
  /// Told of each child process started (tests).
  started?: (pid: number) => void;
};

/// Who is told why a directory may not be used: a person (in their language) or an agent (in English, told what to do
/// about it). `self`: the station itself reads what is there (a task's folder it syncs), so still.fail Helper's grant
/// is no use: only the station's own access counts.
export type Asker = { lang: Lang; agent?: boolean; self?: boolean };

export class Places {
  readonly #mac: boolean;
  readonly #home: string;
  readonly #helper: PlaceHelper | null;
  readonly #probe: Probe;
  readonly #timeoutMs: number;
  readonly #started: ((pid: number) => void) | undefined;
  /// Looks under way, by path and how: one at a time for the same, whoever asks.
  readonly #looking = new Map<string, Promise<Look>>();

  constructor(options: PlacesOptions = {}) {
    this.#mac = options.mac ?? platform.hasFolderPermissions;
    this.#home = options.home ?? homedir();
    this.#helper = options.helper ?? null;
    this.#probe = options.probe ?? nodeProbe;
    this.#timeoutMs = options.timeoutMs ?? TIMEOUT_MS;
    this.#started = options.started;
  }

  /// Whether macOS's privacy protection applies here.
  get mac(): boolean {
    return this.#mac;
  }

  /// Whether `path` is in a folder macOS protects, by its name (nothing looked at).
  protects(path: string): boolean {
    return this.#mac && protectedPlace(path, this.#home) !== null;
  }

  /// `dir` as a folder something may start in: there, a folder, one the station may list (or, in a protected folder,
  /// still.fail Helper may), or refused (PlaceRefused) saying why in `asker`'s words. Its links followed where known.
  async directory(dir: string, asker: Asker): Promise<string> {
    if (!this.#mac) {
      const s = statSync(dir, { throwIfNoEntry: false });
      if (!s) throw this.#refused("gone", dir, asker);
      if (!s.isDirectory()) throw this.#refused("not_a_directory", dir, asker);
      if (unreadableDir(dir)) throw this.#refused("denied", dir, asker);
      return dir;
    }
    let look = walk(dir, (p) => protectedPlace(p, this.#home));
    if (look.state === "protected") {
      const at = look;
      look = await this.#once(`${asker.self ? "self" : "dir"}:${asker.agent ? "agent" : asker.lang}:${at.path}`, () => this.#protectedDir(at, dir, asker));
    }
    if (look.state === "ok") return look.real;
    throw this.#refused(look.state === "protected" ? "denied" : look.state, dir, asker);
  }

  /// A file (absolute) for the station to keep a copy of (a message's attachment): itself when it is outside the
  /// folders macOS protects (its caller looks at it as before); else copied into `into` (a new folder there, the same
  /// name) by still.fail Helper or a child process, at most `most` bytes, and that copy given, or refused saying why.
  async file(path: string, into: string, asker: Asker, most: number): Promise<string> {
    if (!this.#mac) return path;
    const where = this.#fileWhere(path);
    if (where === null) return path;
    const dir = join(into, `.stillfail-staged-${randomUUID()}`);
    mkdirSync(dir, { recursive: true });
    try {
      return await this.#copy(where, join(dir, basename(where.path)), path, asker, most);
    } catch (e) {
      rmSync(dir, { recursive: true, force: true });
      throw e;
    }
  }

  async #copy(where: { path: string } & Where, to: string, path: string, asker: Asker, most: number): Promise<string> {
    if (where.helper && this.#helper !== null && !asker.self) {
      const helper = this.#helper;
      const fs = helper.fs({ roots: [where.top], protect: [] });
      try {
        const s = await fs.stat(where.path);
        if (!s.file) throw this.#refused("not_a_file", path, asker);
        if (s.size > most) throw this.#refused("too_large", path, asker);
        await fs.copyTo(where.path, to);
        return to;
      } catch (e) {
        if (e instanceof PlaceRefused) throw e;
        const r = e as Error & { code?: string; grant?: Grant; top?: string };
        if (r.code === "grant" && r.grant) throw this.#needs(r.grant, r.top ?? where.top, await helper.ask(r.grant, r.top ?? where.top).catch(() => "none" as const), path, asker);
        if (r.code === "ENOENT" || r.code === "ENOTDIR") throw this.#refused("gone", path, asker);
        if (r.code === "EPERM" || r.code === "EACCES") throw this.#refused("denied", path, asker);
        log.warn("places", "still.fail Helper did not copy a file; copying it off the station's thread", { path, error: r.message });
      }
    }
    const answer = await this.#child(COPY_JS, [where.path, to, String(most)], path, asker);
    if (answer.state === "ok") return to;
    throw this.#refused(answer.state === "not_a_file" || answer.state === "too_large" || answer.state === "denied" ? answer.state : "gone", path, asker);
  }

  /// Where a file is, when that is in a protected folder: its folder walked (links followed outside them), its name.
  #fileWhere(path: string): ({ path: string } & Where) | null {
    const named = protectedPlace(path, this.#home);
    if (named !== null) return { path, ...named };
    const folder = follow(resolve(path, ".."), (p) => protectedPlace(p, this.#home));
    if (folder.state === "protected") return { ...folder, path: join(folder.path, basename(path)) };
    if (folder.state !== "ok") return null;
    // The file itself a link into one.
    const own = join(folder.real, basename(path));
    try {
      if (!lstatSync(own).isSymbolicLink()) return null;
    } catch {
      return null;
    }
    const target = resolve(folder.real, readlinkSync(own));
    const there = protectedPlace(target, this.#home);
    return there === null ? null : { path: target, ...there };
  }

  #once(key: string, look: () => Promise<Look>): Promise<Look> {
    const going = this.#looking.get(key);
    if (going) return going;
    const p = look().finally(() => this.#looking.delete(key));
    this.#looking.set(key, p);
    return p;
  }

  /// A folder in a protected folder: by still.fail Helper where it opens that folder (and the station itself need not),
  /// else by a child process.
  async #protectedDir(at: Extract<Look, { state: "protected" }>, dir: string, asker: Asker): Promise<Look> {
    if (at.helper && this.#helper !== null && !asker.self) {
      try {
        const s = await this.#helper.request({ op: "files.stat", path: at.path, follow: true, roots: [at.top], protect: [] });
        return s?.dir === true ? { state: "ok", real: at.path } : { state: "not_a_directory" };
      } catch (e) {
        const r = e as Error & { code?: string; grant?: Grant; top?: string };
        if (r.code === "grant" && r.grant) {
          const window = await this.#helper.ask(r.grant, r.top ?? at.top).catch(() => "none" as const);
          throw this.#needs(r.grant, r.top ?? at.top, window, dir, asker);
        }
        if (r.code === "ENOENT" || r.code === "ENOTDIR") return { state: "gone" };
        if (r.code === "EPERM" || r.code === "EACCES") return { state: "denied" };
        // The helper did not answer (it could not start, it ended): looked at the other way.
        log.warn("places", "still.fail Helper did not look at a directory; looking off the station's thread", { path: at.path, error: r.message });
      }
    }
    const answer = await this.#child(DIR_JS, [at.path], dir, asker);
    if (answer.state === "ok" && typeof answer.real === "string") return { state: "ok", real: answer.real };
    if (answer.state === "gone" || answer.state === "not_a_directory" || answer.state === "denied") return { state: answer.state };
    throw new Error(`couldn't check ${dir}: ${answer.error ?? "no answer"}`);
  }

  /// `script` run by a child process, killed after `timeoutMs` (a prompt of macOS's holds it, not the station): its
  /// answer; refused `timeout` when it did not give one in time.
  #child(script: string, argv: string[], named: string, asker: Asker): Promise<any> {
    return new Promise((done, fail) => {
      const child = execFile(this.#probe.command, this.#probe.args(script, argv), { timeout: this.#timeoutMs, killSignal: "SIGKILL", env: this.#probe.env ?? process.env }, (error, stdout) => {
        if (error && (error.killed || error.signal === "SIGKILL")) {
          log.warn("places", "a folder macOS protects did not answer in time", { path: argv[0], ms: this.#timeoutMs });
          fail(this.#refused("timeout", named, asker));
          return;
        }
        try {
          done(JSON.parse(String(stdout).trim().split("\n").at(-1) ?? ""));
        } catch {
          fail(new Error(`couldn't check ${named}: ${error?.message ?? "no answer"}`));
        }
      });
      if (child.pid !== undefined) this.#started?.(child.pid);
    });
  }

  #refused(code: Exclude<Code, "grant">, path: string, asker: Asker): PlaceRefused {
    const lang = asker.agent ? "en" : asker.lang;
    if (code === "denied") return new PlaceRefused(code, unreadableDirMessage(lang, path));
    if (code === "timeout") return new PlaceRefused(code, tr(lang, "station.place.timeout", { cwd: path, seconds: Math.ceil(this.#timeoutMs / 1000), machine: machine() }));
    const key = { gone: "station.place.gone", not_a_directory: "station.place.notDir", not_a_file: "station.place.notFile", too_large: "station.place.tooLarge" }[code];
    return new PlaceRefused(code, tr(lang, key, { cwd: path }));
  }

  #needs(grant: Grant, top: string, window: "up" | "closed" | "none", path: string, asker: Asker): PlaceRefused {
    const lang = asker.agent ? "en" : asker.lang;
    const key = window === "up" ? "station.place.grant" : window === "closed" ? "station.place.grantClosed" : "station.place.grantNone";
    const words = tr(lang, key, { folder: tr(lang, `station.helper.window.${grant}`), top, cwd: path, machine: machine() });
    const told = asker.agent
      ? `${words} Ask a person for it: call the permissions tool with request=${grant}, post what it says with chat_post kind=need_human and end your turn; try again once it is granted.`
      : words;
    return new PlaceRefused("grant", told, { grant, window });
  }
}

const machine = () => hostname().replace(/\.local$/, "");
