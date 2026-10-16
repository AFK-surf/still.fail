// What is over the left end of a page's top row while the sidebar is closed (the desktop window's buttons, 更新 beside
// them, the sidebar's own button), and a bar there kept clear of it: called from a stylesheet (.css.ts).
import { globalStyle } from "@vanilla-extract/css";

const railed = ":root:has([data-rail])";
const wide = "(min-width: 701px)";

/**
 * A bar across a page's top (`bar`: its selector) clear of what is over its left end while the sidebar is closed: the
 * window's buttons (in the desktop app), 更新 beside them (`update`: its selector), the sidebar's own button without
 * the rail. The page bars do it, and the drive's reader and player, whose toolbars take that row.
 */
export function clearOfWindowButtons(bar: string, update: string): void {
  globalStyle(`[data-sidebar="closed"] ${bar}`, { "@media": { [wide]: { paddingLeft: "52px" } } });
  globalStyle(`[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] ${bar}`, { "@media": { [wide]: { paddingLeft: "124px" } } });
  globalStyle(`${railed}[data-sidebar="closed"] ${bar}`, { "@media": { [wide]: { paddingLeft: "12px" } } });
  // The window's buttons reach 12 px past the rail.
  globalStyle(`${railed}[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] ${bar}`, { "@media": { [wide]: { paddingLeft: "28px" } } });
  globalStyle(`${railed}:has(${update})[data-sidebar="closed"] ${bar}`, { "@media": { [wide]: { paddingLeft: "72px" } } });
  globalStyle(`${railed}:has(${update})[data-desktop="inset"]:not([data-fullscreen])[data-sidebar="closed"] ${bar}`, { "@media": { [wide]: { paddingLeft: "84px" } } });
}
