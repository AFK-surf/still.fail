import { globalStyle } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { passageFlashHeldKeyframes, passageFlashKeyframes, searchStrokeKeyframes, strokeRevealKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { STILL, stillAtOnce, stillFlash } from "@stillfail/ui/styles/still.ts";
import { LEAVE_EASE_CSS, MOVE_EASE_CSS, OUT_EASE_CSS } from "@stillfail/ui/curves.ts";
import { PALETTE, TONE, type Tone } from "@stillfail/ui/palette.ts";

/** A colour of the palette (@stillfail/ui/palette.ts) as CSS: a tone's ground is its ink at the theme's opacity. */
const color = (c: string | Tone, theme: "light" | "dark") =>
  typeof c === "string" ? c : `color-mix(in srgb, ${c.tone} ${Math.round(TONE[theme] * 100)}%, transparent)`;

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
 * The screen's safe area (a phone's status bar, notch or island, its home indicator or navigation buttons), as every
 * style reads it: through these, never env() itself (scripts/check.sh), so the stories (web/stories) can put the page
 * on each phone's.
 */
globalStyle(":root", {
  vars: {
    "--safe-top": "env(safe-area-inset-top, 0px)", "--safe-bottom": "env(safe-area-inset-bottom, 0px)",
    "--safe-left": "env(safe-area-inset-left, 0px)", "--safe-right": "env(safe-area-inset-right, 0px)",
  },
});
/**
 * Zork's approved desktop tokens (apps/zork-design-pc/tokens), so still.fail reads as
 * part of the same family: white canvas, warm sidebar, ink text, brand orange,
 * status colours with their own tinted grounds. Dark follows the Zork client.
 */
