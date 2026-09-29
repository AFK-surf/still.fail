import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeInKeyframes } from "./styles/keyframes.css.ts";
import { previewBar, previewFrame } from "./Preview.css.ts";
import * as stageCss from "./PreviewStage.css.ts";

/** A web service's place in its chat's side panel: the frame is drawn over it (Previews.tsx). */
export const slot = style({ flex: "1", minHeight: "0" });
/** Over the page, under menus and dialogs; only the frames and the small ones' buttons take the pointer. */
export const layer = style({
  position: "fixed", inset: "0", zIndex: "30", pointerEvents: "none",
  vars: {
    "--pv-glass": "62%",
    "--pv-shadow": "0 8px 24px -6px rgb(0 0 0 / .14), 0 1px 3px rgb(0 0 0 / .06)",
  },
  /** Dark: the glass thicker (over a light page it is not a muddy grey), the shadow deeper. */
  selectors: {
    ":root[data-theme=\"dark\"] &": {
      vars: { "--pv-glass": "84%", "--pv-shadow": "0 10px 28px -6px rgb(0 0 0 / .5), 0 1px 3px rgb(0 0 0 / .3)" },
    },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        ":root:not([data-theme=\"light\"]) &": {
          vars: { "--pv-glass": "84%", "--pv-shadow": "0 10px 28px -6px rgb(0 0 0 / .5), 0 1px 3px rgb(0 0 0 / .3)" },
        },
      },
    },
  },
});
export const frame = style({
  position: "fixed", display: "flex", flexDirection: "column", transformOrigin: "0 0", background: vars.canvas,
  pointerEvents: "auto",
  selectors: {
    "&[data-mode=hidden]": { visibility: "hidden", pointerEvents: "none" },
    "&[data-mode=small]": {
      pointerEvents: "none", overflow: "hidden", borderRadius: `calc(${vars.rCard} / var(--scale, 1))`,
      cornerShape: vars.cornerShape,
    },
  },
});
const glass = {
  background: `color-mix(in srgb, ${vars.raised} var(--pv-glass), transparent)`, WebkitBackdropFilter: "blur(16px) saturate(1.8)",
  backdropFilter: "blur(16px) saturate(1.8)",
} as const;
/** Over a small one's page: its corners and a slight shadow (no edge), its name in a glass capsule, and on hover
 * tucking them away and closing it. */
export const card = style({
  position: "fixed", borderRadius: vars.rCard, cornerShape: vars.cornerShape, cursor: "pointer", outline: "none",
  boxShadow: "var(--pv-shadow)", pointerEvents: "auto",
  selectors: {
    "&[data-mode=hidden]": { visibility: "hidden", pointerEvents: "none" },
    /** Its page comes down into it: it shows as that ends. */
    "&[data-mode=small]": { animation: `${fadeInKeyframes} 120ms ${vars.easeOut} 180ms both` },
    "&:focus-visible": { boxShadow: `0 0 0 2px ${vars.fieldFocus}` },
  },
});
/** Its top and left edges and the corner between them: dragged, the small ones resize (the far corner stays). */
export const edge = style({
  position: "absolute", zIndex: "1",
  selectors: {
    "&[data-edge=top]": { top: "-3px", left: "10px", right: "0", height: "7px", cursor: "ns-resize" },
    "&[data-edge=left]": { left: "-3px", top: "10px", bottom: "0", width: "7px", cursor: "ew-resize" },
    "&[data-edge=corner]": { top: "-10px", left: "-10px", width: "24px", height: "24px", cursor: "nwse-resize" },
  },
});
/** Where to take it: a short round-capped arc just outside its top-left corner, following it (Previews.tsx
 * shapeGrip), shown on hover (stronger on the edges). */
