// Writes apps/mbui/src/stillfail/ui_faults.mbt from the core's list of UI fault categories (src/ui-faults.ts), so the
// app and the core sort faults by one list. `--check` fails when the file is not what the list makes.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { UI_FAULTS, UI_FAULT_OTHER } from "../src/ui-faults.ts";

const out = fileURLToPath(new URL("../../../apps/mbui/src/stillfail/ui_faults.mbt", import.meta.url));
const q = (s: string) => JSON.stringify(s);
const branches = UI_FAULTS.map((f) => `  if ${f.whole ? `said == ${q(f.said)}` : `said.has_prefix(${q(f.said)})`} {\n    return ${q(f.category)}\n  }\n`).join("");
const text =
  "// Made by client/core-ts/scripts/ui-faults.ts from the core's src/ui-faults.ts: do not edit.\n\n" +
  "///|\n/// What of UI fault `said` may be reported: its category, never its text.\n" +
  `fn ui_fault_category(said : String) -> String {\n${branches}  ${q(UI_FAULT_OTHER)}\n}\n`;
if (process.argv.includes("--check")) {
  let was = "";
  try { was = readFileSync(out, "utf8"); } catch {}
  if (was !== text) { console.error(`not what client/core-ts/src/ui-faults.ts makes: ${out} — run node client/core-ts/scripts/ui-faults.ts`); process.exit(1); }
} else writeFileSync(out, text);
