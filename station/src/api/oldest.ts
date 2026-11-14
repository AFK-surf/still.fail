// How old a core this station still answers (CONTRIBUTING.md: what is kept for older versions goes 7 days after what
// replaces it ships). Each core says its build with every request (`stillfail-build`, as `0.1.<n>`), and each answer
// says the station's. A change that takes out what a station kept for older cores raises OLDEST_CORE, in the same
// change, to the build that first did without it: a core that says a build older than that is told to update (426),
// not answered the old way (one that says none is answered: `coreTooOld`). The core keeps the same floor for stations
// (client/core-ts/src/station/oldest.ts).
import { version } from "../ops/version.ts";

export const BUILD_HEADER = "stillfail-build";

/// The oldest core build answered; 0: any. 6968 said its build first (#3612), and made its sidebar and a thread's
/// summary itself (`rows=1`, `views=1`): api/events.ts makes them for no stream since.
export const OLDEST_CORE = 6968;

/// A build under this is no release's count of commits, and is not held to the floor: a development build's (`0.1.0`,
/// `0.1.1`) and an iOS app's, whose number is its TestFlight build's (libs/mbui/scripts/ios.sh MBUI_IOS_BUILD).
export const COUNTED_FROM = 1000;

/// The build in `0.<m>.<n>` (or `<n>`), null for none: n, the commits up to it; m, the stable releases up to it, only
/// said (`0.1.` until it was counted, the user, 2026-11-09).
export function buildOf(said: string | undefined): number | null {
  const m = /^(?:0\.\d+\.)?(\d+)$/.exec(said?.trim() ?? "");
  return m ? Number(m[1]) : null;
}

/// Whether a core asking with these headers is older than OLDEST_CORE (`oldest`, a test's): one that says a release's
/// build under it. One that says no build is held to no floor: the app on the web never told its core a build (its
/// host says what the device is nowhere; `0.1.0` only since #5187, 2026-11-10), so a web page of any release before
/// that, and a tab not loaded again since, asks exactly as a core from before builds were said does (#3612,
/// 2026-11-03), a language and no build. Told to update as those were (#5187), every such page had each of its
/// requests refused: its stations up and none reached, its chats as they were when it was last open, and nothing it
/// could update (2026-11-10, the stable web on these stations). A core from before #3612 is answered as any, without
/// the sidebar rows and thread summaries a station made for it until then. Not to be turned back before the web says
/// its release's build and that has been out 7 days.
export function coreTooOld(headers: Record<string, unknown>, oldest = OLDEST_CORE): boolean {
  if (oldest <= 0) return false;
  const said = Object.entries(headers).find(([k]) => k.toLowerCase() === BUILD_HEADER)?.[1];
  const build = buildOf(typeof said === "string" ? said : undefined);
  return build !== null && build >= COUNTED_FROM && build < oldest;
}

/// This station's build, as answers say it.
export const stationBuild = (): string => version();
