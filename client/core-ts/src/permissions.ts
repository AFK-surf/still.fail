// What macOS lets a Mac station's still.fail Helper do (docs/remote-screens.md "Grants"), as the station's page shows it:
// the overview's `permissions` put in words. Each grant with what it is for, or, while its window is up on the Mac, how
// it is given there; what is unavailable now for want of one; the desktop's page when its screen can be seen and
// driven (a person asks for a grant and grants it from wherever they are, through it); and whether the viewer may ask.
// A station that says none (not a Mac, or from before them) has none: the page shows nothing.
import { t } from "./i18n.ts";
import { encode } from "./ops.ts";
import { StationAddr } from "./station/addr.ts";
import { get, isObject } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// The grants, in the order they are shown; any other a station names is left out.
export const GRANTS = ["capture", "control", "documents", "desktop", "downloads", "removable", "network", "localNetwork"];

/// The desktop's page in the app (the agents' `screen` tool links it so too).
function desktopPath(station: string): string {
  const addr = StationAddr.parse(station);
  return `/w/${encode(addr.workspace)}/s/${encode(addr.station)}/screen/desktop`;
}

/// What is unavailable now for want of the grants `ids`, in a line (the page's note; a screen's row in its list).
export function unavailable(ids: string[]): string {
  return t("core-views.permissions.unavailable", { features: ids.map((id) => t(`core-views.permissions.${id}.feature`)).join(t("core-views.screen.and")) });
}

/// The overview's `permissions` (`{grants: [{grant, state}], asking, screen, request}`) as the page shows it; undefined
/// when the station said none.
export function permissionsShown(v: unknown, station: string): J | undefined {
  if (!isObject(v) || !Array.isArray(v.grants)) return undefined;
  const asking = new Set(Array.isArray(v.asking) ? v.asking.filter((g: unknown) => typeof g === "string") : []);
  const screen = v.screen === true;
  const grants = v.grants.flatMap((g: unknown) => {
    const id = get(g, "grant");
    if (typeof id !== "string" || !GRANTS.includes(id)) return [];
    const granted = get(g, "state") === "granted";
    const up = !granted && asking.has(id);
    // The LAN not reached: where it is switched on, for the app the station runs in (no window asks for it).
    const off = id === "localNetwork" && !granted;
    const app = typeof v.localNetworkName === "string" ? v.localNetworkName : "still.fail";
    const line = off
      ? t("core-views.permissions.localNetwork.off", { app })
      : up
        ? t(screen ? "core-views.permissions.askingHere" : "core-views.permissions.askingThere")
        : t(`core-views.permissions.${id}.line`);
    return [{ id, name: t(`core-views.permissions.${id}.name`), line, granted, asking: up }];
  });
  const missing = grants.filter((g: J) => !g.granted);
  return {
    grants,
    ...(missing.length > 0 ? { note: unavailable(missing.map((g: J) => g.id)) } : {}),
    ...(screen ? { screen: desktopPath(station) } : {}),
    canRequest: v.request === true,
  };
}
