// The station's error reports (mesh/app/src/telemetry.rs) use the web app's PostHog key (docs/telemetry.md): this
// writes it to dist/admin/posthog.json, where a release keeps it (scripts/station-bundle.sh) and the station reads it
// at start. dist/admin held the station's own page once; now it holds only this. The key is read as web/vite.config.ts
// reads it: from the file $STILLFAIL_POSTHOG ($EMBER_POSTHOG before the rename) names ({host, key}), with this
// checkout's commit as the release. Without one, dist/admin is made empty: the station then reports nothing.
//   node scripts/posthog-key.ts
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const out = `${root}dist/admin`;
// A page built here by an older checkout goes: nothing serves it now.
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const path = process.env.STILLFAIL_POSTHOG ?? process.env.EMBER_POSTHOG;
if (path) {
  const { host, key } = JSON.parse(readFileSync(path, "utf8")) as { host: string; key: string };
  let release = "unknown";
  try {
    release = execFileSync("git", ["rev-parse", "--short=12", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
  } catch { /* not a checkout */ }
  writeFileSync(`${out}/posthog.json`, `${JSON.stringify({ host, key, release })}\n`);
  console.log("dist/admin/posthog.json written");
} else {
  console.log("no PostHog key ($STILLFAIL_POSTHOG): dist/admin/posthog.json not written");
}
