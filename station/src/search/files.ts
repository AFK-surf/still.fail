// The machine's files found by a search (docs/search.md): on macOS what Spotlight has indexed of the whole machine, its
// files' names and what they say (asked as a search comes, `mdfind`); elsewhere the home's files walked as a search
// comes, for a few seconds, the nearest the top first (nothing is indexed). As the drive lends them: a member
// who may write finds the whole machine, a read-only one only the folders their workspace pinned; the station's own
// data is never found, and the person's own mail, messages, calendars, contacts, notes and photos only where the station
// says so (config.json `search.personal`).
import { spawn } from "node:child_process";
import { type Dirent } from "node:fs";
import { readFile, readdir, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, sep } from "node:path";
import { wall } from "../ops/fibers.ts";
import { platform } from "../platform/index.ts";
import { protectedTop } from "../drive/fs.ts";
import type { Asker, Group, Hit } from "./match.ts";

/// The home's folders macOS keeps from the station (drive/fs.ts `protectedTop`).
const PROTECTED = ["Documents", "Desktop", "Downloads"];
/// Where a Mac keeps its apps.
const APPS = ["/Applications", "/System/Applications"];
/// How long Spotlight has to answer, and how many paths it is let give before it is stopped; what files say is asked
/// for fewer (a common word is in a hundred thousand of them, each counted by Spotlight before it is given).
const WAIT_MS = 3_000;
const MOST = 1000;
const MOST_SAID = 100;
/// Words shorter than this are looked for at the start of names alone: `*u*` is in nearly every name on the machine.
export const SHORT = 3;
/// A search's files are found again only after this long: the same words asked at once by several of a person's
/// devices (as they connect again), or again and again by a client from before it let go of what it no longer shows,
/// are one search of the machine; a file made since is found a few seconds later.
export const KEPT_MS = 5_000;
/// Past this many searches of the machine a minute, one asked again is answered with what it found last (up to
/// STALE_MS old) rather than searched again; one not asked lately is searched all the same.
export const PER_MINUTE = 20;
export const STALE_MS = 10 * 60_000;

/// Where a Mac keeps what is the person's own (mail, messages, calendars, contacts, notes, photos), under the home.
export const PERSONAL = [
  "Library/Mail", "Library/Messages", "Library/Calendars", "Library/Application Support/AddressBook",
  "Library/Group Containers/group.com.apple.notes", "Library/Containers/com.apple.Notes", "Library/Metadata/CoreSpotlight",
  "Pictures/Photos Library.photoslibrary",
];

export type FileSearchDeps = {
  /// What no search may find (the station's own: ops/own.ts).
  protect(): string[];
  /// The folders a workspace pinned (null: the home one's).
  roots(workspace: string | null): string[];
  /// Whether the person's own mail, messages and the like may be found (config.json `search.personal`).
  personal(): boolean;
  home?: string;
  /// Spotlight's paths for a query, under `within` (none: anywhere), at most `most` (a test's own; null: walk the folders
  /// as where there is no Spotlight).
  spotlight?: ((query: string, within: string[], most: number, signal?: AbortSignal) => Promise<string[]>) | null;
  /// The time, as the walk's end is told by (a test's own).
  now?: () => number;
  /// The folders macOS keeps from the station (Documents, Desktop, Downloads), asked through still.fail Helper where it
  /// holds their grant: those it may search now (`tops`, of the folders asked), and its Spotlight there.
  helper?: { granted(tops: string[]): string[]; search(top: string, query: string, most: number, protect: string[]): Promise<string[]> } | null;
};

const under = (path: string, dir: string) => path === dir || path.startsWith(dir.endsWith(sep) ? dir : dir + sep);

