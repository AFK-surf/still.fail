// The frosted ground of whatever floats over the page (menus, popovers, the composer's kind): raised grey let through
// at 72%, thicker in dark (84%) so a light page beneath does not turn it grey; no border.
import { vars } from "./tokens.css.ts";

export const glass = {
  background: `light-dark(color-mix(in srgb, ${vars.raised} 72%, transparent), color-mix(in srgb, ${vars.raised} 84%, transparent))`,
  WebkitBackdropFilter: "blur(20px) saturate(1.4)",
  backdropFilter: "blur(20px) saturate(1.4)",
} as const;
