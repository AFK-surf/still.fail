import { globalStyle } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { searchStrokeKeyframes, splashFloatKeyframes } from "./keyframes.css.ts";

/**
 * Corners, after Codex: plain rounding by default; where the browser draws superellipses, rounded rectangles get a
 * superellipse(1.5) corner over a radius a quarter longer. Circles and capsules are never touched.
 */
globalStyle(":root", { vars: { "--corner-shape": "round", "--corner-scale": "1" } });
globalStyle(":root", {
  "@supports": {
    "(corner-shape: superellipse(1.5))": {
      vars: { "--corner-shape": "superellipse(1.5)", "--corner-scale": "1.25" },
    },
  },
});
/**
 * After Cue's design system (Comma): neutral greys with one brand colour, panes laid into a grey window with a hairline
 * round them, Inter at its optical regular (450). still.fail keeps its orange; the status colours keep their grounds.
 */
globalStyle(":root", {
  colorScheme: "light",
  vars: {
    "--font-body": "\"Inter Variable\", -apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Hiragino Sans GB\", sans-serif",
    "--font-mono": "ui-monospace, SFMono-Regular, Menlo, monospace",
    "--canvas": "#fdfdfd",
    // What floats over the canvas (menus, popovers, frosted): a grey ground of its own, a step darker than the canvas in
    // light and a step lighter in dark, where a shadow does not show.
    "--raised": "#e9e9eb",
    "--window": "#f4f4f5",
    "--sidebar": "#f4f4f5",
    "--surface": "#ffffff",
    "--ring": "#dfe0e2",
    "--pane-shadow": "0 1px 2px rgb(16 24 40 / .06), 0 1px 3px rgb(16 24 40 / .08)",
    "--list": "#fafafa",
    "--text": "#1a1b1e",
    "--muted": "#5b5e63",
    "--subtle": "#7f8286",
    "--line": "#e7e8ea",
    "--line-strong": "#c9cbce",
    "--hover": "rgb(26 27 30 / .05)",
    "--selected": "#e8e8ea",
    "--paper": "#f4f4f5",
    "--accent": "oklch(68% .175 39)",
    "--accent-text": "oklch(48% .155 38)",
    "--accent-bg": "oklch(96.5% .025 45)",
    "--blue": "oklch(49% .18 260)",
    "--code-inline": "#7C3FA0",
    "--blue-bg": "oklch(96% .02 260)",
    "--green": "oklch(46% .11 158)",
    "--green-bg": "oklch(96% .02 158)",
    "--amber": "oklch(48% .10 73)",
    "--amber-bg": "oklch(97% .028 85)",
    "--red": "oklch(48% .15 22)",
    "--red-bg": "oklch(97% .02 22)",
    "--neutral-bg": "#f1f1f2",
    "--overlay": "rgb(17 18 19 / .2)",
    "--shadow": "rgb(16 24 40 / .10)",
    "--primary": "#24272b",
    "--primary-hover": "#41464c",
    "--on-primary": "#fff",
    "--field-hover": "#9a9ea3",
    "--field-focus": "#646970",
    "--online": "oklch(68% .15 150)",
    "--r-field": `calc(12px * ${vars.cornerScale})`,
    "--r-card": `calc(20px * ${vars.cornerScale})`,
    "--r-dialog": `calc(32px * ${vars.cornerScale})`,
    "--r-nav": `calc(10px * ${vars.cornerScale})`,
    "--r-menu": `calc(16px * ${vars.cornerScale})`,
    "--r-option": `calc(12px * ${vars.cornerScale})`,
    "--text-xs": "12px",
    "--text-sm": "13px",
    "--text-body": "14px",
    "--text-md": "16px",
    "--text-lg": "22px",
    "--ease-out": "cubic-bezier(.16, 1, .3, 1)",
    "--dur": "140ms",
  },
});
/** Dark, after Cue's: a near-black window, panes a step lighter, what is laid on them a step more. */
const dark = {
  colorScheme: "dark",
  vars: {
    "--canvas": "#18191b",
    "--raised": "#2a2b2e",
    "--window": "#0f0f10",
    "--sidebar": "#0f0f10",
    "--surface": "#222326",
    "--ring": "#2e2f32",
    "--pane-shadow": "0 1px 3px rgb(0 0 0 / .5)",
    "--list": "#1d1e20",
    "--text": "#f1f1f2",
    "--muted": "#a4a5a9",
    "--subtle": "#7e8187",
    "--line": "#2a2b2e",
    "--line-strong": "#3a3b3f",
    "--hover": "rgb(255 255 255 / .05)",
    "--selected": "#26272a",
    "--paper": "#222326",
    "--accent": "oklch(72% .16 42)",
    "--accent-text": "oklch(78% .13 45)",
    "--accent-bg": "oklch(30% .05 40)",
    "--blue": "oklch(75% .12 260)",
    "--code-inline": "#C9A2E6",
    "--blue-bg": "oklch(30% .05 260)",
    "--green": "oklch(76% .12 158)",
    "--green-bg": "oklch(30% .04 158)",
    "--amber": "oklch(80% .12 80)",
    "--amber-bg": "oklch(32% .05 80)",
    "--red": "oklch(74% .14 22)",
    "--red-bg": "oklch(30% .05 22)",
    "--neutral-bg": "#27282b",
    "--overlay": "rgb(0 0 0 / .5)",
    "--shadow": "rgb(0 0 0 / .45)",
    "--primary": "#f1f1f2",
    "--primary-hover": "#d1d1d1",
    "--on-primary": "#18191b",
    "--field-hover": "#5d6066",
    "--field-focus": "#8a8d93",
  },
};
globalStyle(":root:not([data-theme=\"light\"])", { "@media": { "(prefers-color-scheme: dark)": dark } });
globalStyle(":root[data-theme=\"dark\"]", dark);
globalStyle("*, *::before, *::after", { boxSizing: "border-box" });
globalStyle("html, body, #app", { height: "100%", margin: "0" });
globalStyle("body", {
  background: vars.canvas, color: vars.text, font: `450 ${vars.textBody}/1.55 ${vars.fontBody}`,
  fontFeatureSettings: "\"cv11\", \"ss01\"", fontOpticalSizing: "auto", WebkitFontSmoothing: "antialiased", lineBreak: "strict",
  textWrap: "pretty",
});
/**
 * Headings and the short lines under them break evenly, never one long line and a stub, and only where the words
 * allow: at punctuation and spaces, not inside a word (模|型) or a bracket; a run too long for the line still breaks.
 */
