// Writes the app's palette (apps/mbui/src/sf/palette_data.mbt) from still.fail's colours (web/ui/src/palette.ts), so
// the web's pages and the app have one set. `--check` fails when the file is not what the colours make.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { PALETTE, TONE } from "../web/ui/src/palette.ts";

const at = (p: string) => fileURLToPath(new URL(`../${p}`, import.meta.url));
const out = at("apps/mbui/src/sf/palette_data.mbt");
// the app's Palette's fields, in its order (tokens.mbt)
const tokens = readFileSync(at("apps/mbui/src/sf/tokens.mbt"), "utf8");
const struct = tokens.slice(tokens.indexOf("pub(all) struct Palette {"), tokens.indexOf("\n}\n", tokens.indexOf("pub(all) struct Palette {")));
const fields = [...struct.matchAll(/^\s+([a-z_0-9]+) : Int64$/gm)].map((m) => m[1]!);
const hex = (c: string) => `0x${c.slice(1).toUpperCase().padEnd(8, "F")}L`;
const value = (v: string | { tone: string }, theme: "light" | "dark") =>
  typeof v === "string" ? hex(v) : `alpha(${hex(v.tone)}, tone_${theme})`;
const palette = (theme: "light" | "dark") => {
  const p = PALETTE[theme] as Record<string, string | { tone: string }>;
  const missing = fields.filter((f) => !(f in p));
  if (missing.length) throw new Error(`web/ui/src/palette.ts has no ${missing.join(", ")} for ${theme}`);
  return `let web_${theme} : Palette = {\n${fields.map((f) => `  ${f}: ${value(p[f]!, theme)},`).join("\n")}\n}\n`;
};
const text =
  "// Made by scripts/palette.ts from web/ui/src/palette.ts: do not edit.\n\n" +
  `///|\nlet tone_light : Double = ${TONE.light}\n\n///|\nlet tone_dark : Double = ${TONE.dark}\n\n` +
  `///|\n${palette("light")}\n///|\n${palette("dark")}`;
if (process.argv.includes("--check")) {
  let was = "";
  try { was = readFileSync(out, "utf8"); } catch {}
  if (was !== text) { console.error(`not what web/ui/src/palette.ts makes: ${out} — run node scripts/palette.ts`); process.exit(1); }
} else writeFileSync(out, text);
