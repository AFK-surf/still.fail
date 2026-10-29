import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { STILL, stillAtOnce } from "@stillfail/ui/styles/still.ts";

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
export const vizWait = style({ borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.paper });
/** A frame hidden till it has drawn, over the place held for it (Viz.tsx Frame). */
export const vizHeld = style({ position: "relative", overflow: "hidden" });
/**
 * A frame come once it has drawn, as a message's image comes once loaded (Chat.css.ts msgImageReveal, 2026-10-29: inline
 * HTML 的渲染显示要参考图片的展示逻辑): brushed in from its top, blurred to sharp and from 1.04 its size to its own over
 * 1100ms, the place held for it fading out behind it (300ms, from 800).
 */
const vizRevealKeyframes = keyframes({
  from: { maskPosition: "0 100%", filter: "blur(14px)", transform: "scale(1.04)" },
  to: { maskPosition: "0 0", filter: "blur(0)", transform: "none" },
});
const vizWaitGoneKeyframes = keyframes({ to: { opacity: 0 } });
globalStyle(`${vizHeld} > iframe`, { position: "relative" });
globalStyle(`${vizHeld} > iframe[data-reveal]`, {
  maskImage: "linear-gradient(to bottom, #000 40%, transparent 60%)", maskSize: "100% 250%",
  animation: `${vizRevealKeyframes} 1100ms ${vars.easeOut} both`,
});
globalStyle(`${vizHeld} > [data-gone]`, { animation: `${vizWaitGoneKeyframes} 300ms ${vars.easeOut} 800ms both` });
globalStyle(`${STILL} ${vizHeld} > [data-gone]`, stillAtOnce);
export const vizNote = style({ padding: "24px", color: vars.muted, fontSize: vars.textUi });
