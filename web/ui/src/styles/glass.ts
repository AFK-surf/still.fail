// The grounds things float on. Each adds its own shadow.
import { vars } from "./tokens.css.ts";

/**
 * What every panel that pops up stands on, one and the same: menus, popovers, hover cards, dialogs, ⌘K. Opaque, a line
 * round it (over a dense list or the messages, glass let the rows read through). White in light; in dark the raised
 * grey, a step off the page.
 */
export const panelGround = `light-dark(${vars.canvas}, ${vars.raised})`;
export const panel = {
  background: panelGround,
  border: `1px solid ${vars.line}`,
  // (the line over what is behind the panel, not over its own ground: on a dimmed page a line over the white was a
  // pale ring round it)
  backgroundClip: "padding-box",
  WebkitBackdropFilter: "none",
  backdropFilter: "none",
} as const;

/** The composer's frosted ground (and the bands and bars that sit on the page with it): raised grey at 72%, blurred; no border. */
export const glass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`,
  WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)",
} as const;

/** Frosted glass over a picture, in the theme's colours (a viewer is light in a light app, dark in a dark one). */
export const pictureGlass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, backdropFilter: "blur(24px) saturate(1.6)", WebkitBackdropFilter: "blur(24px) saturate(1.6)",
};
