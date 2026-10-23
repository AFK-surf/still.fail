import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** The dialog's search, its places, then the note: one column. */
export const body = style({ display: "grid", gap: "12px", minWidth: "0" });
/** The places, scrolling within the dialog. */
export const list = style({ display: "grid", gap: "2px", maxHeight: "300px", overflowY: "auto", minHeight: "0" });
/** 「最近用过」 over the places relayed to before. */
export const groupHead = style({ padding: "2px 8px", fontSize: vars.textMeta, color: vars.muted });
/** The workspaces to look in, when there are several: all, or one, each with its platform's mark. */
export const scopes = style({ display: "flex", flexWrap: "wrap", gap: "6px" });
export const scope = style({
  display: "inline-flex", alignItems: "center", gap: "5px", height: "26px", padding: "0 10px", border: "none",
  borderRadius: "999px", background: `color-mix(in srgb, ${vars.text} 6%, transparent)`, color: vars.muted,
  fontSize: vars.textMeta, cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover:not([data-on])": { color: vars.text },
    "&[data-on]": { background: vars.text, color: vars.canvas },
  },
});
/** A place to pick: its platform's mark, its name, its workspace (among several), and what relaying there does. */
export const place = style({
  display: "flex", alignItems: "center", gap: "8px", width: "100%", minHeight: "34px",
  padding: "6px 10px", border: "none", borderRadius: vars.rOption, cornerShape: vars.cornerShape, background: "transparent",
  color: vars.text, fontSize: vars.textUi, textAlign: "left", cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-on]": { background: vars.accentBg, color: vars.accentText },
  },
});
export const placeName = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const placeWhere = style({
  flex: "none", fontSize: vars.textMeta, color: vars.muted,
  selectors: { [`${place}[data-on] &`]: { color: vars.accentText } },
});
export const placeNote = style({
  flex: "none", marginLeft: "auto", fontSize: vars.textMeta, color: vars.muted,
  selectors: { [`${place}[data-on] &`]: { color: vars.accentText } },
});
/** On the place picked: picking another instead. */
export const change = style({ fontWeight: "500" });
/** 「显示全部」 under the places relayed to before. */
export const more = style({
  justifySelf: "start", padding: "4px 8px", border: "none", background: "transparent", color: vars.accentText,
  fontSize: vars.textMeta, cursor: "pointer",
});
/** Why a connect's places could not be read, in line with its rows. */
export const unread = style({ margin: "0", padding: "4px 8px", fontSize: vars.textMeta, color: vars.red });
export const empty = style({ margin: "0", padding: "4px 8px", fontSize: vars.textMeta, color: vars.muted });
export const noteField = style({ display: "grid", gap: "6px" });
export const noteLabel = style({ fontSize: vars.textMeta, color: vars.muted });
/** Which bot the agent speaks through there, under the place picked: in line with the place's name (the row's 10 in,
 * its mark's 16 and the 8 after it). */
export const via = style({ display: "flex", alignItems: "center", flexWrap: "wrap", margin: "0", padding: "2px 10px 0 34px", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "pre" });
/** The bot: its picture before its name. */
export const viaBot = style({ display: "inline-flex", alignItems: "center", gap: "4px", color: vars.text });
