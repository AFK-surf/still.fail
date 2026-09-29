// The note that a step needs a real ember (real.tsx): over the demo, frosted as ember's floating things are.
import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

const fade = keyframes({ from: { opacity: 0 } });
const rise = keyframes({ from: { opacity: 0, transform: "translateY(12px) scale(.97)" } });

export const veil = style({
  position: "fixed", inset: "0", zIndex: "1000", pointerEvents: "auto", display: "grid", placeItems: "center", padding: "24px",
  background: `color-mix(in srgb, ${vars.canvas} 45%, transparent)`, animation: `${fade} .2s ease-out`,
});
export const card = style({
  width: "min(400px, 100%)", padding: "26px 26px 22px", borderRadius: vars.rDialog, textAlign: "center",
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, backdropFilter: "blur(20px)", WebkitBackdropFilter: "blur(20px)",
  boxShadow: `0 20px 50px -20px ${vars.shadow}`, animation: `${rise} .28s ${vars.easeOut}`,
});
export const mark = style({ display: "block", width: "56px", height: "56px", margin: "0 auto 14px" });
export const title = style({ margin: "0 0 20px", fontSize: vars.textMd, fontWeight: "650", color: vars.text });
export const actions = style({ display: "flex", gap: "8px", justifyContent: "center" });
export const button = style({
  display: "inline-flex", alignItems: "center", height: "36px", padding: "0 18px", borderRadius: "999px", border: "0",
  fontSize: vars.textBody, fontWeight: "550", cursor: "pointer", background: vars.hover, color: vars.text,
  selectors: { "&[data-primary]": { background: vars.primary, color: vars.onPrimary } },
});
