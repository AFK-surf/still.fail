// The composer's frosted ground, for whatever floats over the page (the composer, menus, popovers): raised grey let
// through at 72% and blurred; no border. Each adds its own shadow.
import { vars } from "./tokens.css.ts";

/**
 * What the sidebar's menus stand on (controls.css.ts \`popoverSolid\`): opaque, a line round it. Over its dense list,
 * the glass let the rows read through. White in light; in dark the raised grey, a step off the page.
 */
export const solid = {
  background: `light-dark(${vars.canvas}, ${vars.raised})`,
  border: `1px solid ${vars.line}`,
  WebkitBackdropFilter: "none",
  backdropFilter: "none",
} as const;

export const glass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`,
  WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)",
} as const;
