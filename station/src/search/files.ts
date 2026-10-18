// The machine's files found by a search (docs/search.md): on macOS what Spotlight has indexed of the whole machine, its
// files' names and what they say (asked as a search comes, `mdfind`, never copied into the station's index); elsewhere
// what the station's own index has of the home's files (search/sources.ts `fileDocs`). As the drive lends them: a member
// who may write finds the whole machine, a read-only one only the folders their workspace pinned; the station's own
// data is never found, and the person's own mail, messages, calendars, contacts, notes and photos only where the station
// says so (config.json `search.personal`).
import { spawn } from "node:child_process";
import { stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, sep } from "node:path";
import { wall } from "../ops/fibers.ts";
import type { Asker, Group, Hit } from "./index.ts";

/// How long Spotlight has to answer, and how many paths it is let give before it is stopped.
const WAIT_MS = 3_000;
const MOST = 400;

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
  /// Spotlight's paths for a query, under `within` (none: anywhere), at most `most` (a test's own).
  spotlight?: (query: string, within: string[], most: number) => Promise<string[]>;
};

const under = (path: string, dir: string) => path === dir || path.startsWith(dir.endsWith(sep) ? dir : dir + sep);

/// A word as Spotlight's query language has it in a string: its quotes, backslashes and wildcards escaped.
const quoted = (word: string) => word.replace(/[\\"*?]/g, (c) => `\\${c}`);

/// Spotlight's query for the words: each in a name (any part of it) or in what a file says (a word of it), case and
/// diacritics aside.
export function spotlightQuery(words: string[]): string {
  return words.map((w) => `(kMDItemFSName == "*${quoted(w)}*"cd || kMDItemTextContent == "${quoted(w)}*"cdw)`).join(" && ");
}

/// `mdfind` asked: its paths as they come, stopped at `most` or after WAIT_MS.
export function mdfind(query: string, within: string[], most: number): Promise<string[]> {
  return new Promise((resolve) => {
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
  });
}

export class FileSearch {
  readonly #deps: FileSearchDeps;
  readonly #home: string;

  constructor(deps: FileSearchDeps) {
    this.#deps = deps;
    this.#home = deps.home ?? homedir();
  }

  /// Whether files are found this way here (Spotlight on macOS); elsewhere the station's index has them.
  static here(): boolean {
    return process.platform === "darwin";
  }

  /// The files the words find for `asker`: those whose name has the first word first, then the most recently changed.
  async query(words: string[], asker: Asker, limit: number): Promise<Group | null> {
    if (words.length === 0) return null;
    const writer = asker.scopes.includes("write");
    const pinned = this.#deps.roots(asker.home ? null : asker.workspace);
    // A read-only member: only what their workspace pinned.
    if (!writer && pinned.length === 0) return null;
    const ask = this.#deps.spotlight ?? mdfind;
    const found = await ask(spotlightQuery(words), writer ? [] : pinned, MOST);
    const protect = this.#deps.protect();
    const personal = this.#deps.personal() ? [] : PERSONAL.map((p) => join(this.#home, p));
    const kept = found.filter((p) => !protect.some((d) => under(p, d)) && !personal.some((d) => under(p, d)) && (writer || pinned.some((r) => under(p, r))));
    const first = words[0]!;
    const named = (p: string) => basename(p).toLowerCase().includes(first);
    const known = await Promise.all(
      kept.map(async (path) => {
        try {
          const st = await stat(path);
          return { path, dir: st.isDirectory(), size: st.size, at: st.mtimeMs };
        } catch {
          return null;
        }
      }),
    );
    const files = known.filter((f): f is NonNullable<typeof f> => f !== null);
    // Those named so first; then the home's, then the rest of the machine (its apps, its disks); the latest first.
    const rank = (p: string) => (named(p) ? 0 : 2) + (under(p, this.#home) ? 0 : 1);
    files.sort((a, b) => rank(a.path) - rank(b.path) || b.at - a.at);
    const hits: Hit[] = files.slice(0, limit).map((f) => {
      const root = writer ? null : (pinned.find((r) => under(f.path, r)) ?? null);
      return {
        kind: "file", key: `f:${f.path}`, title: basename(f.path), text: this.#shown(dirname(f.path)), at: Math.round(f.at),
        path: f.path, ...(root !== null ? { root, rel: f.path.slice(root.length).replace(/^[\\/]+/, "") } : {}),
        dir: f.dir, size: f.size,
      };
    });
    return hits.length === 0 ? null : { kind: "file", hits, more: files.length > limit };
  }

  /// A folder as people read it: under the home from `~`.
  #shown(dir: string): string {
    return under(dir, this.#home) ? `~${dir.slice(this.#home.length)}` : dir;
  }
}
