import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** An inline visualization: the frame on the message's own ground, a small switch to its source below it. */
export const viz = style({ width: "100%", minWidth: 0, margin: "0 0 4px", selectors: { "&:last-child": { marginBottom: 0 } } });
/** Under the frame, out of its way (the figure's own controls sit in its corners): the switch, shown on hover. */
export const vizBar = style({
  display: "flex", justifyContent: "flex-end", height: "22px", marginTop: "2px",
  opacity: "0", transition: `opacity ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${viz}:hover &`]: { opacity: "1" },
    "&:focus-within": { opacity: "1" },
  },
  "@media": { "(pointer: coarse)": { opacity: "1" } },
});
export const vizToggle = style({
  height: "22px", padding: "0 8px", border: "0", borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "none", color: vars.subtle, fontSize: "11px", cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});
export const vizFrame = style({ display: "block", width: "100%", border: "0", background: "transparent" });
