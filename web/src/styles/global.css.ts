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
 * Zork's approved desktop tokens (apps/zork-design-pc/tokens), so ember reads as
 * part of the same family: white canvas, warm sidebar, ink text, brand orange,
 * status colours with their own tinted grounds. Dark follows the Zork client.
 */
globalStyle(":root", {
  colorScheme: "light",
  vars: {
    "--font-body": "\"Inter Variable\", -apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Hiragino Sans GB\", sans-serif",
    "--font-mono": "ui-monospace, SFMono-Regular, Menlo, monospace",
    "--canvas": "oklch(100% 0 0)",
    // What floats over the canvas (the composer): a grey ground of its own, a step darker than the canvas in light and
    // a step lighter in dark, where a shadow does not show.
    "--raised": "#e4e4e8",
    "--sidebar": "oklch(96.9% .005 85)",
    "--list": "oklch(98.5% .002 85)",
    "--text": "oklch(27% .009 255)",
    "--muted": "oklch(52% .012 255)",
    "--subtle": "oklch(57% .01 255)",
    "--line": "oklch(91% .005 85)",
    "--line-strong": "oklch(82% .008 255)",
    "--hover": "oklch(25% .02 85 / .065)",
    "--selected": "oklch(93% .009 85)",
    "--paper": "oklch(96.3% .012 88)",
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
    "--neutral-bg": "oklch(95% .004 255)",
    "--overlay": "oklch(20% .01 255 / .2)",
    "--shadow": "oklch(20% .01 255 / .10)",
    "--primary": "#24272b",
    "--primary-hover": "#41464c",
    "--on-primary": "#fff",
    "--field-hover": "#9a9ea3",
    "--field-focus": "#646970",
    "--online": "oklch(68% .15 150)",
    "--r-field": `calc(12px * ${vars.cornerScale})`,
    "--r-card": `calc(20px * ${vars.cornerScale})`,
    "--r-dialog": `calc(32px * ${vars.cornerScale})`,
    "--r-nav": `calc(12px * ${vars.cornerScale})`,
    "--r-menu": `calc(20px * ${vars.cornerScale})`,
    "--r-option": `calc(12px * ${vars.cornerScale})`,
    // Six roles, each a size with its line (leading-*): times and tags; a row's second line and notes; lists, menus,
    // buttons and settings; what is read; a section's or dialog's title; a page's. The phone's are a size up
    // (mobile/styles/root.css.ts). Weights are three: 400, 500 to stand out, 600 for titles.
    "--text-caption": "11px", "--leading-caption": "16px",
    "--text-meta": "12px", "--leading-meta": "18px",
    "--text-ui": "13px", "--leading-ui": "20px",
    "--text-body": "14px", "--leading-body": "22px",
    // What is typed in: as what is read (the phone's 16, iOS zooms into less).
    "--text-input": "14px",
    "--text-title": "16px", "--leading-title": "24px",
    "--text-heading": "22px", "--leading-heading": "30px",
    // Big numbers (usage).
    "--text-display": "28px",
    "--ease-out": "cubic-bezier(.2, .7, .2, 1)",
    "--dur": "140ms",
  },
});
globalStyle(":root:not([data-theme=\"light\"])", {
  "@media": {
    "(prefers-color-scheme: dark)": {
      colorScheme: "dark",
      vars: {
        "--canvas": "#1f2023",
        "--raised": "#2a2c31",
        "--sidebar": "#19191b",
        "--list": "#1c1d20",
        "--text": "#e9e9ea",
        "--muted": "#a3a5a9",
        "--subtle": "#8c8f94",
        "--line": "#2d2e32",
        "--line-strong": "#3d3f44",
        "--hover": "rgb(255 255 255 / .05)",
        "--selected": "#323338",
        "--paper": "#26272b",
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
        "--neutral-bg": "#2a2b2f",
        "--overlay": "oklch(0% 0 0 / .5)",
        "--shadow": "oklch(0% 0 0 / .45)",
        "--primary": "#eceded",
        "--primary-hover": "#d3d4d6",
        "--on-primary": "#1f2023",
        "--field-hover": "#5d6066",
        "--field-focus": "#8a8d93",
      },
    },
  },
});
globalStyle(":root[data-theme=\"dark\"]", {
  colorScheme: "dark",
  vars: {
    "--canvas": "#1f2023",
    "--raised": "#2a2c31",
    "--sidebar": "#19191b",
    "--list": "#1c1d20",
    "--text": "#e9e9ea",
    "--muted": "#a3a5a9",
    "--subtle": "#8c8f94",
    "--line": "#2d2e32",
    "--line-strong": "#3d3f44",
    "--hover": "rgb(255 255 255 / .05)",
    "--selected": "#323338",
    "--paper": "#26272b",
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
    "--neutral-bg": "#2a2b2f",
    "--overlay": "oklch(0% 0 0 / .5)",
    "--shadow": "oklch(0% 0 0 / .45)",
    "--primary": "#eceded",
    "--primary-hover": "#d3d4d6",
    "--on-primary": "#1f2023",
    "--field-hover": "#5d6066",
    "--field-focus": "#8a8d93",
  },
});
globalStyle("*, *::before, *::after", { boxSizing: "border-box" });
globalStyle("html, body, #app", { height: "100%", margin: "0" });
globalStyle("body", {
  background: vars.canvas, color: vars.text, font: `400 ${vars.textBody}/1.55 ${vars.fontBody}`,
  fontFeatureSettings: "\"cv11\", \"ss01\"", WebkitFontSmoothing: "antialiased", lineBreak: "strict",
  textWrap: "pretty",
});
/**
 * Headings and the short lines under them break evenly, never one long line and a stub, and only where the words
 * allow: at punctuation and spaces, not inside a word (模|型) or a bracket; a run too long for the line still breaks.
 */
globalStyle("h1, h2, h3", { textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere" });
globalStyle("button, input, select, textarea", { font: "inherit", color: "inherit" });
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
