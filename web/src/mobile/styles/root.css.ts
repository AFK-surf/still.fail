import { globalStyle, style } from "@vanilla-extract/css";
import { mRiseKeyframes } from "@stillfail/ui/styles/keyframes.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import * as waitCss from "@stillfail/ui/waiting.css.ts";

/** The narrow screen's colours in the dark (root.css.ts m, mDark). */
const darkVars = {
  "--m-bg": "#1B1C1F",
  "--m-surface": "#26272B",
  "--m-surface2": "#2C2D31",
  "--raised": "#2A2C31",
  "--m-ink": "#ECECED",
  "--m-muted": "#B8BBC1",
  "--m-subtle": "#B8BBC1",
  "--m-line": "rgb(236 236 237 / .122)",
  "--m-accent": "#E8734F",
  "--m-accent-bg": "color-mix(in srgb, #F6A383 16%, transparent)",
  "--m-accent-ink": "#F6A383",
  "--m-green": "#5CC08A",
  "--m-red": "#FE9D8C",
  "--m-warn-ink": "#EEAA44",
  "--m-green-ink": "#66CA93",
  "--m-on-red": "#1B1C1F",
  "--m-blue": "#8EB8FE",
  "--m-chip": "#313237",
  "--m-bubble": "rgb(236 236 237 / .106)",
  "--m-thumb": "#3A3B40",
};

/**
 * The narrow screen, as the Android app draws it (apps/android/…/ui/Theme.kt, Glass.kt, Parts.kt, Sheet.kt and the
 * screens): warm paper, ink, and one ember orange that means "this needs you". A dp or an sp is a pixel here.
 */
export const m = style({
  position: "fixed", inset: "0", overflow: "hidden", background: "var(--m-bg)", color: "var(--m-ink)",
  fontSize: vars.textBody, lineHeight: "1.4", WebkitTapHighlightColor: "transparent", WebkitTextSizeAdjust: "100%",
  colorScheme: "light",
  vars: {
    // The phone's type, as Android's: a size up from the wide screen's, what is typed 16 (iOS zooms into less).
    [vars.textCaption]: "12px",
    [vars.textMeta]: "13px",
    [vars.textUi]: "15px",
    [vars.textBody]: "15px",
    [vars.textInput]: "16px",
    [vars.textTitle]: "16px",
    "--m-bg": "#F5F3EF",
    "--m-surface": "#FFFFFF",
    "--m-surface2": "#FBFAF7",
    // Its floating capsules white over the warm page (the wide screen's grey showed too little against it); dark as the wide screen's.
    "--raised": "#FFFFFF",
    "--m-ink": "#24272B",
    "--m-muted": "#535559",
    "--m-subtle": "#535559",
    // The ink at an opacity, as the wide screen's --line and --neutral-bg (styles/global.css.ts): as far off whatever
    // they lie on, the page, a card or a sheet.
    "--m-line": "rgb(50 45 36 / .141)",
    "--m-accent": "#CC5A34",
    // The accent's ink at an opacity, as the wide screen's --accent-bg (styles/global.css.ts): a step off the page, a
    // card or a sheet alike.
    "--m-accent-bg": "color-mix(in srgb, #8F2B01 18%, transparent)",
    "--m-accent-ink": "#8F2B01",
    "--m-green": "#2F8F5B",
    "--m-red": "#991302",
    "--m-warn": "#D9962B",
    // Words and icons in warn's colour: its amber dark enough to read (4.5:1), as --m-accent-ink is the accent's.
    "--m-warn-ink": "#6E4802",
    // Words in green (verified, online): its ink, as --m-accent-ink is the accent's; --m-green is a dot's, a switch's.
    "--m-green-ink": "#045B33",
    // What is said on the red (a solid danger button, a failed mark): white on the light theme's deep red, the page's ink
    // on the dark theme's light one (white on it was 2.4:1).
    "--m-on-red": "#FFFFFF",
    "--m-blue": "#0047AE",
    "--m-chip": "#E8E4DC",
    // A step darker than the page (the wide screen's grey sat as light as this warm page, and its bubbles barely showed).
    "--m-bubble": "rgb(50 45 36 / .075)",
    "--m-thumb": "#FFFFFF",
    "--m-ease": "cubic-bezier(.2, .8, .2, 1)",
    "--m-standard": "cubic-bezier(.4, 0, .2, 1)",
    "--m-top": "var(--safe-top)",
    "--m-foot": "var(--safe-bottom)",
  },
  selectors: {
    ":root[data-theme=\"dark\"] &": {
      colorScheme: "dark",
      vars: darkVars,
    },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        ":root:not([data-theme=\"light\"]) &": {
          colorScheme: "dark",
          vars: darkVars,
        },
      },
    },
  },
});
/**
 * The page under the narrow screen its paper too: an iPhone's home-screen app paints its status bar from the page's
 * background (iOS 26 reads html/body, not theme-color), and the wide screen's white canvas there stood as a white band
 * over the warm top bar.
 */
globalStyle(`:root:has(${m}), :root:has(${m}) body`, { background: "#F5F3EF" });
globalStyle(`:root[data-theme="dark"]:has(${m}), :root[data-theme="dark"]:has(${m}) body`, { background: darkVars["--m-bg"] });
globalStyle(`:root:not([data-theme="light"]):has(${m}), :root:not([data-theme="light"]):has(${m}) body`, {
  "@media": { "(prefers-color-scheme: dark)": { background: darkVars["--m-bg"] } },
});
/**
 * Where the phone draws what the wide screen draws, with the wide screen's own parts (a chat's messages, its composer):
 * the wide screen's styles hold there, the phone's resets below do not reach in, and its type is a size up for the
 * narrow screen.
 */
/**
 * The narrow screen's parts drawn where its root is not (over the dark image viewer, which is in a portal of the
 * document's): its colours, the dark ones, and its curves and insets.
 */
export const mDark = style({
  colorScheme: "dark",
  vars: {
    ...darkVars, "--m-ease": "cubic-bezier(.2, .8, .2, 1)", "--m-standard": "cubic-bezier(.4, 0, .2, 1)",
    "--m-top": "var(--safe-top)", "--m-foot": "var(--safe-bottom)",
  },
});

export const wide = style({
  color: vars.text, fontSize: vars.textBody, lineHeight: "1.55",
  vars: { [vars.textMeta]: "13px", [vars.textUi]: "15px", [vars.textBody]: "15px", [vars.neutralBg]: "var(--m-bubble)" },
});
globalStyle(`${m} button:not(${wide} *)`, { font: "inherit" });
// A button's words the colour of what it is in, unless its own style says otherwise: a reset at no weight (:where), so
// a shared control's own colour wins (a primary button's white on the ink: inherited, it was the ink on the ink, 1:1).
globalStyle(`:where(${m} button:not(${wide} *))`, { color: "inherit" });
globalStyle(`${m} button`, { WebkitTapHighlightColor: "transparent" });
globalStyle(`${m} p:not(${wide} *)`, { margin: "0" });
globalStyle(`${m} [data-enter]:not(${wide} *)`, { animation: `${mRiseKeyframes} 320ms var(--m-standard) both` });

// Waiting (@stillfail/ui waiting.tsx) on the phone: its pill in the phone's grey (as its message bubbles), a page's bones
// in the phone's line, not the wide screen's (what they are drawn over is the page's own, as it will be).
globalStyle(`${m} ${waitCss.pill}`, { vars: { [vars.neutralBg]: "var(--m-bubble)", [vars.line]: "var(--m-line)" } });
globalStyle(`${m} ${waitCss.boneMarks}`, { vars: { [vars.line]: "var(--m-line)" } });
