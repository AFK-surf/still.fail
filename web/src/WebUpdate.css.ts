import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const notice = style({
  position: "fixed", zIndex: 150, top: "calc(env(safe-area-inset-top, 0px) + 12px)", left: "50%",
  transform: "translateX(-50%)", display: "flex", alignItems: "center", gap: 12,
  width: "max-content", maxWidth: "calc(100vw - 24px)", padding: "8px 10px 8px 16px",
  borderRadius: vars.rCard, background: `color-mix(in srgb, ${vars.raised} 92%, transparent)`,
  backdropFilter: "blur(20px)", boxShadow: "0 2px 12px #00000018", color: vars.text,
  fontSize: vars.textSm, lineHeight: "24px", whiteSpace: "nowrap",
  "@media": { "(max-width: 767px)": { top: "calc(env(safe-area-inset-top, 0px) + 64px)" } },
});
export const refresh = style({
  border: 0, borderRadius: vars.rField, padding: "4px 10px", font: "inherit", cursor: "pointer",
  color: vars.onPrimary, background: vars.primary,
  ":hover": { background: vars.primaryHover },
});
export const later = style({
  border: 0, padding: "4px 6px", font: "inherit", cursor: "pointer", background: "none", color: vars.muted,
  ":hover": { color: vars.text },
});
