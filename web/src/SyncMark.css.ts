// The list's catching up (SyncMark.tsx): the refresh mark in the middle of a key's room, turning; done, brought to rest
// (SyncMark.tsx settleTurn: `data-ticked` once that is under way, `--settle` what the arrows wait), its arrows drawn back
// along their strokes (180 ms), the tick drawn (240 ms, begun as they are mostly back), then the whole fading (400 ms).
import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

const turn = keyframes({ from: { transform: "rotate(0deg)" }, to: { transform: "rotate(360deg)" } });

export const syncMark = style({
  position: "relative", display: "inline-grid", placeItems: "center", flex: "none", color: vars.muted, outline: "none",
  transition: "opacity 400ms ease-in", selectors: { '&[data-phase="out"]': { opacity: 0 } },
});
const part = { gridArea: "1 / 1", display: "grid", placeItems: "center" } as const;
export const syncTurning = style({ ...part, animation: `${turn} 1.4s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite` });
globalStyle(`${STILL} ${syncTurning}`, stillLoop("turn"));
export const syncTickAt = style(part);
// (a gap past the stroke's end, so none of it is left, not even a round end's dot)
export const syncBack = style({
  strokeDasharray: "1 2", strokeDashoffset: 0,
  transition: "stroke-dashoffset 180ms cubic-bezier(0.4, 0, 0.2, 1) var(--settle, 0ms)",
});
export const syncTick = style({
  strokeDasharray: "1 2", strokeDashoffset: 1.01,
  transition: "stroke-dashoffset 240ms cubic-bezier(0.2, 0.7, 0.2, 1) calc(var(--settle, 0ms) + 108ms)",
});
globalStyle(`${syncMark}[data-ticked] ${syncBack}`, { strokeDashoffset: 1.01 });
globalStyle(`${syncMark}[data-ticked] ${syncTick}`, { strokeDashoffset: 0 });
