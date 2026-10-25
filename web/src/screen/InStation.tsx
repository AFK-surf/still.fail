// A sign-in's page in the station's own browser (docs/remote-login.md, 在 station 的浏览器中登录): the station opens it in a
// tab of its browser (the one open, if it is) and answers the tab's screen, whose page opens here and goes back by
// itself once the tab is gone (closed as the sign-in ends: `?until-gone`, ScreenPage). Claude's comes back to its
// command there, with no code to paste; a device code is pasted into the page from this device's clipboard.
import { useGo } from "../go.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { stationBase } from "../station.tsx";

/** What a screen's page is opened with when it is to go back by itself once its screen is gone. */
export const UNTIL_GONE = "until-gone";

/** The page of a screen, opened until it is gone. */
export function untilGone(station: string, screen: string): string {
  return `${stationBase(station)}/screen/${encodeURIComponent(screen)}?${UNTIL_GONE}`;
}

/** Opens a page in the station's browser by `ask` (the station's answer names its tab's screen), then the screen's page;
 * a failure said as 无法<what>. */
export function useInStation(station: string): (ask: () => Promise<unknown>, what: string) => void {
  const go = useGo();
  const act = useAct();
  return (ask, what) => act(ask().then((answer) => {
    const screen = (answer as { screen?: unknown } | null)?.screen;
    if (typeof screen === "string" && screen !== "") go(untilGone(station, screen));
  }), what);
}
