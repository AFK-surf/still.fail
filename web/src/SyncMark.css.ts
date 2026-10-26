// The list's catching up (SyncMark.tsx): the refresh mark in the middle of a key's room, turning; done, a tick in its
// place (each growing from 0.6 as it comes, 200 ms), then the whole fading (400 ms).
import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

const turn = keyframes({ from: { transform: "rotate(0deg)" }, to: { transform: "rotate(360deg)" } });

export const syncMark = style({
  position: "relative", display: "inline-grid", placeItems: "center", flex: "none", color: vars.muted, outline: "none",
  transition: "opacity 400ms ease-in", selectors: { '&[data-phase="out"]': { opacity: 0 } },
});
const part = { gridArea: "1 / 1", display: "grid", placeItems: "center", transition: "opacity 200ms ease-out, transform 200ms ease-out" } as const;
export const syncTurning = style({ ...part, animation: `${turn} 1.4s cubic-bezier(0.45, 0.05, 0.55, 0.95) infinite` });
globalStyle(`${STILL} ${syncTurning}`, stillLoop("turn"));
export const syncTick = style({ ...part, opacity: 0, transform: "scale(0.6)" });
globalStyle(`${syncMark}:is([data-phase="done"], [data-phase="out"]) ${syncTurning}`, { opacity: 0, transform: "scale(0.6)", animation: "none" });
globalStyle(`${syncMark}:is([data-phase="done"], [data-phase="out"]) ${syncTick}`, { opacity: 1, transform: "none" });
