// This station's version, as still.fail cloud and `stillfail update` are told it: its release's (`0.1.<n>`, from the
// BUILD file of the release it runs from: <app>/station/main.js, so <app> is two up), else this package's. Read once:
// an update puts the next release's in its place before this one hands over.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

let read: string | undefined;

/// The release directory this code runs from.
export const appDir = () => dirname(dirname(fileURLToPath(import.meta.url)));

export function stationVersion(app: string): string | undefined {
  try {
    const build = readFileSync(join(app, "BUILD"), "utf8").trim();
    return build !== "" && /^[0-9]+$/.test(build) ? `0.1.${build}` : undefined;
  } catch {
    return undefined;
  }
}

export function version(): string {
  return (read ??= stationVersion(appDir()) ?? "0.1.0");
}
