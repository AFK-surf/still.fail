import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

// The archive: one row a chat, its title with when (and where) at the end of its line, its last message the whole
// line under it; what can be done with it in when's place while it is pointed at. No lines between.
export const archiveHeading = style({ margin: "18px 10px 4px", fontSize: vars.textMeta, color: vars.muted });
export const archiveRow = style({
  display: "grid", gap: "2px", padding: "8px 10px", borderRadius: vars.rNav, cornerShape: vars.cornerShape,
  selectors: {
    "&:hover, &:focus-within": { background: vars.hover },
  },
});
export const archiveHead = style({ display: "flex", alignItems: "baseline", gap: "12px", minWidth: "0" });
export const archiveTitle = style({
  flex: "1", fontSize: vars.textUi, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const archiveMeta = style({
  fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const archiveWhen = style({
  display: "flex", gap: "8px", flex: "none", fontSize: vars.textMeta, color: vars.muted, fontVariantNumeric: "tabular-nums",
  selectors: { [`${archiveRow}:is(:hover, :focus-within) &`]: { display: "none" } },
});
/** In the title's line without making it taller. */
export const archiveActions = style({
  display: "none", gap: "2px", flex: "none", alignSelf: "center", margin: "-4px -4px -4px 0",
  selectors: { [`${archiveRow}:is(:hover, :focus-within) &`]: { display: "flex" } },
  // No pointer to point with: always there.
  "@media": { "(hover: none)": { display: "flex" } },
});
export const archiveAction = style({ width: "26px", height: "26px" });
export const archiveDelete = style({ selectors: { "&:hover": { color: vars.red } } });
