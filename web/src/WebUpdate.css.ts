import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const notice = style({
  position: "fixed", zIndex: 150, bottom: "calc(env(safe-area-inset-bottom, 0px) + 12px)", left: "calc(env(safe-area-inset-left, 0px) + 12px)",
  display: "flex", alignItems: "center", gap: 12,
  width: "max-content", maxWidth: "calc(100vw - 24px)", padding: "8px 10px 8px 16px",
  borderRadius: vars.rCard, background: `color-mix(in srgb, ${vars.raised} 92%, transparent)`,
  backdropFilter: "blur(20px)", boxShadow: "0 2px 12px #00000018", color: vars.text,
  fontSize: vars.textSm, lineHeight: "24px", whiteSpace: "nowrap",
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

/** An ordinary footer row: it takes space inside the sidebar and follows it when resized or closed. */
export const sidebar = style({
  display: "flex", alignItems: "center", gap: 4, minWidth: 0, padding: "2px 4px 2px 10px",
  fontSize: vars.textSm, lineHeight: "20px", color: vars.text,
});
export const sidebarRefresh = style({
  display: "flex", alignItems: "center", gap: 8, flex: 1, minWidth: 0,
  border: 0, padding: "6px 0", background: "none", color: "inherit", font: "inherit", textAlign: "left", cursor: "pointer",
  ":hover": { color: vars.accentText },
});
