import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

export const trigger = style({ display: "inline-flex", alignItems: "center", gap: "5px", flexShrink: 0, padding: "6px 0", border: 0, background: "none", color: vars.accentText, fontSize: "12px", lineHeight: "18px", cursor: "pointer", whiteSpace: "nowrap", borderRadius: "6px", outline: "none", selectors: { "&:focus-visible": { boxShadow: `0 0 0 2px ${vars.fieldFocus}` } } });
export const dot = style({ width: "6px", height: "6px", borderRadius: "50%", background: "currentColor", flexShrink: 0 });
export const popover = style({ display: "flex", alignItems: "center", gap: "12px", maxWidth: "min(340px, calc(100vw - 24px))", padding: "12px 10px 12px 16px", zIndex: 100, borderRadius: vars.rCard, background: `color-mix(in srgb, ${vars.raised} 88%, transparent)`, backdropFilter: "blur(20px)", boxShadow: `0 6px 24px ${vars.shadow}`, color: vars.text, fontSize: "13px", lineHeight: "19px", outline: "none" });
export const words = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: 0 });
export const title = style({ fontWeight: "500" });
export const detail = style({ color: vars.muted, fontSize: "12px", lineHeight: "17px", overflowWrap: "anywhere" });
export const update = style({ display: "inline-flex", alignItems: "center", gap: "4px", padding: "8px 0", border: 0, background: "none", font: "inherit", color: vars.accentText, fontWeight: "500", whiteSpace: "nowrap", cursor: "pointer", flexShrink: 0, selectors: { "&:disabled": { opacity: .6, cursor: "default" } } });
export const dismiss = style({ display: "grid", placeItems: "center", width: "32px", height: "32px", padding: 0, border: 0, background: "none", color: vars.muted, cursor: "pointer", flexShrink: 0 });
export const arrow = style({ fill: `color-mix(in srgb, ${vars.raised} 88%, transparent)` });
