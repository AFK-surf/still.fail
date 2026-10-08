import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

/** A group of providers under its small heading (Cue's order: labs, china, gateways, cloud, inference, local). */
export const group = style({ marginBottom: "28px" });
export const groupHead = style({ margin: "0 0 8px", fontSize: vars.textLabel, fontWeight: "500", color: vars.muted });
export const tiles = style({
  display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "4px", margin: "0 -12px",
  "@media": { "(max-width: 700px)": { gridTemplateColumns: "repeat(2, minmax(0, 1fr))" } },
});
/** A provider: its mark and its name, nothing else; flat, a ground on hover. */
export const tile = style({
  display: "flex", alignItems: "center", gap: "12px", minWidth: "0", padding: "10px 12px", textAlign: "left", border: "0",
  borderRadius: vars.rField, background: "transparent", color: vars.text, fontSize: vars.textBody, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
export const tileName = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** The two ways to connect a vendor that has both: its plan, or a key. */
export const methods = style({
  display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", gap: "12px",
  "@media": { "(max-width: 700px)": { gridTemplateColumns: "1fr" } },
});
export const method = style({
  display: "grid", gap: "6px", alignContent: "start", padding: "18px", textAlign: "left", border: "0", borderRadius: vars.rCard,
  background: vars.paper, color: vars.text, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover } },
});
export const methodHint = style({ fontSize: vars.textSecondary, color: vars.muted });
export const form = style({ display: "grid", gap: "18px" });
export const offers = style({ marginBottom: "28px" });
export const uses = style({ margin: "0", fontSize: vars.textSecondary, color: vars.muted });
export const stations = style({ marginBottom: "24px" });
