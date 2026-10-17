// The app's icons from the Android app's (apps/android/shared/.../ui/Icons.kt, itself made by scripts/icons.py from
// design/icons): the same names and paths, written to src/ui/IconSet.ts. `--check`: fail if that file is stale.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = join(dirname(fileURLToPath(import.meta.url)), "..");
const kt = readFileSync(join(app, "../android/shared/src/main/kotlin/fail/still/android/ui/Icons.kt"), "utf8");
const list = (s) => [...s.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
const icons = [];
for (const m of kt.matchAll(/^\s*val (\w+) = icon\("([^"]+)", listOf\(([^)]*)\), listOf\(([^)]*)\)\)/gm)) {
  icons.push(`  ${m[1]}: { lines: ${JSON.stringify(list(m[3]))}, dots: ${JSON.stringify(list(m[4]))} },`);
}
if (icons.length < 50) throw new Error(`only ${icons.length} icons found in Icons.kt`);
const glyphs = [];
for (const m of kt.matchAll(/StationGlyph\("([^"]+)", "([^"]*)", "([^"]*)", icon\("[^"]+", listOf\(([^)]*)\), listOf\(([^)]*)\)\)\)/g)) {
  glyphs.push(`  { name: ${JSON.stringify(m[1])}, emoji: ${JSON.stringify(m[2])}, words: ${JSON.stringify(m[3])}, icon: { lines: ${JSON.stringify(list(m[4]))}, dots: ${JSON.stringify(list(m[5]))} } },`);
}
if (glyphs.length < 10) throw new Error(`only ${glyphs.length} station icons found in Icons.kt`);
const names = [...kt.matchAll(/^\s*val (\w+) = icon\("([^"]+)"/gm)].map((m) => `  ${JSON.stringify(m[2])}: Icons.${m[1]},`);
const out = `// Made by scripts/icons.mjs from the Android app's Icons.kt (design/icons): do not edit.
export interface IconPaths { lines: string[]; dots: string[] }

export const Icons = {
${icons.join("\n")}
} satisfies Record<string, IconPaths>;

export type IconName = keyof typeof Icons;

/** The icons by their file names (Icons.byName). */
export const IconsByName: Record<string, IconPaths> = {
${names.join("\n")}
};

/** One of the icons a station can have: its name (kept as glyph:<name>), the emoji kept beside it for older clients, the words it is found by, and it drawn. */
export interface StationGlyph { name: string; emoji: string; words: string; icon: IconPaths }

/** The icons a station can have (design/station-icons), in the picker's order. */
export const StationIcons = {
  all: [
${glyphs.join("\n")}
  ] as StationGlyph[],
  /** The one a station's icon names (glyph:<name>, or glyph:<name>:<colour>); null for a picture, none, or one this build does not know. */
  of(icon: string | null | undefined): StationGlyph | null {
    if (!icon?.startsWith("glyph:")) return null;
    const name = icon.slice(6).split(":")[0];
    return StationIcons.all.find((g) => g.name === name) ?? null;
  },
};
`;
const target = join(app, "src/ui/IconSet.ts");
if (process.argv.includes("--check")) {
  if (readFileSync(target, "utf8") !== out) { console.error("src/ui/IconSet.ts is stale: node scripts/icons.mjs"); process.exit(1); }
} else writeFileSync(target, out);
console.log(`${icons.length} icons, ${glyphs.length} station icons`);
