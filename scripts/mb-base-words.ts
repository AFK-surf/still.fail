// Writes libs/base/src/mesh/words_made.mbt from the device base's own words (client/core-ts/src/lang.zh.json and
// lang.en.json: of no program, the peer "the server"), the keys the mesh says (`core-logic.mesh.*`), so the mesh in
// MoonBit says what the one in TypeScript says and no word is written twice by hand. The two files are read as what
// they are written, nothing of the core loaded. `--check` fails when the file is not what the two make
// (scripts/check.sh runs it for a change to either side).
//
// And the other way, in either mode: every key the mesh says has words. `say` gives a key it has no words for back as
// the key itself, so one renamed or taken out of the two files would be shown to people as `no_reply`, and nothing
// would fail. The mesh says a key as the first argument of `say`, `failed` or `under` (libs/base/src/mesh/words.mbt,
// error.mbt), written out as a string: each must be a key of both files, and one that is not written out is refused
// (but the two helpers handing their own `key` on to `say`), since it cannot be held.
//
//   node scripts/mb-base-words.ts [--check]
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const FROM = "client/core-ts/src";
const at = (path: string) => fileURLToPath(new URL(`../${path}`, import.meta.url));
const out = at("libs/base/src/mesh/words_made.mbt");
/// The words of a language as they are written: the keys in the file's order.
const read = new Map<string, Record<string, string>>();
function saidIn(lang: string): Record<string, string> {
  if (!read.has(lang)) read.set(lang, JSON.parse(readFileSync(at(`${FROM}/lang.${lang}.json`), "utf8")) as Record<string, string>);
  return read.get(lang)!;
}

/// A MoonBit string of `text`.
const literal = (text: string) => `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
const table = (name: string, words: Record<string, string>) =>
  `///|\nlet ${name} : Map[String, String] = {\n${Object.entries(words)
    .filter(([key]) => key.startsWith("core-logic.mesh."))
    .map(([key, text]) => `  ${literal(key)}: ${literal(text)},\n`)
    .join("")}}\n`;
const made =
  `// Made by scripts/mb-base-words.ts from ${FROM}/lang.zh.json and lang.en.json (the device base's own words):\n// do not edit.\n\n` +
  `${table("made_zh", saidIn("zh"))}\n${table("made_en", saidIn("en"))}`;

if (process.argv.includes("--check")) {
  let was = "";
  try { was = readFileSync(out, "utf8"); } catch {}
  if (was !== made) { console.error(`not what ${FROM}/lang.zh.json and lang.en.json make: ${out} — run node scripts/mb-base-words.ts`); process.exit(1); }
} else writeFileSync(out, made);

// ── every key the mesh says has words ──

const MESH = "libs/base/src/mesh";
/// The one file whose functions hand a key they were given on to `say`: `failed` and `under`, their parameter `key`.
const HANDS_ON = "error.mbt";
const lacking: string[] = [];
for (const file of readdirSync(at(MESH)).filter((name) => name.endsWith(".mbt") && name !== "words_made.mbt").sort()) {
  // (comments blanked, each character but a newline a space, so that a place in it is the same place in the file)
  const code = readFileSync(at(`${MESH}/${file}`), "utf8").replace(/^\s*\/\/.*$/gm, (comment) => comment.replace(/./g, " "));
  for (const call of code.matchAll(/(\bfn\s+)?\b(say|failed|under)\(\s*("(?:[^"\\\n]|\\.)*"|[^\s,)]*)/g)) {
    // (its own declaration, `fn say(key : String, …`)
    if (call[1] !== undefined) continue;
    const where = `${MESH}/${file}:${code.slice(0, call.index).split("\n").length}`;
    const said = call[3]!;
    if (!said.startsWith('"')) {
      if (file !== HANDS_ON || said !== "key") lacking.push(`${where}: \`${call[2]}(${said}\`: a key not written out as a string cannot be held to the words: write it out where it is said`);
      continue;
    }
    const key = `core-logic.mesh.${JSON.parse(said) as string}`;
    for (const lang of ["zh", "en"]) {
      if (!(key in saidIn(lang))) lacking.push(`${where}: says "${key.slice("core-logic.mesh.".length)}", and ${FROM}/lang.${lang}.json has no ${key}: people would be shown the key itself. Renamed or taken out there? Say the key it has now; a new one is written there first, in both languages`);
    }
  }
}
if (lacking.length > 0) { console.error(lacking.join("\n")); process.exit(1); }
