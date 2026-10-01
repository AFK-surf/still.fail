// The narrow screen's footprint page (Usage.tsx): its notes, sizes and the words of its clean-ups.
import { globalStyle, style } from "@vanilla-extract/css";
import { mScroll } from "./styles/pages.css.ts";

export const mNote = style({ margin: "0 0 8px", padding: "0 24px", fontSize: "13px", color: "var(--m-muted)" });
export const mSize = style({ flex: "none", color: "var(--m-muted)", fontSize: "14px", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const mAction = style({ flex: "none", color: "var(--m-accent)", fontWeight: "500", selectors: { "&[data-danger]": { color: "var(--m-red)" } } });
export const mAgain = style({ display: "block", marginTop: "10px", padding: "0", background: "none", border: "0" });
// Over the phone's `button { font: inherit; color: inherit }` (root.css.ts).
globalStyle(`${mScroll} button${mAgain}`, { color: "var(--m-accent)", fontSize: "13px" });
export const mNested = style({ display: "flex", flex: "1", minWidth: "0", selectors: { "&[data-nested]": { paddingLeft: "14px" } } });
