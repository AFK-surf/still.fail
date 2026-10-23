import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** A screen's row: as tall as a folder's on the same page; beside it, a tab's actions. */
export const row = style({ minHeight: "52px", flex: "1", minWidth: "0" });
export const item = style({ display: "flex", alignItems: "center", gap: "4px" });
/** A tab's chat and closing it, after its row. */
export const actions = style({ display: "flex", alignItems: "center", gap: "2px", flex: "none" });
/** The core's line under a screen's name (what it is, its size, who is on it), or why there are none. */
export const line = style({ minWidth: "0", color: vars.muted, fontSize: vars.textMeta, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** What the station lacks (a grant to turn on): the only thing here in colour. */
export const off = style({ color: vars.amber });
/** Only said, not opened: no ground under the pointer. */
export const still = style({ selectors: { "&:hover": { background: "none" } } });
