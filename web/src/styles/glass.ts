// The composer's frosted ground, for whatever floats over the page (the composer, menus, popovers): raised grey let
// through at 72% and blurred; no border. Each adds its own shadow.
import { vars } from "./tokens.css.ts";

export const glass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`,
  WebkitBackdropFilter: "blur(20px)",
  backdropFilter: "blur(20px)",
} as const;
