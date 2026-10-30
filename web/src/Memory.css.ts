import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { cardGround } from "./styles/pages.css.ts";

export const memoryDoc = style({ fontSize: vars.textBody });
/** A row of a list card (pages.css.ts listRow), a link or a button. */
export const memoryRow = style({
  width: "100%", border: "0", background: "none", color: vars.text, font: "inherit", textAlign: "left",
  textDecoration: "none", cursor: "pointer",
});
export const memoryRowTitle = style({ display: "flex", alignItems: "baseline", gap: "8px", minWidth: "0" });
export const memoryRowSub = style({ fontSize: vars.textMeta, color: vars.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const memoryRowValue = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted });
export const memoryChevron = style({ flex: "none", color: vars.subtle });
export const memoryTag = style({ flex: "none", fontSize: vars.textMeta, color: vars.subtle });
export const memoryConflict = style({ margin: "0", fontSize: vars.textMeta, color: vars.amber });
/** Which stations have a shared skill. */
export const memoryUsers = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted });
export const memoryNone = style({ margin: "0", fontSize: vars.textUi });
/** A page's head: when it is read, and its sharing. */
export const memoryHead = style({ marginBottom: "16px" });
export const memoryWhen = style({ marginBottom: "16px", fontSize: vars.textUi, color: vars.muted });
globalStyle(`${memoryHead} ${memoryWhen}`, { marginBottom: "0" });
globalStyle(`${memoryWhen} b`, { display: "block", marginBottom: "2px", fontSize: vars.textMeta, fontWeight: "500", color: vars.subtle });
/** The pages to pick between: pills as wide as their words. */
export const memoryChips = style({ display: "flex", flexWrap: "wrap", gap: "6px", marginBottom: "20px" });
export const memoryChip = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "30px", padding: "0 12px", border: "0",
  borderRadius: "999px", background: cardGround, color: vars.text, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-on]": { background: vars.text, color: vars.canvas },
  },
});
// (its count smaller, in the chip's own colour: at 60% it was 4:1, docs/ui-panels.md 对比度)
globalStyle(`${memoryChip} span`, { fontSize: vars.textMeta });
globalStyle(`${memoryDoc} > :first-child`, { marginTop: "0" });
globalStyle(`${memoryDoc} > :last-child`, { marginBottom: "0" });
