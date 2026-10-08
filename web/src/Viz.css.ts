import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** An inline visualization: the frame on the message's own ground, a small link to the file below it. */
export const viz = style({ width: "100%", minWidth: 0, margin: "0 0 4px", selectors: { "&:last-child": { marginBottom: 0 } } });
/** Under the frame, out of its way (the figure's own controls sit in its corners): the way to open it on its own. */
export const vizBar = style({ display: "flex", justifyContent: "flex-end", gap: "2px", height: "22px", marginTop: "2px" });
/** 全屏打开, 在侧边打开: icons quiet under the figure, the chat's own grey, clearer on hover (what they do is their tip). */
export const vizOpen = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "4px",
  width: "22px", height: "22px", padding: "0", border: "0", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "none", color: vars.subtle, fontSize: vars.textCaption, cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
export const vizFrame = style({ display: "block", width: "100%", border: "0", background: "transparent" });
/** A whole page placed in a message: a 16:9 window of the message's width, its corners the card's. */
export const vizPage = style({
  display: "block", width: "100%", aspectRatio: "16 / 9", maxHeight: "80vh", border: "0",
  borderRadius: vars.rCard, cornerShape: vars.cornerShape, background: vars.paper,
});
/** Where a visualization's frame comes while its file is fetched, as tall as the frame will be (Viz.tsx sets it), quietly. */
export const vizWait = style({ borderRadius: `calc(12px * ${vars.cornerScale})`, background: vars.paper });
export const vizNote = style({ padding: "24px", color: vars.muted, fontSize: vars.textSecondary });
