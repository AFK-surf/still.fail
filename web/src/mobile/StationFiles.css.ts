// ＋'s Station 文件 and a station's file's card tapped (StationFiles.tsx).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { mSwitchRow } from "./Connects.css.ts";

/** Between the folder as a whole and what is in it: a hairline, in by the rows' padding. */
export const rule = style({ height: "1px", margin: "4px 20px", background: "var(--m-line)" });
/** Where the file is: its station and its folder, under its name. */
export const where = style({ margin: "0", padding: "0 20px 14px", fontSize: vars.textMeta, overflowWrap: "anywhere" });
export const block = style({ display: "grid", gap: "8px", padding: "0 20px 14px" });
export const label = style({ fontSize: vars.textMeta, color: "var(--m-muted)" });
globalStyle(`${block} ${mSwitchRow}`, { width: "100%" });
