import { keyframes, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { glass } from "./styles/glass.ts";

const sweep = keyframes({ from: { transform: "translateX(-100%)" }, to: { transform: "translateX(250%)" } });

export const trigger = style({ display: "inline-flex", alignItems: "center", gap: "5px", flexShrink: 0, padding: "6px 0", border: 0, background: "none", color: vars.accentText, fontSize: vars.textMeta, lineHeight: "18px", cursor: "pointer", whiteSpace: "nowrap", borderRadius: "6px", outline: "none", selectors: { "&:focus-visible": { boxShadow: `0 0 0 2px ${vars.fieldFocus}` }, '&[data-tone="trouble"]': { color: vars.red } } });
export const dot = style({ width: "6px", height: "6px", borderRadius: "50%", background: "currentColor", flexShrink: 0 });
export const popover = style({ display: "flex", flexDirection: "column", gap: "8px", width: "min(288px, calc(100vw - 24px))", boxSizing: "border-box", padding: "12px 10px 12px 14px", zIndex: 100, borderRadius: vars.rCard, ...glass, boxShadow: `0 6px 24px ${vars.shadow}`, color: vars.text, fontSize: vars.textUi, lineHeight: "19px", outline: "none" });
export const head = style({ display: "flex", alignItems: "flex-start", gap: "8px" });
export const words = style({ display: "flex", flexDirection: "column", gap: "2px", minWidth: 0, flex: 1 });
export const title = style({ display: "flex", alignItems: "baseline", gap: "8px", minWidth: 0 });
export const name = style({ fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0 });
export const state = style({ flexShrink: 0, fontSize: vars.textMeta, color: vars.accentText, selectors: { '[data-tone="trouble"] &': { color: vars.red } } });
export const detail = style({ color: vars.muted, fontSize: vars.textMeta, lineHeight: "17px", overflowWrap: "anywhere" });
export const bar = style({ position: "relative", height: "3px", marginRight: "4px", borderRadius: "2px", overflow: "hidden", background: `color-mix(in srgb, ${vars.accent} 18%, transparent)` });
export const fill = style({ position: "absolute", inset: "0 auto 0 0", borderRadius: "inherit", background: vars.accent, transition: "width .3s ease" });
export const sweeping = style({ width: "40%", animation: `${sweep} 1.4s ease-in-out infinite`, "@media": { "(prefers-reduced-motion: reduce)": { animation: "none", width: "100%", opacity: .35 } } });
export const foot = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", minHeight: "24px", marginRight: "4px" });
export const versions = style({ color: vars.muted, fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "16px", fontVariantNumeric: "tabular-nums", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", minWidth: 0 });
export const update = style({ display: "inline-flex", alignItems: "center", gap: "4px", marginLeft: "auto", padding: "4px 10px", border: 0, borderRadius: "999px", background: vars.accentBg, font: "inherit", fontSize: vars.textMeta, lineHeight: "16px", color: vars.accentText, fontWeight: "500", whiteSpace: "nowrap", cursor: "pointer", flexShrink: 0, selectors: { "&:disabled": { opacity: .6, cursor: "default" } } });
export const dismiss = style({ display: "grid", placeItems: "center", width: "24px", height: "24px", margin: "-3px 0 -3px 0", padding: 0, border: 0, borderRadius: "6px", background: "none", color: vars.muted, cursor: "pointer", flexShrink: 0, selectors: { "&:hover": { background: vars.fieldHover, color: vars.text } } });