globalStyle(":root", {
  colorScheme: "light",
  vars: {
    "--font-body": "\"Inter Variable\", -apple-system, BlinkMacSystemFont, \"PingFang SC\", \"Hiragino Sans GB\", sans-serif",
    "--font-text": "var(--font-body)",
    "--font-mono": "ui-monospace, SFMono-Regular, Menlo, monospace",
    "--canvas": color(PALETTE.light.canvas, "light"),
    // What floats over the canvas (the composer): a grey ground of its own, a step darker than the canvas in light and
    // a step lighter in dark, where a shadow does not show.
    "--raised": color(PALETTE.light.raised, "light"),
    // What is lifted out of a tinted track (a segmented choice's thumb), drawn over the track: white, a shadow lifting
    // it; in dark, where a shadow does not show, the ink at 12% over the track (the ink at 6%), a step lighter than it on
    // whatever ground it lies on (the canvas was darker than a track on the page, 1.07:1).
    "--lifted": color(PALETTE.light.lifted, "light"),
    "--sidebar": color(PALETTE.light.sidebar, "light"),
    "--list": color(PALETTE.light.list, "light"),
    "--text": color(PALETTE.light.text, "light"),
    "--muted": color(PALETTE.light.muted, "light"),
    "--subtle": color(PALETTE.light.subtle, "light"),
    // What is drawn to be seen with nothing in it, at its faintest (a line, a gauge's empty cell, a placeholder's block):
    // the ink at an opacity, so it stands as far off whatever it lies on (the page, a card, a menu), at least 1.25 to 1
    // (mbui ui/contrast.mbt); an opaque grey was that on the page alone (a station's empty cells on its card, 1.03 to
    // 1 in the dark, 2026-10-26). The same on the canvas as the grey it was.
    "--line": color(PALETTE.light.line, "light"),
    "--line-strong": color(PALETTE.light.line_strong, "light"),
    "--hover": color(PALETTE.light.hover, "light"),
    "--selected": color(PALETTE.light.selected, "light"),
    "--paper": color(PALETTE.light.paper, "light"),
    "--accent": color(PALETTE.light.accent, "light"),
    // A tone's ground (a pill's, a mention's, an error's): its ink at an opacity, as --line and --neutral-bg, so it
    // stands a step off whatever it lies on (the page, a card, a menu: 1.25 to 1 and more) and its ink still reads on it
    // (4.5 to 1). Opaque ones fitted to the page were 1.0 to 1.1 off a card in the dark (2026-10-27), their pills not seen.
    "--accent-text": color(PALETTE.light.accent_text, "light"),
    "--accent-bg": color(PALETTE.light.accent_bg, "light"),
    "--blue": color(PALETTE.light.blue, "light"),
    "--code-inline": color(PALETTE.light.code_ink, "light"),
    "--blue-bg": color(PALETTE.light.blue_bg, "light"),
    "--green": color(PALETTE.light.green_ink, "light"),
    "--green-bg": color(PALETTE.light.green_bg, "light"),
    "--amber": color(PALETTE.light.warn_ink, "light"),
    "--amber-bg": color(PALETTE.light.amber_bg, "light"),
    "--red": color(PALETTE.light.red, "light"),
    "--red-bg": color(PALETTE.light.red_bg, "light"),
    // A merged pull request's, a completed issue's (GitHub's purple, a step deeper to read on its ground).
    "--purple": color(PALETTE.light.purple, "light"),
    "--purple-bg": color(PALETTE.light.purple_bg, "light"),
    // A quiet ground under what is in it (a pill, a bubble), a step off whatever it lies on as --line is, fainter.
    "--neutral-bg": color(PALETTE.light.neutral_bg, "light"),
    "--overlay": color(PALETTE.light.overlay, "light"),
    "--shadow": color(PALETTE.light.shadow, "light"),
    "--primary": color(PALETTE.light.primary, "light"),
    "--primary-hover": color(PALETTE.light.primary_hover, "light"),
    "--on-primary": color(PALETTE.light.on_primary, "light"),
    "--field-hover": color(PALETTE.light.field_hover, "light"),
    "--field-focus": color(PALETTE.light.field_focus, "light"),
    "--online": color(PALETTE.light.online, "light"),
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
    // one curve for each thing a motion can be (@stillfail/ui/curves.ts): what comes, what goes, a move
    "--ease-out": OUT_EASE_CSS,
    "--ease-leave": LEAVE_EASE_CSS,
    "--ease-move": MOVE_EASE_CSS,
    "--dur": "140ms",
  },
});
globalStyle(":root:not([data-theme=\"light\"])", {
  "@media": {
    "(prefers-color-scheme: dark)": {
      colorScheme: "dark",
      vars: {
        "--canvas": color(PALETTE.dark.canvas, "dark"),
        "--raised": color(PALETTE.dark.raised, "dark"),
        "--lifted": color(PALETTE.dark.lifted, "dark"),
        "--sidebar": color(PALETTE.dark.sidebar, "dark"),
        "--list": color(PALETTE.dark.list, "dark"),
        "--text": color(PALETTE.dark.text, "dark"),
        "--muted": color(PALETTE.dark.muted, "dark"),
        "--subtle": color(PALETTE.dark.subtle, "dark"),
        "--line": color(PALETTE.dark.line, "dark"),
        "--line-strong": color(PALETTE.dark.line_strong, "dark"),
        "--hover": color(PALETTE.dark.hover, "dark"),
        "--selected": color(PALETTE.dark.selected, "dark"),
        "--paper": color(PALETTE.dark.paper, "dark"),
        "--accent": color(PALETTE.dark.accent, "dark"),
        "--accent-text": color(PALETTE.dark.accent_text, "dark"),
        "--accent-bg": color(PALETTE.dark.accent_bg, "dark"),
        "--blue": color(PALETTE.dark.blue, "dark"),
        "--code-inline": color(PALETTE.dark.code_ink, "dark"),
        "--blue-bg": color(PALETTE.dark.blue_bg, "dark"),
        "--green": color(PALETTE.dark.green_ink, "dark"),
        "--green-bg": color(PALETTE.dark.green_bg, "dark"),
        "--amber": color(PALETTE.dark.warn_ink, "dark"),
        "--amber-bg": color(PALETTE.dark.amber_bg, "dark"),
        "--red": color(PALETTE.dark.red, "dark"),
        "--red-bg": color(PALETTE.dark.red_bg, "dark"),
        "--purple": color(PALETTE.dark.purple, "dark"),
        "--purple-bg": color(PALETTE.dark.purple_bg, "dark"),
        "--neutral-bg": color(PALETTE.dark.neutral_bg, "dark"),
        "--overlay": color(PALETTE.dark.overlay, "dark"),
        "--shadow": color(PALETTE.dark.shadow, "dark"),
        "--primary": color(PALETTE.dark.primary, "dark"),
        "--primary-hover": color(PALETTE.dark.primary_hover, "dark"),
        "--on-primary": color(PALETTE.dark.on_primary, "dark"),
        "--field-hover": color(PALETTE.dark.field_hover, "dark"),
        "--field-focus": color(PALETTE.dark.field_focus, "dark"),
      },
    },
  },
});
globalStyle(":root[data-theme=\"dark\"]", {
  colorScheme: "dark",
  vars: {
    "--canvas": color(PALETTE.dark.canvas, "dark"),
    "--raised": color(PALETTE.dark.raised, "dark"),
    "--lifted": color(PALETTE.dark.lifted, "dark"),
    "--sidebar": color(PALETTE.dark.sidebar, "dark"),
    "--list": color(PALETTE.dark.list, "dark"),
    "--text": color(PALETTE.dark.text, "dark"),
    "--muted": color(PALETTE.dark.muted, "dark"),
    "--subtle": color(PALETTE.dark.subtle, "dark"),
    "--line": color(PALETTE.dark.line, "dark"),
    "--line-strong": color(PALETTE.dark.line_strong, "dark"),
    "--hover": color(PALETTE.dark.hover, "dark"),
    "--selected": color(PALETTE.dark.selected, "dark"),
    "--paper": color(PALETTE.dark.paper, "dark"),
    "--accent": color(PALETTE.dark.accent, "dark"),
    "--accent-text": color(PALETTE.dark.accent_text, "dark"),
    "--accent-bg": color(PALETTE.dark.accent_bg, "dark"),
    "--blue": color(PALETTE.dark.blue, "dark"),
    "--code-inline": color(PALETTE.dark.code_ink, "dark"),
    "--blue-bg": color(PALETTE.dark.blue_bg, "dark"),
    "--green": color(PALETTE.dark.green_ink, "dark"),
    "--green-bg": color(PALETTE.dark.green_bg, "dark"),
    "--amber": color(PALETTE.dark.warn_ink, "dark"),
    "--amber-bg": color(PALETTE.dark.amber_bg, "dark"),
    "--red": color(PALETTE.dark.red, "dark"),
    "--red-bg": color(PALETTE.dark.red_bg, "dark"),
    "--purple": color(PALETTE.dark.purple, "dark"),
    "--purple-bg": color(PALETTE.dark.purple_bg, "dark"),
    "--neutral-bg": color(PALETTE.dark.neutral_bg, "dark"),
    "--overlay": color(PALETTE.dark.overlay, "dark"),
    "--shadow": color(PALETTE.dark.shadow, "dark"),
    "--primary": color(PALETTE.dark.primary, "dark"),
    "--primary-hover": color(PALETTE.dark.primary_hover, "dark"),
    "--on-primary": color(PALETTE.dark.on_primary, "dark"),
    "--field-hover": color(PALETTE.dark.field_hover, "dark"),
    "--field-focus": color(PALETTE.dark.field_focus, "dark"),
  },
});
globalStyle("*, *::before, *::after", { boxSizing: "border-box" });
globalStyle("html, body, #app", { height: "100%", margin: "0" });
/**
 * Lines break the usual way, not `text-wrap: pretty`: Safari's (iOS's every browser) breaks Chinese in a narrow box
 * after every character (a 64px label: 缓/存/命/中/率), and a line of 5 to 30 characters in one a character wide.
 * The app's own words have their digits all one width (`tabular-nums`, after `font`, which resets it): a percentage, a
 * time running, a count keep their width as they change. What people wrote (where `vars.fontText` is set) and a book's
 * column keep the font's own figures (`fontVariantNumeric: "normal"` there).
 */
