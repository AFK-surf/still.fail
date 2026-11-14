// Writes the web's curves (web/ui/src/curves-data.ts) from the app's (libs/mbui/src/ui/motion.mbt: Out and Leave;
// Move's spring and length from libs/mbui/src/flex/move.mbt, under what lays things out), so a motion eases one way
// on both. `--check` fails when the file is not what those make.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const at = (p: string) => fileURLToPath(new URL(`../${p}`, import.meta.url));
const out = at("web/ui/src/curves-data.ts");
const src = readFileSync(at("libs/mbui/src/ui/motion.mbt"), "utf8");
const bezier = (name: string) => {
  const m = src.match(new RegExp(`\\n\\s+${name} => bezier_at\\(([\\d.]+), ([\\d.]+), ([\\d.]+), ([\\d.]+), t\\)`));
  if (!m) throw new Error(`no ${name} curve in motion.mbt`);
  return m.slice(1, 5).map(Number);
};
const move = readFileSync(at("libs/mbui/src/flex/move.mbt"), "utf8");
const k = move.match(/\n(?:pub )?let move_k : Double = ([\d.]+)\n/);
const most = move.match(/\n(?:pub )?let move_most_ms : Double = ([\d.]+)\n/);
if (!most) throw new Error("no move_most_ms in flex's move.mbt");
if (!k) throw new Error("no move_k in flex's move.mbt");
const text =
  "// Made by scripts/curves.ts from the app's libs/mbui/src/ui/motion.mbt: do not edit.\n\n" +
  `/** What comes (Out). */\nexport const EASE_OUT = [${bezier("Out").join(", ")}] as const;\n` +
  `/** What goes (Leave). */\nexport const EASE_LEAVE = [${bezier("Leave").join(", ")}] as const;\n` +
  `/** Where a move's spring rests: ω·T (Move). */\nexport const MOVE_K = ${Number(k[1])};\n` +
  `/** The longest a move takes (move_most_ms). */\nexport const MOVE_MOST_MS = ${Number(most[1])};\n`;
if (process.argv.includes("--check")) {
  let was = "";
  try { was = readFileSync(out, "utf8"); } catch {}
  if (was !== text) { console.error(`not what motion.mbt makes: ${out} — run node scripts/curves.ts`); process.exit(1); }
} else writeFileSync(out, text);