globalStyle("h1, h2, h3", { textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere" });
globalStyle("button, input, select, textarea", { font: "inherit", color: "inherit" });
/**
 * Reached by the keyboard, a control shows a soft ring in the accent round it (after Cue's focus ring), in place of the
 * browser's. No weight of its own: whatever a control says about its focus wins.
 */
globalStyle(":where(a, button, summary, [role=\"button\"], [role=\"tab\"], [role=\"menuitem\"], [tabindex]):focus-visible", {
  outline: `3px solid color-mix(in srgb, ${vars.accent} 38%, transparent)`, outlineOffset: "1px",
});
// The browser pads a button 1px 6px: an icon button narrower than its icon plus that pushes the icon off center.
globalStyle("button", { padding: "0" });
globalStyle("a", { color: "inherit", textDecoration: "none" });
globalStyle("code, pre", { fontFamily: vars.fontMono });
globalStyle("[hidden]", { display: "none !important" });
globalStyle("*, *::before, *::after", {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animationDuration: "1ms !important", transitionDuration: "1ms !important",
    },
  },
});
/** The app starting: the buddy floats; what it waits for comes up only if it takes a while. */
globalStyle(".splash", {
  position: "fixed", inset: "0", display: "grid", placeContent: "center", justifyItems: "center", gap: "16px",
  padding: "24px", background: vars.canvas, textAlign: "center",
});
globalStyle(".splash-mark", { display: "block", animation: `${splashFloatKeyframes} 1.8s ease-in-out infinite` });
globalStyle(".splash-mark", {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
globalStyle("body[data-resizing]", { cursor: "col-resize", userSelect: "none" });
/** The page itself never scrolls or bounces; only the panes inside do. */
globalStyle("html, body", { height: "100%", overflow: "hidden", overscrollBehavior: "none" });
/**
 * Scrollbars float over what scrolls and take no room (scrollbars.ts draws them): with a mouse the system's are hidden;
 * touch screens keep theirs, which float already.
 */
globalStyle("[data-floating-scrollbars] *", { scrollbarWidth: "none" });
globalStyle("[data-floating-scrollbars] ::-webkit-scrollbar", { display: "none" });
/**
 * A new chat's first message sent, its page becomes the chat: the box it was written in moves down to where the chat's
 * is, and the rest crossfades (cloud/workspace.tsx navigates with a view transition).
 */
globalStyle("::view-transition-group(composer)", { animationDuration: "340ms", animationTimingFunction: vars.easeOut });
globalStyle("::view-transition-old(composer), ::view-transition-new(composer)", { height: "100%", objectFit: "none", objectPosition: "left top" });
globalStyle("::view-transition-old(root), ::view-transition-new(root)", { animationDuration: "260ms" });
/**
 * The desktop composer is not pictured in a page change: the live box shows through, and moves and resizes itself
 * (dock.tsx). Its old picture would fade out as a second composer.
 */
globalStyle("::view-transition-group(dock), ::view-transition-new(dock)", { animation: "none" });
globalStyle("::view-transition-old(dock)", { display: "none" });
globalStyle("::view-transition-group(*), ::view-transition-old(*), ::view-transition-new(*)", {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none",
    },
  },
});
/** The words a search found, marked in the message it opened, until the chat is left. */
globalStyle("::highlight(search-hit)", {
  // Bold without laying the words out anew (a highlight cannot change the font): the glyphs drawn a little wider.
  color: vars.text, textShadow: "0.35px 0 0 currentColor, -0.35px 0 0 currentColor",
});
/** Under each, a hand-drawn stroke in the accent (Chat.tsx drawStrokes), drawn in left to right, one after another. */
globalStyle("[data-search-marks]", { position: "absolute", inset: "0", pointerEvents: "none" });
globalStyle("[data-search-marks] svg", { position: "absolute", overflow: "visible" });
globalStyle("[data-search-marks] path", {
  fill: "none", stroke: vars.accent, strokeWidth: "3", strokeLinecap: "round", vectorEffect: "non-scaling-stroke",
  strokeDasharray: "1", strokeDashoffset: "1", animation: `${searchStrokeKeyframes} 520ms cubic-bezier(.4, 0, .2, 1) forwards`,
});
globalStyle("[data-search-marks][data-settled] path", { animation: "none", strokeDashoffset: "0" });
globalStyle("[data-search-marks] path", { "@media": { "(prefers-reduced-motion: reduce)": { animation: "none", strokeDashoffset: "0" } } });
/** The quoted passage, highlighted where it was said after following a quote. */
globalStyle("::highlight(quote-flash)", {
  backgroundColor: `color-mix(in srgb, ${vars.accent} 28%, transparent)`, color: "inherit",
});
globalStyle(":root[data-quote-flash=\"fading\"] ::highlight(quote-flash)", { backgroundColor: `color-mix(in srgb, ${vars.accent} 12%, transparent)` });