globalStyle("body", {
  background: vars.canvas, color: vars.text, font: `400 ${vars.textBody}/1.55 ${vars.fontBody}`, fontVariantNumeric: "tabular-nums",
  fontFeatureSettings: "\"cv11\", \"ss01\"", WebkitFontSmoothing: "antialiased", lineBreak: "strict",
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
/**
 * A checkbox as the app draws its controls, not the system's blue one: a small soft square with a line round it;
 * ticked, the primary colour with a check in the colour on it (a switch's on, ui.tsx Switch).
 */
globalStyle('input[type="checkbox"]', {
  appearance: "none", display: "inline-grid", placeItems: "center", flex: "none", width: "18px", height: "18px", margin: "0",
  border: `1px solid ${vars.lineStrong}`, borderRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: vars.canvas, cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}, border-color ${vars.dur} ${vars.easeOut}`,
});
globalStyle('input[type="checkbox"]:hover:not(:disabled)', { borderColor: vars.fieldHover });
globalStyle('input[type="checkbox"]:checked', { background: vars.primary, borderColor: vars.primary });
globalStyle('input[type="checkbox"]::before', {
  content: '""', width: "12px", height: "12px", background: vars.onPrimary, transform: "scale(0)",
  transition: `transform ${vars.dur} ${vars.easeOut}`,
  mask: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M2.5 6.2l2.4 2.4 4.6-5'/%3E%3C/svg%3E") center / contain no-repeat`,
});
globalStyle('input[type="checkbox"]:checked::before', { transform: "scale(1)" });
globalStyle('input[type="checkbox"]:disabled', { opacity: ".45", cursor: "default" });
globalStyle('input[type="checkbox"]:focus-visible', { outline: `2px solid ${vars.fieldFocus}`, outlineOffset: "2px" });
globalStyle("code, pre", { fontFamily: vars.fontMono });
globalStyle("[hidden]", { display: "none !important" });
/**
 * Motion reduced (styles/still.ts): every animation in 1ms, once, its end and its end events as ever; every transition
 * none, its change there at once (after its delay, if it has one). Not 1ms for transitions: with every element's
 * `transition-property: all`, everything would go over 1ms, and a thing shown again (visibility) stayed hidden for
 * the frame the change was in. A loop says where it rests (stillLoop): once in 1ms it stands as it is without it.
 */
globalStyle(`${STILL} *, ${STILL} *::before, ${STILL} *::after`, {
  animationDuration: "1ms !important", animationIterationCount: "1 !important", transitionDuration: "0s !important",
});
/** The app starting: the mark, still; what it waits for comes up only if it takes a while. */
globalStyle(".splash", {
  position: "fixed", inset: "0", display: "grid", placeContent: "center", justifyItems: "center", gap: "16px",
  padding: "24px", background: vars.canvas, textAlign: "center",
});
globalStyle(".splash-mark", { display: "block" });
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
// The 1ms of every motion, which `*` does not reach.
globalStyle(`${STILL}::view-transition-group(*), ${STILL}::view-transition-old(*), ${STILL}::view-transition-new(*)`, { animationDuration: "1ms !important" });
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
  strokeDasharray: "1", strokeDashoffset: "1", animation: `${searchStrokeKeyframes} 520ms ease-in-out forwards`,
});
globalStyle("[data-search-marks][data-settled] path", { animation: "none", strokeDashoffset: "0" });
globalStyle(`${STILL} [data-search-marks] path`, stillAtOnce);
/** The words in a found line (⌘K's and the phones' search, Marked.tsx): the same hand-drawn stroke under each, drawn in
 *  from its left one after another (`--n`: which it is). */
