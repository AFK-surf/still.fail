import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const navNote = style({ marginLeft: "auto", fontSize: vars.textLabel, color: vars.muted });
export const connectFacts = style({ display: "flex", alignItems: "center", gap: "10px", flex: "none" });
export const connectTeam = style({
  display: "inline-flex", alignItems: "center", gap: "4px", marginLeft: "8px", fontWeight: "400",
  fontSize: vars.textLabel, color: vars.muted,
});
/** A list's heading that only names it (not a section of its own): small and quiet, no rule under it. */
export const sectionTitleQuiet = style({
  margin: "0 0 6px", fontSize: vars.textLabel, fontWeight: "500", color: vars.muted,
});
