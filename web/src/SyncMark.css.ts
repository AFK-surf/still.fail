// The list's catching up (SyncMark.tsx): the refresh mark in the middle of a key's room, the ring close round it as the
// update key's (lineStrong under, the accent from the top as far as it has come; turning while that is not known).
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { spinKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

export const syncMark = style({
  position: "relative", display: "inline-grid", placeItems: "center", flex: "none", color: vars.muted, outline: "none",
});
export const syncRing = style({
  position: "absolute", inset: 0, margin: "auto", fill: "none", strokeWidth: 2, strokeLinecap: "round",
  transition: `stroke-dasharray ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-unknown]": { animation: `${spinKeyframes} 0.8s linear infinite` } },
});
globalStyle(`${STILL} ${syncRing}[data-unknown]`, stillLoop("turn"));
export const syncTrack = style({ stroke: vars.lineStrong });
export const syncArc = style({ stroke: vars.accent });
