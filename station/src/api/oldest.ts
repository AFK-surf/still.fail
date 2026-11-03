// How old a core this station still answers (CONTRIBUTING.md: what is kept for older versions goes 7 days after what
// replaces it ships). Each core says its build with every request (`stillfail-build`, as `0.1.<n>`), and each answer
// says the station's. A change that takes out what a station kept for older cores raises OLDEST_CORE, in the same
// change, to the build that first did without it: a core older than that (or one from before it said its build) is
// told to update (426), not answered the old way. The core keeps the same floor for stations
// (client/core-ts/src/station/oldest.ts).
import { version } from "../ops/version.ts";

export const BUILD_HEADER = "stillfail-build";

/// The oldest core build answered; 0: any.
export const OLDEST_CORE = 0;

/// The build in `0.1.<n>` (or `<n>`), null for none.
export function buildOf(said: string | undefined): number | null {
  const m = /^(?:0\.1\.)?(\d+)$/.exec(said?.trim() ?? "");
  return m ? Number(m[1]) : null;
}

/// Whether a core asking with these headers is older than OLDEST_CORE (`oldest`, a test's).
export function coreTooOld(headers: Record<string, unknown>, oldest = OLDEST_CORE): boolean {
  if (oldest <= 0) return false;
  const said = Object.entries(headers).find(([k]) => k.toLowerCase() === BUILD_HEADER)?.[1];
  const build = buildOf(typeof said === "string" ? said : undefined);
  return build === null || build < oldest;
}

/// This station's build, as answers say it.
export const stationBuild = (): string => version();
