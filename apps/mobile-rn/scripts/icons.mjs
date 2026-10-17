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
const out = `// Made by scripts/icons.mjs from the Android app's Icons.kt (design/icons): do not edit.
export interface IconPaths { lines: string[]; dots: string[] }

export const Icons = {
${icons.join("\n")}
} satisfies Record<string, IconPaths>;

export type IconName = keyof typeof Icons;
`;
const target = join(app, "src/ui/IconSet.ts");
if (process.argv.includes("--check")) {
  if (readFileSync(target, "utf8") !== out) { console.error("src/ui/IconSet.ts is stale: node scripts/icons.mjs"); process.exit(1); }
} else writeFileSync(target, out);
console.log(`${icons.length} icons`);
