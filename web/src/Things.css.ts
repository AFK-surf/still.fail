import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { MESSAGE_FILE_CORNER } from "./Chat.css.ts";

/** A chat's things (Things.tsx): the kinds and the field, then the chosen kind's, the pictures a grid, the rest rows. */
export const things = style({ flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", padding: "0 16px 24px" });
export const thingsHead = style({ display: "flex", flexDirection: "column", gap: "8px", padding: "12px 0" });
/** The kinds to choose from: across the row, as the field under them is. */
export const thingsKinds = style({ alignSelf: "stretch" });
export const thingsKind = style({ fontSize: vars.textUi, fontWeight: "500" });
export const thingsNone = style({ margin: "0", padding: "12px 0", fontSize: vars.textMeta, color: vars.muted });
export const thingsMore = style({ display: "flex", justifyContent: "center", padding: "8px 0" });
/** The pictures by the day: its heading 12 over it, 8 to its first message; a message's 6 under what it says. */
export const mediaDays = style({ display: "flex", flexDirection: "column" });
export const mediaDay = style({ display: "flex", flexDirection: "column", gap: "8px", paddingBottom: "8px" });
export const mediaDayHead = style({ margin: "0", paddingTop: "12px", fontSize: vars.textUi, fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const mediaGroup = style({ display: "flex", flexDirection: "column", gap: "6px" });
/** When and who (in the quiet grey), then its first words, cut to the line. */
export const mediaSaid = style({ margin: "0", display: "flex", gap: "8px", minWidth: "0", fontSize: vars.textMeta, whiteSpace: "nowrap" });
export const mediaSaidWhen = style({ flex: "none", color: vars.muted });
export const mediaSaidWords = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", color: vars.text });
/** A message's tiles in lines 4 apart, each tile its shape at least the line's height, growing to fill its line. */
export const mediaLines = style({ display: "flex", flexWrap: "wrap", gap: "4px" });
/** After the tiles: the last line's room, so its tiles keep their height. */
export const mediaRest = style({ flex: "1000 1 0", height: "0" });
export const tile = style({
  position: "relative", padding: "0", border: "0", overflow: "hidden", cursor: "pointer", minWidth: "0",
  borderRadius: MESSAGE_FILE_CORNER, cornerShape: vars.cornerShape, background: vars.neutralBg,
});
/** Its picture (a video's still) covering it, its top where it is longer. */
export const tilePicture = style({
  width: "100%", height: "100%", objectFit: "cover", objectPosition: "top", display: "block", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: { [`${tile}:hover &`]: { opacity: "0.85" } },
});
/** A video's length in its foot corner, a capsule concentric with it (18 high: the tile's corner less its half in). */
const LENGTH_IN = `calc(${MESSAGE_FILE_CORNER} - 9px)`;
export const tileLength = style({
  position: "absolute", left: LENGTH_IN, bottom: LENGTH_IN, height: "18px", display: "flex", alignItems: "center", gap: "4px", padding: "0 6px",
  borderRadius: "999px", background: "rgba(0, 0, 0, 0.65)", color: "#fff", fontSize: vars.textCaption,
});
export const thingsRows = style({ display: "flex", flexDirection: "column", gap: "2px" });
/** A row: what opens it (its mark, its two lines) and 在对话中查看 at its end, round as an option, the pointer's ground on it. */
export const row = style({
  display: "flex", alignItems: "center", gap: "4px", paddingRight: "4px", borderRadius: vars.rOption, cornerShape: vars.cornerShape,
  transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover": { background: vars.hover } },
});
export const rowOpen = style({
  flex: "1", minWidth: "0", display: "flex", alignItems: "center", gap: "10px", padding: "8px", border: "0", background: "none",
  color: vars.text, font: "inherit", textAlign: "left", textDecoration: "none", cursor: "pointer",
});
export const rowMark = style({ flex: "none", display: "flex", color: vars.muted });
export const rowWords = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", gap: "2px" });
export const rowName = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textUi, fontWeight: "500" });
export const rowMeta = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontSize: vars.textMeta, color: vars.muted });
/** A pull request's mark: in its state's colour, as its card's pill (Hover.css.ts state). */
export const pullMark = style({
  flex: "none", color: vars.muted,
  selectors: {
    '&[data-state="open"]': { color: vars.green },
    '&[data-state="merged"]': { color: vars.purple },
    '&[data-state="closed"]': { color: vars.red },
  },
});
