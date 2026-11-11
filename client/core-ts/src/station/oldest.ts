// How old a station this core still talks to (CONTRIBUTING.md: what is kept for older versions goes 7 days after what
// replaces it ships). Each answer of a station says its build (`stillfail-build`, as `0.1.<n>`), and each request of
// this core says its own (the host's, prefs.ts `device`). A change that takes out what the core kept for older
// stations raises OLDEST_STATION, in the same change, to the build that first did without it: an answer of a station
// older than that (or of one from before it said its build) fails, saying the station needs an update. The station
// keeps the same floor for cores (station/src/api/oldest.ts).
import { t } from "../i18n.ts";
import { CoreError } from "../error.ts";

export const BUILD_HEADER = "stillfail-build";

/// The oldest station build talked to; 0: any. 6968 said its build first (#3612), told every stream it leaves the
/// sidebar to the device and keeps its marks (`made`), and told no `thread-view` or `chat` to one that makes them:
/// station/sync.ts keeps no other way of making them since.
export const OLDEST_STATION = 6968;

/// A build under this is no release's count of commits, and is not held to the floor: a station run from the sources
/// says `0.1.0` (station/src/ops/version.ts).
export const COUNTED_FROM = 1000;

/// What is asked of a station too old all the same: what its updates are and the asking for one (its overview, POST
/// /updates…), so the person told to update it can.
const ASKED_OF_ANY = /^\/(overview|updates)(\/|\?|$)/;

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

/// The failure for an answer to `path` (after /admin/api) of a station older than OLDEST_STATION (`oldest`, a test's),
/// null for one new enough, or for what is asked of any (ASKED_OF_ANY). One saying no build is a station's from before
/// it said one where it says it keeps writes to once (`stillfail-idempotent`, every station's answer since the Rust
/// one's); what says neither is no station's (a test's own answer).
export function stationTooOld(headers: readonly [string, string][], path: string, oldest = OLDEST_STATION): CoreError | null {
  if (oldest <= 0 || ASKED_OF_ANY.test(path)) return null;
  const said = (name: string) => headers.find(([k]) => k.toLowerCase() === name)?.[1];
  const build = buildOf(said(BUILD_HEADER));
  if (build === null ? said("stillfail-idempotent") === undefined : build < COUNTED_FROM || build >= oldest) return null;
  return new CoreError("station_too_old", t("station.core.stationTooOld"), 426);
}
