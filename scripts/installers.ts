// The installers a station release carries (scripts/station-bundle.sh puts them in its bin/): the cloud's installer
// (cloud/src/install.ts, install-windows.ts) in each language, its cloud the one the station that runs it names. The
// station updates itself by these, not by what the cloud serves (docs/release-signing.md).
//   node scripts/installers.ts DIR [darwin-arm64|linux-x64|linux-arm64|win32-x64]
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { bundledInstallScript } from "../cloud/src/install.ts";
import { bundledWindowsInstallScript } from "../cloud/src/install-windows.ts";

const [dir, platform = "darwin-arm64"] = process.argv.slice(2);
if (!dir) {
  console.error("usage: installers.ts DIR [PLATFORM]");
  process.exit(2);
}
for (const lang of ["zh", "en"] as const) {
  if (platform === "win32-x64") writeFileSync(join(dir, `install.${lang}.ps1`), bundledWindowsInstallScript(lang));
  else writeFileSync(join(dir, `install.${lang}.sh`), bundledInstallScript(lang), { mode: 0o755 });
}