/// A word as Spotlight's query language has it in a string: its quotes, backslashes and wildcards escaped.
const quoted = (word: string) => word.replace(/[\\"*?]/g, (c) => `\\${c}`);

/// Spotlight's query for the words: each in a name (any part of it; a SHORT word at its start), or (`content`) in a
/// name or what a file says (a word of it), case and diacritics aside. Null for what files say where every word is
/// short: nothing asked.
export function spotlightQuery(words: string[], content: false): string;
export function spotlightQuery(words: string[], content?: boolean): string | null;
export function spotlightQuery(words: string[], content = true): string | null {
  if (content && words.every((w) => w.length < SHORT)) return null;
  const name = (w: string) => (w.length < SHORT ? `kMDItemFSName == "${quoted(w)}*"cd` : `kMDItemFSName == "*${quoted(w)}*"cd`);
  return words.map((w) => (content && w.length >= SHORT ? `(${name(w)} || kMDItemTextContent == "${quoted(w)}*"cdw)` : name(w))).join(" && ");
}

/// What tools make and keep, never what a person looks for: a path through any of these is passed over.
const NOISE = new Set(["node_modules", ".git", "venv", ".venv", "site-packages", "dist-packages", "__pycache__", "target", "Pods", "DerivedData", ".cache", ".Trash", ".npm", ".pnpm-store", ".cargo", ".rustup", ".gradle", ".m2"]);
const noisy = (path: string, home: string) => {
  const parts = path.split(sep);
  if (parts.some((p) => NOISE.has(p) || p.endsWith(".app") && parts.indexOf(p) < parts.length - 1)) return true;
  // The home's Library: the apps' own (their caches and data), not the person's files.
  return under(path, join(home, "Library"));
};

/// `mdfind` asked: its paths as they come, stopped at `most` or after WAIT_MS.
export function mdfind(query: string, within: string[], most: number, signal?: AbortSignal): Promise<string[]> {
  return new Promise((resolve) => {
    if (signal?.aborted) return resolve([]);
    const args = ["-0", ...within.flatMap((w) => ["-onlyin", w]), query];
    const child = spawn("/usr/bin/mdfind", args, { stdio: ["ignore", "pipe", "ignore"] });
    const paths: string[] = [];
    let carry = "";
    let over = false;
    const done = () => {
      if (over) return;
      over = true;
      stop();
      child.kill();
      resolve(paths);
    };
    let stop = () => {};
    stop = wall.after(WAIT_MS, done);
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      const parts = (carry + chunk).split("\0");
      carry = parts.pop() ?? "";
      for (const p of parts) if (p !== "" && paths.length < most) paths.push(p);
      if (paths.length >= most) done();
    });
    child.on("error", done);
    child.on("close", done);
    signal?.addEventListener("abort", done, { once: true });
  });
}

// ── where there is no Spotlight: the folders walked as a search comes ──

/// Folders not gone into: what tools make and keep (dependencies, builds, caches, version control), the apps' own; and
/// the hidden ones.
const SKIPPED = new Set(["node_modules", "target", "dist", "build", ".git", "__pycache__", ".venv", "venv", "Pods", "DerivedData", ".cache", "Library", "AppData"]);
/// What of a file is read for its words: text, at most this much.
const TEXTS = /\.(md|markdown|txt|text|log|csv|tsv|json|jsonl|ya?ml|toml|ini|conf|cfg|xml|html?|css|scss|less|js|jsx|mjs|cjs|ts|tsx|py|rb|go|rs|java|kt|kts|swift|c|cc|cpp|h|hpp|cs|php|sh|bash|zsh|fish|ps1|sql|r|lua|pl|ex|exs|erl|hs|scala|clj|vue|svelte|tex|rst|org|srt|vtt)$/i;
const TEXT_MAX = 256 * 1024;
/// How long a walk may take.
export const WALK_MS = 3_000;

