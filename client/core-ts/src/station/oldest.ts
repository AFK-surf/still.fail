// How old a station this core still talks to (CONTRIBUTING.md: what is kept for older versions goes 7 days after what
// replaces it ships). Each answer of a station says its build (`stillfail-build`, as `0.1.<n>`), and each request of
// this core says its own (the host's, prefs.ts `device`). A change that takes out what the core kept for older
// stations raises OLDEST_STATION, in the same change, to the build that first did without it: an answer of a station
// older than that (or of one from before it said its build) fails, saying the station needs an update. The station
// keeps the same floor for cores (station/src/api/oldest.ts).
import { t } from "../i18n.ts";
import { CoreError } from "../error.ts";

export const BUILD_HEADER = "stillfail-build";

/// The oldest station build talked to; 0: any.
export const OLDEST_STATION = 0;

let own = "";

/// This core's build as its host says it (`0.1.<n>`), said with every request.
export function setOwnBuild(build: string): void {
  own = build;
}

export const ownBuild = (): string => own;

/// The build in `0.<m>.<n>` (or `<n>`), null for none: n, the commits up to it; m, the stable releases up to it, only
/// said (`0.1.` until it was counted, the user, 2026-11-09).
export function buildOf(said: string | undefined): number | null {
  const m = /^(?:0\.\d+\.)?(\d+)$/.exec(said?.trim() ?? "");
  return m ? Number(m[1]) : null;
}

/// The failure for an answer of a station older than OLDEST_STATION (`oldest`, a test's), null for one new enough.
export function stationTooOld(headers: readonly [string, string][], oldest = OLDEST_STATION): CoreError | null {
  if (oldest <= 0) return null;
  const build = buildOf(headers.find(([k]) => k.toLowerCase() === BUILD_HEADER)?.[1]);
  return build !== null && build >= oldest ? null : new CoreError("station_too_old", t("station.core.stationTooOld"), 426);
}
