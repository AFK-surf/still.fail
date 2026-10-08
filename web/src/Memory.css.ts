import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { memoryStation } from "./cloud/settings.css.ts";

export const memoryDoc = style({ fontSize: vars.textBody });
export const memorySkill = style({ display: "flex", flexDirection: "column" });
export const memorySkillRow = style({
  display: "flex", alignItems: "flex-start", gap: "10px", width: "100%", padding: "10px 12px", border: "0",
  borderRadius: vars.rOption, background: "none", color: vars.text, font: "inherit", textAlign: "left",
  cursor: "pointer", cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    [`${memorySkill}[data-open] > &`]: { background: vars.hover },
  },
});
export const memorySkillText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "1px" });
export const memorySkillOwn = style({ fontSize: vars.textLabel, fontWeight: "400", color: vars.subtle });
export const memoryShare = style({ padding: "4px 12px 0 38px" });
export const memoryConflict = style({ margin: "6px 0 0", fontSize: vars.textLabel, color: vars.amber });
export const memoryNone = style({ margin: "0", fontSize: vars.textSecondary });
globalStyle(`${memoryDoc} > :first-child`, { marginTop: "0" });
globalStyle(`${memoryDoc} > :last-child`, { marginBottom: "0" });
/** Here rather than with its class: it comes after .memory-doc > :first-child, and wins over it. */
globalStyle(`${memorySkill} + ${memorySkill}`, { marginTop: "2px" });
globalStyle(`${memorySkillRow} > svg`, {
  flex: "none", marginTop: "2px", color: vars.subtle,
});
globalStyle(`${memorySkillText} b`, {
  display: "flex", alignItems: "baseline", gap: "8px", fontSize: vars.textSecondary, fontWeight: "500", lineHeight: "20px",
});
globalStyle(`${memorySkillText} > span`, { fontSize: vars.textLabel, color: vars.muted });
globalStyle(`${memorySkill} ${memoryDoc}`, { padding: "12px 12px 18px 38px" });
/** Here rather than with its class: it comes after .memory-doc > :first-child, and wins over it. */
globalStyle(`${memoryStation} + ${memoryStation}`, { marginTop: "36px" });