/// The files and folders under `tops` whose name has every word, or (a small text file) whose name and words have them:
/// a folder at a time, the nearest the top first, until `most` are found or `ms` is up (`left`: some were not reached).
export async function walk(tops: string[], words: string[], options: { skip: string[]; most: number; ms: number; now: () => number; signal?: AbortSignal }): Promise<{ paths: string[]; left: boolean }> {
  const until = options.now() + options.ms;
  const skipped = (p: string) => options.skip.some((d) => under(p, d));
  const has = (text: string) => {
    const lower = text.toLowerCase();
    return words.every((w) => lower.includes(w));
  };
  const folders = [...tops];
  const paths: string[] = [];
  while (folders.length > 0) {
    if (paths.length >= options.most) return { paths, left: true };
    if (options.now() > until || options.signal?.aborted) return { paths, left: true };
    const dir = folders.shift()!;
    let names: Dirent[];
    try {
      names = await readdir(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const d of names) {
      if (d.name.startsWith(".")) continue;
      const path = join(dir, d.name);
      if (skipped(path)) continue;
      if (d.isDirectory()) {
        if (!SKIPPED.has(d.name)) folders.push(path);
        if (has(d.name)) paths.push(path);
        continue;
      }
      if (!d.isFile()) continue;
      if (has(d.name)) {
        paths.push(path);
        continue;
      }
      if (!TEXTS.test(d.name)) continue;
      try {
        if ((await stat(path)).size > TEXT_MAX) continue;
        if (has(`${d.name}\n${await readFile(path, "utf8")}`)) paths.push(path);
      } catch {
        // Gone, or not readable: not found.
      }
    }
  }
  return { paths, left: false };
}

export class FileSearch {
  readonly #deps: FileSearchDeps;
  readonly #home: string;
  /// What searches found lately, by what they asked (KEPT_MS): the same asked again meanwhile is answered from it.
  readonly #found = new Map<string, { at: number; files: Promise<Group | null> }>();
  /// The search going now, and those waiting for it; one being typed (its words grown or shortened from the last of the
  /// same asker's) takes the place of the one before, which stops. `who`: the asker, `typed`: its words as one string.
  #going: { who: string; typed: string; stop: AbortController } | null = null;
  #waiting: { who: string; typed: string; go: () => void; drop: () => void }[] = [];
  #went: number[] = [];

  constructor(deps: FileSearchDeps) {
    this.#deps = deps;
    this.#home = deps.home ?? homedir();
  }

  /// The files the words find for `asker`: those whose name has the first word first, then the most recently changed.
  /// The same search within KEPT_MS is answered as it was; the machine is searched one search at a time, an asker's
  /// newer search in place of its older one, at most PER_MINUTE a minute (past it, what was found last).
  async query(words: string[], asker: Asker, limit: number): Promise<Group | null> {
    if (words.length === 0) return null;
    const now = this.#deps.now ?? (() => wall.now());
    const writer = asker.scopes.includes("write");
    const who = JSON.stringify([asker.workspace, asker.home, writer]);
    const key = JSON.stringify([words, who, limit, this.#deps.personal(), this.#deps.roots(asker.home ? null : asker.workspace)]);
    for (const [k, f] of this.#found) if (now() - f.at > STALE_MS) this.#found.delete(k);
    const kept = this.#found.get(key);
    this.#went = this.#went.filter((at) => now() - at < 60_000);
    if (kept && (now() - kept.at <= KEPT_MS || this.#went.length >= PER_MINUTE)) return kept.files;
    const files = this.#turn(who, words.join(" ")).then((stop) =>
      stop === null ? null : this.#search(words, asker, limit, stop.signal).then((found) => (stop.signal.aborted ? null : found)).finally(() => this.#next(stop)),
    );
    this.#found.set(key, { at: now(), files });
    // One stopped or passed over is not kept.
    void files.then((f) => {
      if (f === null && this.#found.get(key)?.files === files) this.#found.delete(key);
    });
    return files;
  }

  /// This asker's turn to search: its controller once it may go, null when a newer one of theirs took its place.
  #turn(who: string, typed: string): Promise<AbortController | null> {
    // The same words typed on: one starts as the other does (an agent's searches of other words each go).
    const before = (w: { who: string; typed: string }) => w.who === who && (typed.startsWith(w.typed) || w.typed.startsWith(typed));
    if (this.#going !== null && before(this.#going)) this.#going.stop.abort();
    return new Promise((resolve) => {
      const go = () => {
        const stop = new AbortController();
        this.#going = { who, typed, stop };
        this.#went.push((this.#deps.now ?? (() => wall.now()))());
        resolve(stop);
      };
      for (const w of this.#waiting.filter(before)) w.drop();
      this.#waiting = this.#waiting.filter((w) => !before(w));
      if (this.#going === null) go();
      else this.#waiting.push({ who, typed, go, drop: () => resolve(null) });
    });
  }

  #next(stop: AbortController) {
    if (this.#going?.stop !== stop) return;
    this.#going = null;
    this.#waiting.shift()?.go();
  }

  async #search(words: string[], asker: Asker, limit: number, signal: AbortSignal): Promise<Group | null> {
    const writer = asker.scopes.includes("write");
    const pinned = this.#deps.roots(asker.home ? null : asker.workspace);
    // A read-only member: only what their workspace pinned.
    if (!writer && pinned.length === 0) return null;
    const home = this.#home;
    const spotlight = this.#deps.spotlight === undefined ? (platform.hasSpotlight ? mdfind : null) : this.#deps.spotlight;
    const protect = this.#deps.protect();
    let asks: Promise<string[]>[];
    let left = false;
    if (spotlight !== null) {
      // Names under the home, what files there say, and the machine's apps by name; a read-only member's in what is
      // pinned. The folders macOS keeps from the station are asked of still.fail Helper instead, where it holds their
      // grant.
      const kept = (dirs: string[]) => dirs.filter((d) => protectedTop(d, home) !== null);
      const open = (dirs: string[]) => dirs.filter((d) => protectedTop(d, home) === null);
      const helper = this.#deps.helper ?? null;
      const guarded = writer ? PROTECTED.map((n) => join(home, n)) : kept(pinned);
      const viaHelper = helper ? helper.granted(guarded) : [];
      const said = spotlightQuery(words);
      asks = writer
        ? [spotlight(spotlightQuery(words, false), [home], MOST, signal), ...(said !== null ? [spotlight(said, [home], MOST_SAID, signal)] : []), spotlight(spotlightQuery(words, false), APPS, 50, signal)]
        : open(pinned).length > 0 ? [spotlight(said ?? spotlightQuery(words, false), open(pinned), MOST, signal)] : [];
      for (const top of viaHelper) asks.push(helper!.search(top, said ?? spotlightQuery(words, false), MOST_SAID, protect).catch(() => []));
    } else {
      const walked = await walk(writer ? [home] : pinned, words, { skip: protect, most: MOST, ms: WALK_MS, now: this.#deps.now ?? (() => wall.now()), signal });
      left = walked.left;
      asks = [Promise.resolve(walked.paths)];
    }
    const own = PERSONAL.map((d) => join(home, d));
    const personalOn = this.#deps.personal();
    // The person's own (under the home's Library) only where the station says so; the rest of that Library never.
    const found = [...new Set((await Promise.all(asks)).flat())].filter((p) => (personalOn && own.some((d) => under(p, d))) || !noisy(p, home));
    const personal = personalOn ? [] : own;
    const listed = found.filter((p) => !protect.some((d) => under(p, d)) && !personal.some((d) => under(p, d)) && (writer || pinned.some((r) => under(p, r))));
    const first = words[0]!;
    const named = (p: string) => basename(p).toLowerCase().includes(first);
    const known = await Promise.all(
      listed.map(async (path) => {
        try {
          const st = await stat(path);
          return { path, dir: st.isDirectory(), size: st.size, at: st.mtimeMs };
        } catch {
          return null;
        }
      }),
    );
    const files = known.filter((f): f is NonNullable<typeof f> => f !== null);
    // Those named so first, an app before a file; then the nearer the home's top, the latest.
    const app = (p: string) => p.endsWith(".app") && APPS.some((d) => under(p, d));
    const rank = (p: string) => (named(p) ? 0 : 4) + (app(p) ? 0 : 2);
    const depth = (p: string) => p.split(sep).length;
    files.sort((a, b) => rank(a.path) - rank(b.path) || depth(a.path) - depth(b.path) || b.at - a.at);
    const hits: Hit[] = files.slice(0, limit).map((f) => {
      const root = writer ? null : (pinned.find((r) => under(f.path, r)) ?? null);
      return {
        kind: "file", key: `f:${f.path}`, title: basename(f.path), text: this.#shown(dirname(f.path)), at: Math.round(f.at),
        path: f.path, ...(root !== null ? { root, rel: f.path.slice(root.length).replace(/^[\\/]+/, "") } : {}),
        dir: f.dir, size: f.size,
      };
    });
    return hits.length === 0 ? null : { kind: "file", hits, more: files.length > limit || left };
  }

  /// A folder as people read it: under the home from `~`.
  #shown(dir: string): string {
    return under(dir, this.#home) ? `~${dir.slice(this.#home.length)}` : dir;
  }
}
