import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// The desktop app's version: one row, the version and what the last check found on the left, its button on the right.
export const row = style({ display: "flex", alignItems: "center", gap: "16px" });
export const text = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px", fontSize: vars.textUi });
export const note = style({ color: vars.muted });
export const failed = style({ color: vars.red });
