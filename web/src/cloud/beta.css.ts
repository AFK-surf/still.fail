import { fallbackVar, globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { sidebar } from "../Sidebar.css.ts";

/** The test channel's mark (beta.tsx): small, frosted like the composer, out of the way of clicks. */
export const mark = style({
  position: "fixed", left: "10px", bottom: "calc(10px + env(safe-area-inset-bottom, 0px))", zIndex: 1000,
  padding: "2px 8px", borderRadius: "999px", pointerEvents: "none", userSelect: "none",
  background: `color-mix(in srgb, ${vars.raised} 72%, transparent)`, WebkitBackdropFilter: "blur(20px)", backdropFilter: "blur(20px)",
  boxShadow: "0 1px 3px rgb(0 0 0 / .06)", color: vars.muted, fontSize: vars.textXs, fontWeight: 600, lineHeight: "18px",
});
// With the sidebar beside the page, at the page's bottom left: the sidebar's foot (stations, account) stays clear.
globalStyle(`:root:has(${sidebar}) ${mark}`, {
  "@media": { "(min-width: 701px)": { left: `calc(${fallbackVar(vars.sidebarW, "240px")} + 10px)` } },
});
