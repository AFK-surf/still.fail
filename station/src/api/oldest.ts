// How old a core this station still answers (CONTRIBUTING.md: what is kept for older versions goes 7 days after what
// replaces it ships). Each core says its build with every request (`stillfail-build`, as `0.1.<n>`), and each answer
// says the station's. A change that takes out what a station kept for older cores raises OLDEST_CORE, in the same
// change, to the build that first did without it: a core older than that (or one from before it said its build) is
// told to update (426), not answered the old way. The core keeps the same floor for stations
// (client/core-ts/src/station/oldest.ts).
import { version } from "../ops/version.ts";

export const BUILD_HEADER = "stillfail-build";

/// The oldest core build answered; 0: any. 6968 said its build first (#3612), and made its sidebar and a thread's
/// summary itself (`rows=1`, `views=1`): api/events.ts makes them for no stream since.
export const OLDEST_CORE = 6968;

/// A build under this is no release's count of commits, and is not held to the floor: a development build's (`0.1.0`,
/// `0.1.1`) and an iOS app's, whose number is its TestFlight build's (apps/mbui/mbui/scripts/ios.sh MBUI_IOS_BUILD).
export const COUNTED_FROM = 1000;

/// The build in `0.<m>.<n>` (or `<n>`), null for none: n, the commits up to it; m, the stable releases up to it, only
/// said (`0.1.` until it was counted, the user, 2026-11-09).
export function buildOf(said: string | undefined): number | null {
  const m = /^(?:0\.\d+\.)?(\d+)$/.exec(said?.trim() ?? "");
  return m ? Number(m[1]) : null;
}

/// Whether a core asking with these headers is older than OLDEST_CORE (`oldest`, a test's). One saying no build is a
/// core from before it said one where it says its language (`stillfail-lang`, every core's since languages); what
/// says neither is no core (a test's own request, a tool's).
export function coreTooOld(headers: Record<string, unknown>, oldest = OLDEST_CORE): boolean {
  if (oldest <= 0) return false;
  const said = (name: string) => Object.entries(headers).find(([k]) => k.toLowerCase() === name)?.[1];
  const build = buildOf(typeof said(BUILD_HEADER) === "string" ? (said(BUILD_HEADER) as string) : undefined);
  if (build === null) return said("stillfail-lang") !== undefined;
  return build >= COUNTED_FROM && build < oldest;
}

/// This station's build, as answers say it.
export const stationBuild = (): string => version();
