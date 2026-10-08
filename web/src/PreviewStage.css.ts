import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { fadeInKeyframes } from "./styles/keyframes.css.ts";

/** Frosted, as the composer is. */
const glass = {
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, WebkitBackdropFilter: "blur(20px) saturate(1.4)",
  backdropFilter: "blur(20px) saturate(1.4)",
} as const;
/** Dark: thicker, so over a light page it is not a muddy grey. */
const thick = `color-mix(in srgb, ${vars.raised} 84%, transparent)`;
const darkGlass = {
  selectors: { ":root[data-theme=\"dark\"] &": { background: thick } },
  "@media": { "(prefers-color-scheme: dark)": { selectors: { ":root:not([data-theme=\"light\"]) &": { background: thick } } } },
} as const;

/** Where the page is: all of it, or (a page of its own size) a ground with the page on it, which may run past it. */
export const stage = style({
  position: "relative", flex: "1", minHeight: "0", overflow: "hidden",
  selectors: {
    "&[data-sized]": { padding: "16px", background: `color-mix(in srgb, ${vars.neutralBg} 55%, ${vars.canvas})`, touchAction: "none" },
    "&[data-dragging]": { cursor: "grabbing" },
  },
});
/** The page's box: the stage's, or its own size drawn at its scale, its corners its screen's (PreviewStage.tsx). */
export const device = style({
  position: "absolute", inset: "0",
  selectors: {
    [`${stage}[data-sized] &`]: { inset: "auto", transformOrigin: "0 0", overflow: "hidden", cornerShape: vars.cornerShape },
  },
});
/** Under the page of its own size, as big as it is drawn: its slight shadow (the page's own would scale with it). */
export const shade = style({
  position: "absolute", transformOrigin: "0 0", cornerShape: vars.cornerShape, pointerEvents: "none",
  boxShadow: "0 8px 24px -8px rgb(0 0 0 / .16), 0 1px 3px rgb(0 0 0 / .06)",
  selectors: {
    ":root[data-theme=\"dark\"] &": { boxShadow: "0 10px 28px -8px rgb(0 0 0 / .5), 0 1px 3px rgb(0 0 0 / .3)" },
  },
});
/** The marks over the page, where it is drawn. */
export const over = style({ position: "absolute", inset: "0", pointerEvents: "none" });
/** Over the page while it is taken hold of (space held, or a touch screen's moving mode): it moves, not clicked. */
export const hold = style({
  position: "absolute", inset: "0", zIndex: "2", cursor: "grab", touchAction: "none",
  selectors: { "&[data-dragging]": { cursor: "grabbing" } },
});
/** An edge of the page of its own size: a soft grip beside it, shown as the stage is pointed at. */
export const edge = style({
  position: "absolute", zIndex: "3", touchAction: "none",
  selectors: {
    "&[data-side=right]": { width: "14px", cursor: "ew-resize" },
    "&[data-side=bottom]": { height: "14px", cursor: "ns-resize" },
    "&[data-side=corner]": { width: "16px", height: "16px", cursor: "nwse-resize" },
    "&::after": {
      content: "\"\"", position: "absolute", borderRadius: "999px", background: vars.muted, opacity: "0",
      transition: `opacity ${vars.dur} ${vars.easeOut}`,
    },
    "&[data-side=right]::after": { left: "5px", top: "50%", width: "4px", height: "36px", marginTop: "-18px" },
    "&[data-side=bottom]::after": { top: "5px", left: "50%", width: "36px", height: "4px", marginLeft: "-18px" },
    "&[data-side=corner]::after": { display: "none" },
    [`${stage}:hover &::after`]: { opacity: ".45" },
    "&:hover::after, :root[data-viewport-resizing] &::after": { opacity: "1" },
  },
});
/** While an edge is dragged: its cursor wherever the pointer goes, nothing selected, the page not taking the pointer. */
globalStyle(":root[data-viewport-resizing=right] *", { cursor: "ew-resize !important", userSelect: "none" });
globalStyle(":root[data-viewport-resizing=bottom] *", { cursor: "ns-resize !important", userSelect: "none" });
globalStyle(":root[data-viewport-resizing=corner] *", { cursor: "nwse-resize !important", userSelect: "none" });
globalStyle(":root[data-viewport-resizing] iframe", { pointerEvents: "none" });
/** Its size, over its bottom edge while it changes (then it fades). */
export const size = style({
  ...glass,
  position: "absolute", zIndex: "3", display: "flex", alignItems: "center", gap: "6px", height: "26px",
  padding: "0 11px", borderRadius: "999px", transform: "translate(-50%, -100%)", pointerEvents: "none",
  boxShadow: "0 1px 4px rgb(0 0 0 / .1)", color: vars.text, fontSize: vars.textLabel, fontWeight: "500",
  whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums", opacity: "0", transition: `opacity 240ms ${vars.easeOut}`,
  selectors: { "&[data-shown]": { opacity: "1", transition: "opacity 80ms linear" } },
});
globalStyle(`${size} span`, { color: vars.muted, fontWeight: "400" });

/** A touch screen's toolbar's place, under the stage, on its ground. */
export const dock = style({
  flex: "none", padding: "0 10px 10px", background: vars.canvas,
  selectors: { "&[data-sized]": { background: `color-mix(in srgb, ${vars.neutralBg} 55%, ${vars.canvas})` } },
});
/** The toolbar: a frosted capsule, the sizes (scrolled sideways), then its tools. */
export const toolbar = style({
  ...glass,
  display: "flex", alignItems: "center", gap: "4px", height: "48px", padding: "0 6px", borderRadius: "999px",
  boxShadow: "0 1px 3px rgb(0 0 0 / .06), 0 6px 20px rgb(0 0 0 / .12)",
  userSelect: "none", WebkitUserSelect: "none", WebkitTouchCallout: "none", touchAction: "pan-x",
  animation: `${fadeInKeyframes} 160ms ${vars.easeOut}`,
  ...darkGlass,
});
export const chips = style({
  flex: "1", minWidth: "0", display: "flex", gap: "2px", overflowX: "auto", scrollbarWidth: "none",
  maskImage: "linear-gradient(to right, #000 calc(100% - 16px), transparent)",
});
export const chip = style({
  flex: "none", height: "36px", padding: "0 13px", border: "0", borderRadius: "999px", background: "none",
  color: vars.muted, font: "inherit", fontSize: vars.textSecondary, whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums",
  selectors: {
    "&[aria-pressed=true]": { background: vars.canvas, color: vars.text, fontWeight: "600", boxShadow: "0 1px 3px rgb(0 0 0 / .1)" },
  },
});
export const tools = style({ flex: "none", display: "flex", alignItems: "center", gap: "2px", paddingLeft: "4px" });
export const tool = style({
  display: "grid", placeItems: "center", width: "36px", height: "36px", border: "0", borderRadius: "50%",
  background: "none", color: vars.text,
  selectors: { "&[aria-pressed=true]": { background: vars.accent, color: "#fff" } },
});
export const fitTool = style({
  height: "36px", padding: "0 12px", border: "0", borderRadius: "999px", background: vars.canvas, color: vars.text,
  font: "inherit", fontSize: vars.textSecondary, fontWeight: "500", whiteSpace: "nowrap",
});
