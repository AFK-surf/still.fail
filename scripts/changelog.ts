// The changelog people read in the apps (docs/changelog.md), from main's history: each commit's `Changelog:` trailers
// (a line for people, in Chinese) and `Fixes: FB-<n>` (the bug reports it fixes), with the version it came in (the
// commits up to it: 0.1.<n>, as every part numbers its builds) and the parts it reached by the files it changed.
// docs/changelog-notes.json adds lines to commits from before, or says one again: { "<commit or its start>": { "text":
// [...], "fixes": [...] } }.
//   node scripts/changelog.ts [rev]   the entries as JSON, newest first (CI puts them in the releases bucket)
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/** Where a change reaches people: the station, the web app (and the desktop app, which carries it), the Android app, the desktop app's own shell, or still.fail cloud (live as it deploys). */
export type Part = "station" | "web" | "android" | "desktop" | "cloud";

export interface Entry {
  /** The commits up to it: what each part's build number is. */
  version: number;
  commit: string;
  /** When it was committed, seconds. */
  at: number;
  text: string[];
  /** The bug reports it fixes (FB-<n>). */
  fixes: number[];
  /** Empty: it needs no release (the site, the docs). */
  parts: Part[];
}

const PARTS: [RegExp, Part[]][] = [
  [/^mesh\//, ["station"]],
  [/^client\//, ["web", "android"]],
  [/^web\//, ["web"]],
  [/^apps\/android\//, ["android"]],
  [/^apps\/desktop\//, ["desktop"]],
  [/^cloud\/src\//, ["cloud"]],
];

/** The parts a commit's files reach. */
export function partsOf(files: string[]): Part[] {
  const parts = new Set<Part>();
  for (const file of files) for (const [path, reached] of PARTS) if (path.test(file)) reached.forEach((p) => parts.add(p));
  return [...parts].sort();
}

/** A commit's trailers as `git log --format=%(trailers:unfold,only)` gives them: the changelog's lines and the fixes. */
export function readTrailers(trailers: string): { text: string[]; fixes: number[] } {
  const text: string[] = [];
  const fixes: number[] = [];
  for (const line of trailers.split("\n")) {
    const m = /^([A-Za-z-]+):\s*(.*)$/.exec(line.trim());
    if (!m) continue;
    const [, key, value] = m;
    if (/^changelog$/i.test(key!) && value!.trim()) text.push(value!.trim());
    if (/^fixes$/i.test(key!)) for (const fb of value!.matchAll(/FB-?(\d+)/gi)) fixes.push(Number(fb[1]));
  }
  return { text, fixes };
}

type Notes = Record<string, { text?: string[]; fixes?: number[] }>;

export function changelog(root: string, rev = "HEAD"): Entry[] {
  const git = (...args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  const notesFile = join(root, "docs/changelog-notes.json");
  const notes: Notes = existsSync(notesFile) ? JSON.parse(readFileSync(notesFile, "utf8")) : {};
  // Newest first, one record a commit: its hash, time and trailers, then its files.
  const log = git("log", "--first-parent", "--diff-merges=first-parent", "--name-only", "--format=%x1e%H%x1f%ct%x1f%(trailers:unfold,only)%x1f", rev);
  const entries: Entry[] = [];
  for (const record of log.split("\x1e").slice(1)) {
    const [commit, at, trailers, rest] = record.split("\x1f") as [string, string, string, string];
    const said = readTrailers(trailers);
    const note = Object.entries(notes).find(([start]) => start.length >= 7 && commit.startsWith(start))?.[1];
    const text = note?.text ?? said.text;
    const fixes = [...new Set([...said.fixes, ...(note?.fixes ?? [])])];
    if (!text.length && !fixes.length) continue;
    // Counted for each (early history has merges, so its place in this list is not its number).
    const version = Number(git("rev-list", "--count", commit).trim());
    entries.push({ version, commit, at: Number(at), text, fixes, parts: partsOf(rest.split("\n").filter(Boolean)) });
  }
  return entries;
}

if (import.meta.main) {
  console.log(JSON.stringify(changelog(join(import.meta.dirname, ".."), process.argv[2] ?? "HEAD")));
}
