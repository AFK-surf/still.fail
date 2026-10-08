// The changelog people read in the apps (docs/changelog.md), from main's history: each commit's `Changelog:` trailers
// (a line for people, in Chinese) and `Fixes: FB-<n>` (the bug reports it fixes), with the version it came in (the
// commits up to it: 0.1.<n>, as every part numbers its builds) and the parts it reached by the files it changed (partsOf).
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

// Each file reaches the parts of the first of these it is under.
const PARTS: [RegExp, Part[]][] = [
  // The station: station/ (src/ and its native parts; not its tests), and mesh/ in the history before it (the Rust one).
  [/^station\/(src|native)\/|^mesh\//, ["station"]],
  // Android's native shell (the web's iroh, client/iroh-wasm, is among what Android does not carry).
  [/^client\/(shell\/|Cargo\.)/, ["android"]],
  // The core, which every app carries; but what apps/android/not-carried.txt says the Android app does not.
  [/^client\//, ["web", "android"]],
  [/^web\//, ["web"]],
  [/^apps\/android\//, ["android"]],
  [/^apps\/desktop\//, ["desktop"]],
  [/^cloud\/src\//, ["cloud"]],
];

// What changes no app by itself: tests, the lists of what the Android app carries, and the types the clients read
// (client/core-ts/src/shapes/schema.ts, and the bindings made from it), which change with the code that fills them.
const CHANGES_NOTHING =
  /^client\/core-ts\/(test|bench|harness|side)\/|^apps\/android\/[^/]+\/src\/(androidTest|test)\/|^apps\/android\/(carries\.sh|not-carried\.txt)$|^client\/core-ts\/src\/shapes\/schema\.ts$|^web\/src\/core\/(shapes|operations)\.ts$|^apps\/android\/.*\/data\/(Shapes|Operations)\.kt$/;

// The words people read (client/i18n/catalog/<language>/<part>[-…].json). The core carries them all into every app,
// but they reach people where the code that says them does: a commit that changes code as well reaches only what its
// code reaches (a desktop feature's words are no news on Android); one of words alone, the parts they are named for.
const WORDS = /^client\/i18n\/catalog\/[^/]+\/([a-z]+)[^/]*\.json$/;
const SAID_IN: Record<string, Part[]> = {
  android: ["android"],
  web: ["web"],
  desktop: ["desktop"],
  station: ["station"],
  cloud: ["cloud"],
  core: ["android", "web"],
  common: ["android", "web"],
};

/**
 * The parts a commit's files reach (`notCarried`: the paths apps/android/not-carried.txt names). A commit that by itself
 * changes nothing anyone uses (its tests, say, carrying the line for the commits before it) reaches where its files are.
 */
export function partsOf(files: string[], notCarried: RegExp | null = null): Part[] {
  const reach = (file: string) => PARTS.find(([path]) => path.test(file))?.[1] ?? [];
  const code = new Set<Part>();
  const words = new Set<Part>();
  for (const file of files) {
    const said = WORDS.exec(file)?.[1];
    if (said !== undefined) for (const part of SAID_IN[said] ?? []) words.add(part);
    else if (!CHANGES_NOTHING.test(file)) for (const part of reach(file)) if (part !== "android" || !notCarried?.test(file)) code.add(part);
  }
  if (!code.size && !words.size) for (const file of files) for (const part of reach(file)) code.add(part);
  return [...(code.size ? code : words)].sort();
}

/** apps/android/not-carried.txt's paths, as one expression (null: there is none). */
export function readNotCarried(root: string): RegExp | null {
  const file = join(root, "apps/android/not-carried.txt");
  const paths = existsSync(file) ? readFileSync(file, "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#")) : [];
  return paths.length ? new RegExp(paths.join("|")) : null;
}

const TRAILER = /^([A-Za-z][A-Za-z0-9-]*):\s*(.*)$/;

/**
 * A commit's message: the changelog's lines and the fixes in its trailers, from every paragraph after the subject that is
 * only trailers (each line `Key: value`, or one indented to fold the line before on). git takes the last such paragraph
 * alone for the trailers, which lost every `Changelog:` written above a blank line and `Co-Authored-By:` (37 commits from
 * 2026-10-01 to 10-08: their changes were in the apps, and nothing said so).
 */
export function readMessage(message: string): { text: string[]; fixes: number[] } {
  const text: string[] = [];
  const fixes: number[] = [];
  for (const paragraph of message.split("\n").slice(1).join("\n").split(/\n[ \t]*\n/)) {
    const lines = paragraph.split("\n").filter((l) => l.trim());
    if (!lines.length || !lines.every((l, i) => TRAILER.test(l) || (i > 0 && /^\s/.test(l)))) continue;
    for (const line of lines.join("\n").replace(/\n\s+/g, " ").split("\n")) {
      const [, key, value] = TRAILER.exec(line)!;
      if (/^changelog$/i.test(key!) && value!.trim()) text.push(value!.trim());
      if (/^fixes$/i.test(key!)) for (const fb of value!.matchAll(/FB-?(\d+)/gi)) fixes.push(Number(fb[1]));
    }
  }
  return { text, fixes };
}

type Notes = Record<string, { text?: string[]; fixes?: number[] }>;

export function changelog(root: string, rev = "HEAD"): Entry[] {
  const git = (...args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  const notesFile = join(root, "docs/changelog-notes.json");
  const notes: Notes = existsSync(notesFile) ? JSON.parse(readFileSync(notesFile, "utf8")) : {};
  const notCarried = readNotCarried(root);
  // Newest first, one record a commit: its hash, time and message, then its files.
  const log = git("log", "--first-parent", "--diff-merges=first-parent", "--name-only", "--format=%x1e%H%x1f%ct%x1f%B%x1f", rev);
  const entries: Entry[] = [];
  for (const record of log.split("\x1e").slice(1)) {
    const [commit, at, message, rest] = record.split("\x1f") as [string, string, string, string];
    const said = readMessage(message);
    const note = Object.entries(notes).find(([start]) => start.length >= 7 && commit.startsWith(start))?.[1];
    const text = note?.text ?? said.text;
    const fixes = [...new Set([...said.fixes, ...(note?.fixes ?? [])])];
    if (!text.length && !fixes.length) continue;
    // Counted for each (early history has merges, so its place in this list is not its number).
    const version = Number(git("rev-list", "--count", commit).trim());
    entries.push({ version, commit, at: Number(at), text, fixes, parts: partsOf(rest.split("\n").filter(Boolean), notCarried) });
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