export const grip = style({
  position: "absolute", overflow: "visible", pointerEvents: "none", fill: "none", stroke: vars.muted,
  strokeWidth: "4px", strokeLinecap: "round", strokeLinejoin: "round", opacity: "0",
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${card}:hover &`]: { opacity: ".55" },
    [`${edge}:hover ~ &, :root[data-preview-resizing] &`]: { opacity: "1" },
  },
});
/** While resizing, the cursor stays the edge's wherever the pointer goes, and nothing under it is selected. */
globalStyle(":root[data-preview-resizing=top] *", { cursor: "ns-resize !important", userSelect: "none" });
globalStyle(":root[data-preview-resizing=left] *", { cursor: "ew-resize !important", userSelect: "none" });
globalStyle(":root[data-preview-resizing=corner] *", { cursor: "nwse-resize !important", userSelect: "none" });
export const name = style({
  ...glass,
  position: "absolute", left: "8px", bottom: "8px", display: "flex", alignItems: "center", gap: "6px",
  maxWidth: "calc(100% - 16px)", height: "24px", padding: "0 10px 0 9px", borderRadius: "999px", color: vars.text,
  fontSize: vars.textXs, fontWeight: "500", boxShadow: "0 1px 4px rgb(0 0 0 / .08)",
});
/** Behind the front one (at rest): its page's edge alone. */
globalStyle(`${layer}:not([data-spread]) ${card}[data-front=false] > *`, { visibility: "hidden" });
export const nameText = style({ minWidth: "0", overflow: "hidden", whiteSpace: "nowrap", textOverflow: "ellipsis" });
export const count = style({ flex: "none", color: vars.muted, fontWeight: "400" });
export const dot = style({
  display: "block", flex: "none", width: "6px", height: "6px", borderRadius: "50%", background: vars.green,
  selectors: { "&[data-restarting]": { background: vars.amber } },
});
export const actions = style({
  position: "absolute", top: "8px", right: "8px", display: "flex", gap: "4px", opacity: "0",
  transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${card}:hover &, &:focus-within`]: { opacity: "1" },
  },
});
export const action = style({
  ...glass,
  display: "grid", placeItems: "center", width: "24px", height: "24px", padding: "0", border: "0", borderRadius: "50%",
  color: vars.text, cursor: "pointer", boxShadow: "0 1px 4px rgb(0 0 0 / .08)",
  selectors: {
    "&:hover": { background: vars.raised },
  },
});
/** Tucked away: all of them in a glass capsule in the corner; pointed at, they are laid out over it. */
export const capsule = style({
  ...glass,
  position: "fixed", right: "16px", bottom: "16px", zIndex: "30", display: "flex", alignItems: "center", gap: "7px",
  height: "34px", padding: "0 15px 0 13px", border: "0", borderRadius: "999px", color: vars.text, font: "inherit",
  fontSize: vars.textSm, fontWeight: "500", cursor: "pointer", pointerEvents: "auto",
  boxShadow: "var(--pv-shadow)",
  animation: `${fadeInKeyframes} 160ms ${vars.easeOut}`,
});
globalStyle(`${capsule} svg`, { flex: "none", color: vars.muted });
/** A small one's bar is put away: its page alone shows. */
globalStyle(`${frame}[data-mode=small] ${previewBar}`, { display: "none" });
/** A small one's page of its own size fills its card (the card is in its shape): no ground round it, nothing to drag. */
globalStyle(`${frame}[data-mode=small] ${stageCss.stage}`, { padding: "0", background: "none" });
globalStyle(`${frame}[data-mode=small] :is(${stageCss.edge}, ${stageCss.shade}, ${stageCss.size}, ${stageCss.hold})`, { display: "none" });
/** Its corners are the card's (its own screen's are drawn in the preview beside its chat). */
globalStyle(`${frame}[data-mode=small] ${stageCss.device}`, { borderRadius: "0 !important" });
/** Nor its page's white ground under it: scaled and cut to the corners, it shows round the page's edges as a thin light
 * line (over a dark page); what is behind it is the frame's, the theme's own. */
globalStyle(`${frame}[data-mode=small] ${previewFrame}`, { background: "none" });
