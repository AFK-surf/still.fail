// The inline visualizations' page parts from the web's (web/src/viz: its stylesheet and bridge, which the Android app
// packs into its assets), written to src/ui/VizAssets.ts as strings for Viz.tsx. `--check`: fail if that file is stale.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const app = join(dirname(fileURLToPath(import.meta.url)), "..");
const viz = join(app, "../../web/src/viz");
const stylesheet = readFileSync(join(viz, "ember-viz.css"), "utf8");
const bridge = readFileSync(join(viz, "bridge.js"), "utf8");
const out = `// Made by scripts/viz-assets.mjs from web/src/viz (ember-viz.css, bridge.js): do not edit.
/** The web's stylesheet for a visualization's page. */
export const stylesheet = ${JSON.stringify(stylesheet)};
/** The web's bridge, run first in a visualization's page. */
export const bridge = ${JSON.stringify(bridge)};
`;
const file = join(app, "src/ui/VizAssets.ts");
if (process.argv.includes("--check")) {
  if (readFileSync(file, "utf8") !== out) { console.error("src/ui/VizAssets.ts is stale: node scripts/viz-assets.mjs"); process.exit(1); }
} else writeFileSync(file, out);
