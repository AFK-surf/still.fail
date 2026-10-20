// A toast (toast.tsx): a short line at the bottom of the window, in the middle.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeKeyframes, toastInKeyframes } from "./styles/keyframes.css.ts";

export const toastViewport = style({
  // The window's width, its toast in the middle (centred by moving it half its own width, a long one was held to half
  // the window and ran off both sides).
  position: "fixed", left: "16px", right: "16px", bottom: "24px", zIndex: "80", margin: "0", display: "flex",
  flexDirection: "column", alignItems: "center", padding: "0", listStyle: "none", outline: "none", pointerEvents: "none",
});
export const toast = style({
  padding: "9px 18px", borderRadius: "20px", background: vars.primary, color: vars.onPrimary, fontSize: vars.textUi,
  // A long message (an error with its URL) wraps inside the window instead of running off both sides.
  maxWidth: "560px", overflowWrap: "anywhere", textWrap: "pretty", pointerEvents: "auto", boxShadow: `0 8px 24px ${vars.shadow}`,
  animation: `${toastInKeyframes} 200ms ${vars.easeOut}`,
  selectors: {
    "&[data-state=\"closed\"]": { animation: `${fadeKeyframes} 150ms ${vars.easeOut} reverse forwards` },
  },
});
