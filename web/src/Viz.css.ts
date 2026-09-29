import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** An inline visualization: the frame on the message's own ground, a small link to the file below it. */
export const viz = style({ width: "100%", minWidth: 0, margin: "0 0 4px", selectors: { "&:last-child": { marginBottom: 0 } } });
/** Under the frame, out of its way (the figure's own controls sit in its corners): the way to open it on its own. */
export const vizBar = style({ display: "flex", justifyContent: "flex-end", height: "22px", marginTop: "2px" });
/** 在侧边打开: quiet under the figure, the chat's own grey, clearer on hover. */
export const vizOpen = style({
  display: "inline-flex", alignItems: "center", gap: "4px",
  height: "22px", padding: "0 8px", border: "0", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "none", color: vars.subtle, fontSize: "11px", cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
export const vizFrame = style({ display: "block", width: "100%", border: "0", background: "transparent" });
/** A frame taking the room it is given (a side panel's tab, a phone's page). */
export const vizFill = style({ display: "block", width: "100%", height: "100%", border: "0", background: "transparent" });
export const vizPanel = style({ flex: "1", minHeight: 0, height: "100%", padding: "12px 16px", boxSizing: "border-box", overflow: "hidden" });
/** Where a visualization comes while its file is fetched: its least height, quietly. */
export const vizWait = style({ height: "120px", margin: "0 0 8px", borderRadius: `calc(12px * ${vars.cornerScale})`, background: vars.paper });
export const vizNote = style({ padding: "24px", color: vars.muted, fontSize: vars.textSm });