const STROKE = `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 9' preserveAspectRatio='none'%3E%3Cpath d='M1 6 C 25 3, 55 8, 99 4' fill='none' stroke='black' stroke-width='3' stroke-linecap='round'/%3E%3C/svg%3E")`;
globalStyle("mark[data-stroke]", { position: "relative" });
globalStyle("mark[data-stroke]::after", {
  content: '""', position: "absolute", left: "-2px", right: "-2px", top: "calc(100% - 5px)", height: "6px", pointerEvents: "none",
  background: vars.accent, maskImage: STROKE, maskSize: "100% 100%",
  maskRepeat: "no-repeat", clipPath: "inset(0 100% 0 0)",
  animation: `${strokeRevealKeyframes} 520ms ease-in-out calc(var(--n, 0) * 180ms) forwards`,
});
globalStyle(`${STILL} mark[data-stroke]::after`, stillAtOnce);
/** The quoted passage, marked for a moment where it was said after following a quote (Chat.tsx flashRange): as a
 *  passage picked in it is coloured, the accent's ground behind each of its lines, under the words (the layer is below the text
 *  of the block it is in). */
globalStyle("[data-passage-host]", { position: "relative", isolation: "isolate" });
globalStyle("[data-passage-marks]", { position: "absolute", inset: "0", zIndex: "-1", pointerEvents: "none" });
globalStyle("[data-passage-marks] > span", {
  position: "absolute",
  background: `color-mix(in srgb, ${vars.accent} 26%, transparent)`, animation: `${passageFlashKeyframes} 2400ms both`,
});
// own corner: a passage's ends, round where it starts and ends, square where it runs on to the next line (sf/align.mbt)
globalStyle("[data-passage-marks] > span[data-start]", { borderTopLeftRadius: `calc(6px * ${vars.cornerScale})`, borderBottomLeftRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape }); // own corner: a passage's start
globalStyle("[data-passage-marks] > span[data-end]", { borderTopRightRadius: `calc(6px * ${vars.cornerScale})`, borderBottomRightRadius: `calc(6px * ${vars.cornerScale})`, cornerShape: vars.cornerShape }); // own corner: a passage's end
globalStyle(`${STILL} [data-passage-marks] > span`, stillFlash(passageFlashHeldKeyframes, "2400ms"));
