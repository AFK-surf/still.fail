// The preview's page script (the Android app's assets/preview/page.js, which Preview.kt reads from its assets) as a
// string the app carries, written to src/screens/PreviewPage.ts. `--check`: fail if that file is stale.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = join(dirname(fileURLToPath(import.meta.url)), "..");
const script = readFileSync(join(app, "../android/app/src/main/assets/preview/page.js"), "utf8");
const out = join(app, "src/screens/PreviewPage.ts");
const text = `// Made by scripts/preview-page.mjs from apps/android/app/src/main/assets/preview/page.js: do not edit.
/** The script first in each of a web service's pages in the preview (PreviewWeb.tsx serves it, after the language). */
export const PAGE_SCRIPT: string = ${JSON.stringify(script)};
`;
if (process.argv.includes("--check")) {
  if (readFileSync(out, "utf8") !== text) { console.error("src/screens/PreviewPage.ts is stale: run node scripts/preview-page.mjs"); process.exit(1); }
} else writeFileSync(out, text);
