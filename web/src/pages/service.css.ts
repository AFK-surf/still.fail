import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const frame = style({ position: "fixed", inset: 0, width: "100%", height: "100%", border: 0, background: vars.canvas });
export const missing = style({ display: "grid", placeContent: "center", minHeight: "100%", margin: 0, padding: "24px", color: vars.muted, textAlign: "center" });
