// The changelog people read in the apps (docs/changelog.md), from main's history: each commit's `Changelog:` trailers
// (a line for people, in Chinese) and `Fixes: FB-<n>` (the bug reports it fixes), with the version it came in (the
// commits up to it: 0.1.<n>, as every part numbers its builds) and the parts it reached by the files it changed.
// docs/changelog-notes.json adds lines to commits from before, or says one again: { "<commit or its start>": { "text":
// [...], "fixes": [...] } }.
// That is the test channel's. The stable channel's is written once a release, for people who skip the steps between:
// docs/releases/0.1.<n>.md, which an agent drafts from the test channel's entries since the last one (--draft) and a
// person reads before the release goes out (docs/changelog.md).
//   node scripts/changelog.ts [rev]           the test channel's entries as JSON, newest first (CI: changelog.json)
//   node scripts/changelog.ts --stable        the stable channel's, one entry a release (CI: changelog-stable.json)
//   node scripts/changelog.ts --draft [rev]   what the next release's notes are written from: the test channel's
//                                             entries since the last release's, oldest first, as text
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
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

/**
 * The stable channel's notes, newest first: one entry a release, from docs/releases/0.1.<n>.md. Its front matter says
 * `version: <n>` (the commit every part of the release was built at or after: the apps say whether they have it by
 * it), `date: YYYY-MM-DD` and `parts` (what the release brought out); its lines (`- …`) are the text. Its fixes are the
 * test channel's between the release before and it (the reports are marked fixed by those, not by these).
 */
export function stable(root: string, beta: Entry[] = []): Entry[] {
  const dir = join(root, "docs/releases");
  const releases = (existsSync(dir) ? readdirSync(dir) : [])
    .filter((f) => /^0\.1\.\d+\.md$/.test(f))
    .map((f) => readRelease(readFileSync(join(dir, f), "utf8"), f))
    .sort((a, b) => b.version - a.version);
  return releases.map((release, i) => {
    const after = releases[i + 1]?.version ?? 0;
    const fixes = [...new Set(beta.filter((e) => e.version > after && e.version <= release.version).flatMap((e) => e.fixes))].sort((a, b) => a - b);
    return { ...release, fixes };
  });
}

export function readRelease(file: string, name = "release"): Entry {
  const m = /^---\n([\s\S]*?)\n---\n?([\s\S]*)$/.exec(file);
  if (!m) throw new Error(`${name}: no front matter (--- version, date, parts ---)`);
  const field = (key: string) => new RegExp(`^${key}:\\s*(.+)$`, "m").exec(m[1]!)?.[1]?.trim();
  const version = Number(field("version"));
  const date = field("date") ?? "";
  if (!Number.isSafeInteger(version) || version <= 0) throw new Error(`${name}: version: <the commits up to the release>`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error(`${name}: date: YYYY-MM-DD`);
  const parts = (field("parts") ?? "").replace(/[[\]]/g, "").split(/[,\s]+/).filter(Boolean) as Part[];
  const known: Part[] = ["station", "web", "android", "desktop", "cloud"];
  const unknown = parts.filter((p) => !known.includes(p));
  if (unknown.length || !parts.length) throw new Error(`${name}: parts: some of ${known.join(", ")}`);
  const text = m[2]!.split("\n").map((l) => /^\s*-\s+(.+)$/.exec(l)?.[1]?.trim()).filter((l): l is string => !!l);
  if (!text.length) throw new Error(`${name}: no lines (- …)`);
  // Noon in Beijing on its day: the apps group by day.
  const at = Math.round(Date.parse(`${date}T12:00:00+08:00`) / 1000);
  return { version, commit: "", at, text, fixes: [], parts: [...new Set(parts)].sort() };
}

/** The next release's notes are written from these: the test channel's entries after the last release's, oldest first. */
export function draft(root: string, rev = "HEAD"): string {
  const beta = changelog(root, rev);
  const last = stable(root)[0]?.version ?? 0;
  const head = Number(execFileSync("git", ["rev-list", "--count", rev], { cwd: root, encoding: "utf8" }).trim());
  const lines = beta.filter((e) => e.version > last).reverse().map((e) => `0.1.${e.version} [${e.parts.join(",") || "-"}]${e.fixes.length ? ` FB-${e.fixes.join(",FB-")}` : ""}\n${e.text.map((t) => `  ${t}`).join("\n")}`);
  return `# The test channel's changes since the last release (0.1.${last}), up to 0.1.${head}\n\n${lines.join("\n")}\n`;
}

if (import.meta.main) {
  const root = join(import.meta.dirname, "..");
  const [flag, rev] = process.argv[2]?.startsWith("--") ? [process.argv[2], process.argv[3]] : [undefined, process.argv[2]];
  if (flag === "--stable") console.log(JSON.stringify(stable(root, changelog(root, rev ?? "HEAD"))));
  else if (flag === "--draft") process.stdout.write(draft(root, rev ?? "HEAD"));
  else console.log(JSON.stringify(changelog(root, rev ?? "HEAD")));
}
