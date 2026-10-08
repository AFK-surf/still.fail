// The notifications page (Notifications.tsx): a setting with a choice beside it, and the note on sound.
import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const row = style({ display: "flex", alignItems: "center", gap: "16px", flexWrap: "wrap" });
export const rowText = style({ flex: "1", minWidth: "180px", display: "grid", gap: "2px", fontSize: vars.textSecondary });
export const hint = style({ margin: "0", padding: "8px 10px", borderRadius: vars.rField, background: vars.neutralBg, color: vars.muted, fontSize: vars.textSecondary });
export const rows = style({ display: "grid", gap: "16px" });
export const lead = style({ marginBottom: "28px" });
export const doneChoice = style({ width: "240px", flex: "none" });
