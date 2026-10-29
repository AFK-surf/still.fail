import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { MESSAGE_FILE_CORNER } from "./Chat.css.ts";

/** A chat's things (Things.tsx): the kinds and the field, then the chosen kind's, the pictures a grid, the rest rows. */
export const things = style({ flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", padding: "0 16px 24px" });
export const thingsHead = style({ display: "flex", flexDirection: "column", gap: "8px", padding: "12px 0" });
export const thingsKind = style({ fontSize: vars.textUi, fontWeight: "500" });
export const thingsNone = style({ margin: "0", padding: "12px 0", fontSize: vars.textMeta, color: vars.muted });
export const thingsMore = style({ display: "flex", justifyContent: "center", padding: "8px 0" });
/** The pictures: as many across as leave each 96 at least, 4 apart, square. */
export const thingsGrid = style({ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))", gap: "4px" });
export const tile = style({
  position: "relative", aspectRatio: "1", padding: "0", border: "0", overflow: "hidden", cursor: "pointer",
  borderRadius: MESSAGE_FILE_CORNER, cornerShape: vars.cornerShape, background: vars.neutralBg,
});
/** Its picture (a video's still) covering it. */
export const tilePicture = style({ width: "100%", height: "100%", objectFit: "cover", display: "block" });
export const tilePlay = style({ position: "absolute", inset: "0", display: "flex", alignItems: "center", justifyContent: "center", color: "#fff" });
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
/** A pull request's mark: grey, red where something is wrong with it. */
export const pullMark = style({ flex: "none", color: vars.muted, selectors: { "&[data-wrong]": { color: vars.red } } });
