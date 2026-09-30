import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeKeyframes } from "./styles/keyframes.css.ts";

/**
 * How the connection is, over the top of a chat: frosted like the composer, centred, one line. Only while something
 * is not as it should be (connecting, catching up, down), and a moment after it is again.
 */
export const connection = style({
  position: "absolute", top: "12px", left: "50%", transform: "translateX(-50%)", zIndex: "6",
  display: "flex", alignItems: "center", gap: "8px", maxWidth: "calc(100% - 32px)", height: "30px", padding: "0 6px 0 12px",
  borderRadius: "999px", fontSize: vars.textSm, color: vars.text, whiteSpace: "nowrap",
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, WebkitBackdropFilter: "blur(20px)", backdropFilter: "blur(20px)",
  boxShadow: "0 1px 3px rgb(0 0 0 / .06)",
  animation: `${fadeKeyframes} 160ms ${vars.easeOut}`,
  transition: `opacity 400ms ${vars.easeOut}`,
  selectors: {
    '&[data-tone="trouble"]': { color: vars.red },
    '&[data-tone="back"]': { color: vars.muted, paddingRight: "12px" },
    '&[data-tone="busy"]': { paddingRight: "12px" },
    "&[data-leaving]": { opacity: "0" },
  },
});
export const connectionMark = style({ width: "12px", flex: "none", display: "grid", placeItems: "center" });
export const connectionText = style({ minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
export const connectionDetail = style({ color: vars.muted, minWidth: "0", overflow: "hidden", textOverflow: "ellipsis" });
/** The dot of a connection that came back: quiet grey, it is only saying so. */
export const connectionBack = style({ width: "6px", height: "6px", borderRadius: "50%", background: vars.muted });
export const connectionRetry = style({
  flex: "none", height: "22px", padding: "0 10px", borderRadius: "999px", border: "0", cursor: "pointer",
  background: vars.hover, color: vars.text, fontSize: vars.textSm,
  selectors: { "&:hover": { background: vars.line } },
});
/** On the phone's chat page: under its bar, which the messages run under. */
export const connectionPhone = style({ position: "fixed", top: "calc(var(--m-top) + 64px)" });
