// The frosted ground of whatever floats over the page (menus, popovers, previews): the pane's surface (white in light,
// as Cue's popups), let through a little and blurred; no border. Each adds its own shadow.
import { vars } from "./tokens.css.ts";

export const glass = {
  background: `color-mix(in srgb, ${vars.surface} 86%, transparent)`,
  WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)",
} as const;

/**
 * The composer's ground, after Cue's: the pane's surface (white in light), barely let through and blurred, with a
 * hairline round it and a soft shadow under it, rather than the grey glass.
 */
export const composerGround = {
  background: `color-mix(in srgb, ${vars.surface} 88%, transparent)`,
  WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)",
  boxShadow: `0 0 0 .5px ${vars.ring}, 0 1px 2px rgb(16 24 40 / .05), 0 4px 16px -4px rgb(16 24 40 / .06)`,
  // Asked for less transparency, it is solid.
  "@media": { "(prefers-reduced-transparency: reduce)": { background: vars.surface, WebkitBackdropFilter: "none", backdropFilter: "none" } },
} as const;
