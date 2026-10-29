// The changelog people read in the apps (docs/changelog.md), from main's history: each commit's `Changelog:` trailers
// (a line for people, in Chinese) and `Fixes: FB-<n>` (the bug reports it fixes), with the version it came in (the
// commits up to it: 0.1.<n>, as every part numbers its builds) and the parts people see it in, as its agent says
// (`Changelog-parts:`; one from before that did not, by the files it changed: partsOf). docs/changelog-notes.json adds
// lines to commits from before, or says one again: { "<commit or its start>": { "text": [...], "fixes": [...], "parts":
// [...] } }.
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

/** Where a change reaches people: the station, the web app (and the Electron desktop app, which carries it), the Android app, the desktop app's own (the Electron app's shell, mbui's desktop app), or still.fail cloud (live as it deploys). */
export type Part = "station" | "web" | "android" | "desktop" | "cloud";
const PART_NAMES: readonly string[] = ["station", "web", "android", "desktop", "cloud"] satisfies Part[];
const isPart = (name: string): name is Part => PART_NAMES.includes(name);

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

// For a commit that does not say its parts (those from before they were said), each file reaches the parts of the first
// of these it is under.
const PARTS: [RegExp, Part[]][] = [
  // The station: station/ (src/ and its native parts; not its tests), and mesh/ in the history before it (the Rust one).
  [/^station\/(src|native)\/|^mesh\//, ["station"]],
  // Android's native shell (the web's iroh, client/iroh-wasm, is among what Android does not carry).
  [/^client\/(shell\/|Cargo\.)/, ["android"]],
  // The core, which every app carries; but what client/core-ts/scripts/not-carried.txt says the apps do not.
  [/^client\//, ["web", "android"]],
  [/^web\//, ["web"]],
  [/^apps\/android\//, ["android"]],
  [/^apps\/desktop\//, ["desktop"]],
  // still.fail's mbui app (apps/mbui, mbui itself in apps/mbui/mbui): the Android app since 2026-10-23 (the Kotlin one,
  // apps/android, before it), and the desktop app, in the Electron one's place since 2026-10-26 (it tells the core it is
  // "desktop"). What one platform's host alone builds reaches that platform (iOS is no part yet); the desktop's own
  // pages (src/sfdesk, and what sfapp still has of them: its wide frame, the menu bar, the settings ported from the
  // web's) the desktop.
  [/^apps\/mbui\/((mbui\/)?ios\/|(mbui\/)?src\/host\/ios_)/, []],
  [/^apps\/mbui\/((mbui\/|engine\/)?android\/|(mbui\/)?src\/host\/android_)/, ["android"]],
  [/^apps\/mbui\/((mbui\/)?src\/host\/(apple|mac_|win|electron_)|src\/sfdesk\/|src\/sfapp\/((strings_)?wide|menu_bar|preview_desk|settings\/(web|desk)_))/, ["desktop"]],
  [/^apps\/mbui\//, ["android", "desktop"]],
  [/^cloud\/src\//, ["cloud"]],
];

// What changes no app by itself: tests, the lists of what the Android app carries, and the types the clients read
// (client/core-ts/src/shapes/schema.ts, and the bindings made from it), which change with the code that fills them;
// the core's scripts (what they make is in its src/); mbui's tests, fixtures, tapes, kept answers, films, demos, tools
// and docs.
const CHANGES_NOTHING = new RegExp(
  [
    /^client\/core-ts\/(test|bench|harness|side|scripts)\//,
    /^apps\/android\/[^/]+\/src\/(androidTest|test)\/|^apps\/android\/(carries\.sh|not-carried\.txt)$/,
    /^client\/core-ts\/src\/shapes\/schema\.ts$|^web\/src\/core\/(shapes|operations)\.ts$|^apps\/android\/.*\/data\/(Shapes|Operations)\.kt$/,
    /^apps\/mbui\/(mbui\/)?([^/]+|(e2e|docs|screens|scripts|tools|bench|goldens|test|web)\/.*)$/,
    /^apps\/mbui\/src\/(sffilm|sfreplay|sffix|sfkept|sfkit|sflayout|sfscreens|coredemo|books|photos|videos)\//,
    /^apps\/mbui\/mbui\/src\/(\w*demo|effecttest|awly|film|textdiff)\//,
    /^apps\/mbui\/.*(_test|_wbtest|_fixture|\/fixture)\.mbt$|^apps\/mbui\/core\/(.*[_-]test\.(m|js)|smoke\.m)$/,
  ].map((r) => r.source).join("|"),
);

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
 * The parts a commit's files reach (`notCarried`: the paths client/core-ts/scripts/not-carried.txt names). A commit that by itself
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

/** client/core-ts/scripts/not-carried.txt's paths, as one expression (null: there is none). */
export function readNotCarried(root: string): RegExp | null {
  const file = join(root, "client/core-ts/scripts/not-carried.txt");
  const paths = existsSync(file) ? readFileSync(file, "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#")) : [];
  return paths.length ? new RegExp(paths.join("|")) : null;
}

const TRAILER = /^([A-Za-z][A-Za-z0-9-]*):\s*(.*)$/;
// `Changelog: none` and the like, refused by the commit-msg hook and CI (`--refuse`): a commit with nothing to tell writes
// no Changelog line (67e764d3 and 3 others put "none" in the update bubble).
const NOTHING = /^(none|n\/?a|nothing|无|没有|-+)[.。]?$/i;

/**
 * A commit's message: the changelog's lines, the fixes and the parts it says it reaches people in (`Changelog-parts:`)
 * in its trailers, from every paragraph after the subject that is only trailers (each line `Key: value`, or one indented
 * to fold the line before on). git takes the last such paragraph alone for the trailers, which lost every `Changelog:`
 * written above a blank line and `Co-Authored-By:` (37 commits from 2026-10-01 to 10-08: their changes were in the
 * apps, and nothing said so).
 */
export function readMessage(message: string): { text: string[]; fixes: number[]; parts: string[] } {
  const text: string[] = [];
  const fixes: number[] = [];
  const parts: string[] = [];
  for (const paragraph of message.split("\n").slice(1).join("\n").split(/\n[ \t]*\n/)) {
    const lines = paragraph.split("\n").filter((l) => l.trim());
    if (!lines.length || !lines.every((l, i) => TRAILER.test(l) || (i > 0 && /^\s/.test(l)))) continue;
    for (const line of lines.join("\n").replace(/\n\s+/g, " ").split("\n")) {
      const [, key, value] = TRAILER.exec(line)!;
      if (/^changelog$/i.test(key!) && value!.trim()) text.push(value!.trim());
      if (/^fixes$/i.test(key!)) for (const fb of value!.matchAll(/FB-?(\d+)/gi)) fixes.push(Number(fb[1]));
      if (/^changelog-parts$/i.test(key!)) parts.push(...value!.toLowerCase().split(/[,，\s]+/).filter(Boolean));
    }
  }
  return { text, fixes, parts };
}

/** The parts a commit was said to reach people in ([]: `none`, it needs no release); null: it does not say. */
function partsSaid(said: string[]): Part[] | null {
  const parts = [...new Set(said.filter(isPart))].sort();
  return parts.length || said.includes("none") ? parts : null;
}

/**
 * Why the commit-msg hook and CI (`--refuse`) refuse a commit's message: a Changelog line saying there is nothing to
 * tell; lines or fixes that do not say which parts people see them in (`Changelog-parts:`, the agent's to decide: the
 * files cannot tell, the desktop's change in code the Android app carries too); a part that is none.
 */
export function refused(message: string): string[] {
  const { text, fixes, parts } = readMessage(message);
  const why = text.filter((t) => NOTHING.test(t)).map((t) => `"Changelog: ${t}": a commit with nothing to tell people writes no Changelog line`);
  if ((text.length || fixes.length) && !parts.length) why.push(`no Changelog-parts: say which of ${PART_NAMES.join(", ")} people see it in (none: it needs no release)`);
  const unknown = parts.filter((p) => !isPart(p) && p !== "none");
  if (unknown.length) why.push(`"Changelog-parts: ${unknown.join(", ")}": the parts are ${PART_NAMES.join(", ")}, or none`);
  return why;
}

/** The message's Changelog lines that only say there is nothing to tell. */
export function saysNothing(message: string): string[] {
  return readMessage(message).text.filter((t) => NOTHING.test(t));
}

type Notes = Record<string, { text?: string[]; fixes?: number[]; parts?: string[] }>;

export function changelog(root: string, rev = "HEAD"): Entry[] {
  const git = (...args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
  const notesFile = join(root, "docs/changelog-notes.json");
  const notes: Notes = existsSync(notesFile) ? JSON.parse(readFileSync(notesFile, "utf8")) : {};
  const notCarried = readNotCarried(root);
  // Newest first, one record a commit: its hash, its parents, time and message, then its files.
  const log = git("log", "--first-parent", "--diff-merges=first-parent", "--name-only", "--format=%x1e%H%x1f%P%x1f%ct%x1f%B%x1f", rev);
  const records = log.split("\x1e").slice(1).map((record) => record.split("\x1f") as [string, string, string, string, string]);
  // Each one's version, oldest first: the one before it on this line, and what it brings that that one has not (itself;
  // a merge, the branch too, which early history has). One git a merge, not one a commit counting the whole history
  // again (562 of them took the changelog ~20 s in CI).
  const versions = new Map<string, number>();
  let before = 0;
  for (const [commit, parents] of [...records].reverse()) {
    const [first, ...merged] = parents.split(" ").filter(Boolean);
    before += first && merged.length ? Number(git("rev-list", "--count", `${first}..${commit}`).trim()) : 1;
    versions.set(commit, before);
  }
  const entries: Entry[] = [];
  for (const [commit, , at, message, rest] of records) {
    const said = readMessage(message);
    const note = Object.entries(notes).find(([start]) => start.length >= 7 && commit.startsWith(start))?.[1];
    const text = note?.text ?? said.text;
    const fixes = [...new Set([...said.fixes, ...(note?.fixes ?? [])])];
    if (!text.length && !fixes.length) continue;
    const version = versions.get(commit)!;
    // Where people see it: as docs/changelog-notes.json or its agent says; one from before that did not, where its files are.
    const parts = partsSaid(note?.parts ?? []) ?? partsSaid(said.parts) ?? partsOf(rest.split("\n").filter(Boolean), notCarried);
    entries.push({ version, commit, at: Number(at), text, fixes, parts });
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
  if (flag === "--refuse") {
    // A commit message's file (the commit-msg hook), or a range's commits (CI): what refused says.
    const arg = rev!;
    const messages = existsSync(arg) ? [["this commit", readFileSync(arg, "utf8")]]
      : execFileSync("git", ["log", "--format=%h%x1f%B%x1e", arg], { cwd: root, encoding: "utf8" }).split("\x1e").map((r) => r.trim()).filter(Boolean).map((r) => r.split("\x1f"));
    const refusals = messages.flatMap(([commit, m]) => refused(m!).map((why) => `${commit}: ${why} (docs/changelog.md)`));
    for (const why of refusals) console.error(why);
    process.exit(refusals.length ? 1 : 0);
  }
  if (flag === "--stable") console.log(JSON.stringify(stable(root, changelog(root, rev ?? "HEAD"))));
  else if (flag === "--draft") process.stdout.write(draft(root, rev ?? "HEAD"));
  else console.log(JSON.stringify(changelog(root, rev ?? "HEAD")));
}
