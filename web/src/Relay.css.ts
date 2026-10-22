import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** The dialog's search, its places, then the note: one column. */
export const body = style({ display: "grid", gap: "12px", minWidth: "0" });
/** The places, by connect, scrolling within the dialog. */
export const list = style({ display: "grid", gap: "8px", maxHeight: "300px", overflowY: "auto", minHeight: "0" });
export const group = style({ display: "grid", gap: "2px" });
/** A connect: its platform's mark, the platform, its team. */
export const groupHead = style({ display: "flex", alignItems: "center", gap: "6px", padding: "6px 8px 2px", fontSize: vars.textMeta, color: vars.muted });
/** A place to pick: its name, and what relaying there does at the row's end. */
export const place = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", width: "100%", minHeight: "34px",
  padding: "6px 10px", border: "none", borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: "transparent",
  color: vars.text, fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-on]": { background: vars.accentBg, color: vars.accentText },
  },
});
export const placeName = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const placeNote = style({
  flex: "none", fontSize: vars.textMeta, color: vars.muted,
  selectors: { [`${place}[data-on] &`]: { color: vars.accentText } },
});
/** Why a connect's places could not be read, in line with its rows. */
export const unread = style({ margin: "0", padding: "4px 8px", fontSize: vars.textMeta, color: vars.red });
export const empty = style({ margin: "0", padding: "4px 8px", fontSize: vars.textMeta, color: vars.muted });
export const noteField = style({ display: "grid", gap: "6px" });
export const noteLabel = style({ fontSize: vars.textMeta, color: vars.muted });
